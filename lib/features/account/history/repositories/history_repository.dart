import '../../models/account_models.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../../../core/services/auth_session_service.dart';

abstract interface class HistoryRepository {
  Future<List<RideHistoryItem>> list();
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
        pickup: '${item['pickupAddress'] ?? item['pickup'] ?? ''}',
        destination:
            '${item['destinationAddress'] ?? item['destination'] ?? ''}',
        date: DateTime.tryParse(
                '${item['createdAtUtc'] ?? item['date'] ?? ''}') ??
            DateTime.now(),
        amount: rawAmount is num ? rawAmount.toDouble() : 0,
        status: _status(item['status']),
        serviceKindName: item['serviceKindNameAr']?.toString(),
        serviceName: item['serviceNameAr']?.toString(),
        driverId: item['driverId']?.toString(),
      );
    }).toList(growable: false);
  }

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
