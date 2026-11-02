import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';

abstract interface class DeleteAccountRepository {
  Future<void> delete();
}

class ApiDeleteAccountRepository implements DeleteAccountRepository {
  const ApiDeleteAccountRepository(this._client);
  final ApiClient _client;
  @override
  Future<void> delete() async {
    final result = await _client.execute<Object?>(
        model: 'AccountDeletionModel', operation: 'add', data: const {'reason': 'أطلب حذف حسابي بعد مراجعة أموالي والتزاماتي، وأفهم حفظ السجلات المالية وفق السياسة المعتمدة.'});
    if (result is ApiFailure) throw FormatException(result.problem.detail ?? result.problem.title);
  }
}
