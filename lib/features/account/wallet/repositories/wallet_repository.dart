import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../../../core/services/auth_session_service.dart';
import '../../models/account_models.dart';

abstract interface class WalletRepository {
  Future<List<WalletTransaction>> transactions();
  Future<double> addAmount(
      {required double amount,
      required String paymentMethodId,
      String? bankAccountNumber});
}

class ApiWalletRepository implements WalletRepository {
  const ApiWalletRepository(this._client, this._session);
  final ApiClient _client;
  final AuthSessionService _session;

  @override
  Future<List<WalletTransaction>> transactions() async {
    if (!_session.isAuthenticated.value) return const [];
    final result =
        await _client.execute<Object?>(model: 'WalletModel', operation: 'get');
    if (result is! ApiSuccess || result.data is! Map) return const [];
    final raw = (result.data as Map)['transactions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => WalletTransaction(
              id: '${item['id'] ?? ''}',
              title: '${item['description'] ?? item['title'] ?? 'عملية محفظة'}',
              date: DateTime.tryParse('${item['createdAtUtc'] ?? ''}') ??
                  DateTime.now(),
              amount: (item['amount'] as num?)?.toDouble() ?? 0,
              isCredit: item['type'] == 0 || item['isCredit'] == true,
            ))
        .toList(growable: false);
  }

  @override
  Future<double> addAmount(
      {required double amount,
      required String paymentMethodId,
      String? bankAccountNumber}) async {
    if (!_session.isAuthenticated.value)
      throw StateError('يجب تسجيل الدخول لشحن المحفظة.');
    final result = await _client
        .execute<Object?>(model: 'WalletModel', operation: 'add', data: {
      'amount': amount,
      "type": 0,
      "description": "رصيد تجريبي",
      "externalReference": "POSTMAN-001"
    });
    if (result is ApiSuccess) return amount;
    throw Exception('تعذر شحن المحفظة');
  }
}
