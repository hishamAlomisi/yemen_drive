import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../../../core/services/auth_session_service.dart';
import '../../models/account_models.dart';

abstract interface class WalletRepository {
  Future<WalletSnapshot> wallet();
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
  Future<WalletSnapshot> wallet() async {
    if (!_session.isAuthenticated.value) {
      return const WalletSnapshot(balance: 0, transactions: <WalletTransaction>[]);
    }
    final result =
        await _client.execute<Object?>(model: 'WalletModel', operation: 'get');
    if (result is! ApiSuccess || result.data is! Map) {
      return const WalletSnapshot(balance: 0, transactions: <WalletTransaction>[]);
    }
    final data = result.data as Map;
    final raw = data['transactions'];
    final transactions = raw is List ? raw
        .whereType<Map>()
        .map((item) => WalletTransaction(
              id: '${item['id'] ?? ''}',
              title: '${item['description'] ?? item['title'] ?? 'عملية محفظة'}',
              date: DateTime.tryParse('${item['createdAtUtc'] ?? ''}') ??
                  DateTime.now(),
              amount: (item['amount'] as num?)?.toDouble() ?? 0,
              isCredit: item['type'] == 0 || item['type'] == 3 || item['type'] == 4 || item['isCredit'] == true,
              type: (item['type'] as num?)?.toInt() ?? 0,
            ))
        .toList(growable: false) : const <WalletTransaction>[];
    return WalletSnapshot(
      balance: (data['balance'] as num?)?.toDouble() ?? 0,
      transactions: transactions,
    );
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
