import '../../../../core/network/api_client.dart';

abstract interface class DeleteAccountRepository {
  Future<void> delete();
}

class ApiDeleteAccountRepository implements DeleteAccountRepository {
  const ApiDeleteAccountRepository(this._client);
  final ApiClient _client;
  @override
  Future<void> delete() async {
    final result = await _client.execute<Object?>(
        model: 'UserModel', operation: 'delete', data: const {});
    if (result.runtimeType.toString().contains('Failure'))
      throw Exception('تعذر حذف الحساب');
  }
}
