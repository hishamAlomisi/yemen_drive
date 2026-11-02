import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';

abstract interface class WalletTransferRepository {
  Future<Map<String, dynamic>> request(
    String operation,
    Map<String, Object?> data,
  );
  Future<List<Map<String, dynamic>>> history();
}

class ApiWalletTransferRepository implements WalletTransferRepository {
  ApiWalletTransferRepository(this.api);
  final ApiClient api;
  Future<Object?> _call(String operation, Map<String, Object?> data) async {
    final result = await api.execute<Object?>(
      model: 'WalletTransferModel',
      operation: operation,
      data: data,
    );
    if (result is ApiSuccess) return result.data;
    if (result is ApiFailure) {
      throw Exception(result.problem.detail ?? result.problem.title);
    }
    throw Exception('تعذر الاتصال. أعد المحاولة بنفس التحويل.');
  }

  @override
  Future<Map<String, dynamic>> request(
    String operation,
    Map<String, Object?> data,
  ) async =>
      Map<String, dynamic>.from(
          await _call(operation, data) as Map<Object?, Object?>);
  @override
  Future<List<Map<String, dynamic>>> history() async =>
      (await _call('list', {}) as List<Object?>)
          .whereType<Map<Object?, Object?>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
}
