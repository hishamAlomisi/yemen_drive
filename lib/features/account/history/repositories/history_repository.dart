import '../../models/account_models.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../../../core/services/auth_session_service.dart';

abstract interface class HistoryRepository {
  Future<List<RideHistoryItem>> list();
  Future<void> cancelPaidCashRide(String rideId,
      {required bool creditCustomerWallet});
}

class ApiHistoryRepository implements HistoryRepository {
  const ApiHistoryRepository(this._client, this._session);
  final ApiClient _client;
  final AuthSessionService _session;
  @override
  Future<List<RideHistoryItem>> list() async {
    if (!_session.isAuthenticated.value) return const [];
    final result = await _client.execute<Object?>(
        model: 'RideHistoryModel', operation: 'list', data: const {});
    if (result is! ApiSuccess || result.data is! List) return const [];
    return (result.data as List).whereType<Map<String, dynamic>>().map((item) {
      final rawAmount =
          item['amount'] ?? item['customerPrice'] ?? item['serverPrice'];
      return RideHistoryItem(
        id: '${item['id'] ?? ''}',
        pickup:
            '${item['pickupDisplayName'] ?? item['pickup'] ?? item['pickupAddress'] ?? ''}',
        destination:
            '${item['destinationDisplayName'] ?? item['destination'] ?? item['destinationAddress'] ?? ''}',
        date: DateTime.tryParse(
                '${item['createdAtUtc'] ?? item['date'] ?? ''}') ??
            DateTime.now(),
        amount: rawAmount is num ? rawAmount.toDouble() : 0,
        status: _status(item['status']),
        totalDue: _number(item['totalAmount']) > 0
            ? _number(item['totalAmount'])
            : (rawAmount is num ? rawAmount.toDouble() : 0),
        cancellationFee: _number(item['cancellationFee']),
        isCashPaid:
            '${item['paidPaymentProvider'] ?? ''}'.toLowerCase() == 'cash',
        serviceKindName: item['serviceKindNameAr']?.toString(),
        serviceName: item['serviceNameAr']?.toString(),
        driverId: item['driverId']?.toString(),
      );
    }).toList(growable: false);
  }

  @override
  Future<void> cancelPaidCashRide(
    String rideId, {
    required bool creditCustomerWallet,
  }) async {
    final result = await _client.execute<Object?>(
      model: 'RideModel',
      operation: 'cancel',
      data: <String, Object?>{
        'id': rideId,
        'cashCancellationRefundMethod': creditCustomerWallet ? 2 : 1,
      },
    );
    if (result is! ApiSuccess) {
      throw const FormatException('تعذر إلغاء الرحلة النقدية من الخادم.');
    }
  }

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;

  RideHistoryStatus _status(Object? value) {
    final normalized = '$value'.toLowerCase();
    if (normalized == 'completed' || normalized == '6')
      return RideHistoryStatus.completed;
    if (normalized == 'cancelled' ||
        normalized == 'canceled' ||
        normalized == '7') return RideHistoryStatus.cancelled;
    return RideHistoryStatus.upcoming;
  }
}
