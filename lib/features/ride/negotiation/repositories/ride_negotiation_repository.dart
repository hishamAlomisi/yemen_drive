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
    final id =
        result is ApiSuccess ? _map(result.data)['id']?.toString() : null;
    if (id == null || id.isEmpty)
      throw const FormatException('Invalid ride response.');
    return id;
  }

  @override
  Stream<DriverOffer> watchOffers(String requestId) async* {
    final seen = <String>{};
    for (var i = 0; i < 60; i++) {
      final result = await _client.execute<Object?>(
          model: 'RideModel', operation: 'get', data: {'id': requestId});
      final offers = result is ApiSuccess ? _map(result.data)['offers'] : null;
      if (offers is List) {
        for (final raw in offers.whereType<Map<Object?, Object?>>()) {
          final item = Map<String, Object?>.from(raw);
          final id = item['id']?.toString() ?? '';
          if (id.isEmpty || !seen.add(id)) continue;
          yield DriverOffer(
            id: id,
            driverName: item['driverName']?.toString() ?? '',
            vehicleSummary: item['vehicleModel']?.toString() ?? '',
            price: _number(item['amount']),
            rating: 0,
            etaMinutes: 0,
            expiresAt:
                DateTime.tryParse(item['expiresAtUtc']?.toString() ?? ''),
          );
        }
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
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
