import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../../../core/services/auth_session_service.dart';
import '../../models/account_models.dart';

abstract interface class WalletRepository {
  Future<WalletSnapshot> wallet();
}

class ApiWalletRepository implements WalletRepository {
  const ApiWalletRepository(this._client, this._session);
  final ApiClient _client;
  final AuthSessionService _session;

  @override
  Future<WalletSnapshot> wallet() async {
    if (!_session.isAuthenticated.value) {
      return const WalletSnapshot(
          balance: 0, transactions: <WalletTransaction>[]);
    }
    final result =
        await _client.execute<Object?>(model: 'WalletModel', operation: 'get');
    if (result is! ApiSuccess || result.data is! Map) {
      return const WalletSnapshot(
          balance: 0, transactions: <WalletTransaction>[]);
    }
    final data = result.data as Map;
    final raw = data['transactions'];
    final transactions = raw is List
        ? raw
            .whereType<Map>()
            .map((item) => WalletTransaction(
                  id: item['id']?.toString() ?? '',
                  title: item['description']?.toString() ??
                      item['title']?.toString() ??
                      'عملية محفظة',
                  date: DateTime.tryParse(
                        item['createdAtUtc']?.toString() ?? '',
                      ) ??
                      DateTime.now(),
                  amount: (item['amount'] as num?)?.toDouble() ?? 0,
                  isCredit: item['type'] == 0 ||
                      item['type'] == 3 ||
                      item['type'] == 4 ||
                      item['isCredit'] == true,
                  type: (item['type'] as num?)?.toInt() ?? 0,
                ))
            .toList(growable: false)
        : const <WalletTransaction>[];
    return WalletSnapshot(
      balance: (data['balance'] as num?)?.toDouble() ?? 0,
      transactions: transactions,
    );
  }
}
