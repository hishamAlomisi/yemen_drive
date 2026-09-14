import 'dart:async';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../models/ride_models.dart';

abstract interface class RideNegotiationRepository {
  Future<RideQuote> getQuote({
    required int serviceKindId,
    required int serviceCatalogItemId,
    required RideCoordinate pickup,
    required RideCoordinate destination,
    double? distanceKm,
    double? durationMinutes,
  });

  Future<String> createRequest(RideRequestDraft draft);
  Stream<DriverOffer> watchOffers(String requestId);
  Future<void> acceptOffer(String requestId, String offerId);
  Future<void> rejectOffer(String requestId, String offerId);
  Future<void> cancelRequest(String requestId);
  Future<Map<String, Object?>?> findLatestOpenRide();
  Future<Map<String, Object?>> getRideDetail(String requestId);
  Future<void> publishPassengerLocation(
    String requestId,
    RideCoordinate location, {
    double? bearing,
    double? speed,
  });
}

/// REST implementation. The API returns the
/// current ride snapshot, so offers are observed by lightweight polling until
/// SignalR is enabled for the client.
class ApiRideNegotiationRepository implements RideNegotiationRepository {
  const ApiRideNegotiationRepository(this._client);
  final ApiClient _client;

  @override
  Future<RideQuote> getQuote({
    required int serviceKindId,
    required int serviceCatalogItemId,
    required RideCoordinate pickup,
    required RideCoordinate destination,
    double? distanceKm,
    double? durationMinutes,
  }) async {
    final result = await _client.execute<Object?>(
      model: 'PricingModel',
      operation: 'report',
      data: <String, Object?>{
        'serviceKindId': serviceKindId,
        'serviceCatalogItemId': serviceCatalogItemId,
        'distanceKm': distanceKm ?? _distance(pickup, destination),
        'durationMinutes': durationMinutes ?? 0,
      },
    );
    if (result is! ApiSuccess) {
      throw const FormatException('تعذر جلب تسعيرة الخدمة من الخادم.');
    }
    final body = _map(result.data);
    final amountValue = body['amount'] ?? body['suggestedPrice'];
    final amount = _number(amountValue);
    if (amount <= 0) {
      throw const FormatException('الخدمة لا تحتوي على قاعدة تسعير فعالة.');
    }
    return RideQuote(
      suggestedPrice: amount,
      minPrice: amount,
      maxPrice: amount,
      priceStep: 100,
      serviceFee: _number(body['serviceFee']),
      currency: body['currency']?.toString() ?? 'ر.ي',
    );
  }

  @override
  Future<String> createRequest(RideRequestDraft draft) async {
    final result = await _client.execute<Object?>(
      model: 'RideModel',
      operation: 'add',
      data: <String, Object?>{
        'serviceKindId': draft.serviceKindId,
        'serviceCatalogItemId': draft.serviceCatalogItemId,
        'pickupLabel': draft.pickup,
        'pickupAddress': draft.pickupAddress,
        'pickupLatitude': draft.pickupCoordinate.latitude,
        'pickupLongitude': draft.pickupCoordinate.longitude,
        'destinationLabel': draft.destination,
        'destinationAddress': draft.destinationAddress,
        'destinationLatitude': draft.destinationCoordinate.latitude,
        'destinationLongitude': draft.destinationCoordinate.longitude,
        'customerPrice': draft.offeredPrice,
        'idempotencyKey': draft.idempotencyKey,
      },
    );
    if (result is ApiFailure) {
      final problem = result.problem;
      final details = problem.errors.values.expand((messages) => messages).join(' ');
      throw FormatException(
        details.isNotEmpty ? details : (problem.detail ?? problem.title),
      );
    }
    final success = result as ApiSuccess<Object?>;
    final id = _map(success.data)['id']?.toString();
    if (id == null || id.isEmpty)
      throw const FormatException('لم يُرجع الخادم رقم طلب الرحلة.');
    return id;
  }

  @override
  Stream<DriverOffer> watchOffers(String requestId) async* {
    final seen = <String>{};
    for (var i = 0; i < 60; i++) {
      final result = await _client.execute<Object?>(
          model: 'RideModel', operation: 'get', data: {'id': requestId});
      if (result is! ApiSuccess) {
        throw const FormatException('تعذر تحديث عروض السائقين من الخادم.');
      }
      final offers = _map(result.data)['offers'];
      if (offers is List) {
        for (final raw in offers) {
          final item = _map(raw);
          if (item.isEmpty) continue;
          final id = item['id']?.toString() ?? '';
          if (id.isEmpty || !seen.add(id)) continue;
          final expiresAt = _serverUtcDateTime(item['expiresAtUtc']);
          final status = _offerStatus(item['status']);
          // The ride snapshot retains its offer history. An expired or already
          // handled offer must never briefly appear as a new customer choice.
          if (status != DriverOfferStatus.pending ||
              (expiresAt != null && !expiresAt.isAfter(DateTime.now()))) {
            continue;
          }
          yield DriverOffer(
            id: id,
            driverName: item['driverName']?.toString() ?? '',
            vehicleSummary: item['vehicleModel']?.toString() ?? '',
            price: _number(item['amount']),
            rating: 0,
            etaMinutes: 0,
            status: status,
            expiresAt: expiresAt,
            createdAt: _serverUtcDateTime(item['createdAtUtc']),
          );
        }
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  DriverOfferStatus _offerStatus(Object? value) {
    switch (value?.toString().toLowerCase()) {
      case 'accepted':
      case '1':
        return DriverOfferStatus.accepted;
      case 'rejected':
      case '2':
        return DriverOfferStatus.rejected;
      case 'expired':
      case '3':
        return DriverOfferStatus.expired;
      default:
        return DriverOfferStatus.pending;
    }
  }

  /// SQL-backed UTC values can arrive without a trailing timezone marker.
  /// Treat such values as UTC; parsing them as device-local time would make a
  /// valid offer appear expired whenever the device is ahead of UTC.
  static DateTime? _serverUtcDateTime(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    final hasOffset =
        RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(text);
    if (hasOffset) return parsed.toUtc();
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  }

  @override
  Future<void> acceptOffer(String requestId, String offerId) async {
    final result = await _client.execute<Object?>(
        model: 'RideOfferActionModel',
        operation: 'accept',
        data: {'rideId': requestId, 'offerId': offerId});
    if (result is! ApiSuccess) {
      throw const FormatException('تعذر قبول عرض السائق من الخادم.');
    }
  }

  @override
  Future<void> rejectOffer(String requestId, String offerId) async {
    final result = await _client.execute<Object?>(
        model: 'RideOfferActionModel',
        operation: 'reject',
        data: {'rideId': requestId, 'offerId': offerId});
    if (result is! ApiSuccess) {
      throw const FormatException('تعذر رفض عرض السائق من الخادم.');
    }
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    final result = await _client.execute<Object?>(
        model: 'RideModel', operation: 'cancel', data: {'id': requestId});
    if (result is! ApiSuccess) {
      throw const FormatException('تعذر إلغاء طلب الرحلة من الخادم.');
    }
  }

  @override
  Future<Map<String, Object?>?> findLatestOpenRide() async {
    final result = await _client.execute<Object?>(
      model: 'RideModel',
      operation: 'list',
      data: const <String, Object?>{},
    );
    if (result is! ApiSuccess || result.data is! List) return null;

    for (final raw in result.data as List) {
      final ride = _map(raw);
      final status = int.tryParse('${ride['status'] ?? ''}');
      if (status != null && status >= 0 && status <= 5) return ride;
    }
    return null;
  }

  @override
  Future<Map<String, Object?>> getRideDetail(String requestId) async {
    final result = await _client.execute<Object?>(
      model: 'RideModel',
      operation: 'get',
      data: <String, Object?>{'id': requestId},
    );
    if (result is! ApiSuccess) {
      throw const FormatException('تعذر تحديث حالة الرحلة من الخادم.');
    }
    return _map(result.data);
  }

  @override
  Future<void> publishPassengerLocation(
    String requestId,
    RideCoordinate location, {
    double? bearing,
    double? speed,
  }) async {
    final result = await _client.execute<Object?>(
      model: 'RideLocationModel',
      operation: 'add',
      data: <String, Object?>{
        'rideId': requestId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'bearing': bearing,
        'speed': speed,
      },
    );
    if (result is! ApiSuccess) {
      throw const FormatException('تعذر حفظ موقع العميل للرحلة.');
    }
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static double _distance(RideCoordinate a, RideCoordinate b) {
    final dx = (a.latitude - b.latitude).abs();
    final dy = (a.longitude - b.longitude).abs();
    return (dx + dy) * 111;
  }
}
