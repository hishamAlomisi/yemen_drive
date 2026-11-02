import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';

abstract interface class ComplaintRepository {
  Future<void> submit({required String category, required String message});
}

abstract interface class ReferralRepository {
  Future<void> submit(String code);
}

class ApiComplaintRepository implements ComplaintRepository {
  const ApiComplaintRepository(this._client);
  final ApiClient _client;
  @override
  Future<void> submit(
      {required String category, required String message}) async {
    final result = await _client.execute<Object?>(
        model: 'SupportTicketModel',
        operation: 'add',
        data: {'category': category, 'message': message});
    if (result is ApiFailure) throw FormatException(result.problem.detail ?? result.problem.title);
  }
}

class ApiReferralRepository implements ReferralRepository {
  const ApiReferralRepository(this._client);
  final ApiClient _client;
  @override
  Future<void> submit(String code) async {
    final result = await _client.execute<Object?>(
        model: 'ReferralModel', operation: 'add', data: {'code': code});
    if (result is ApiFailure) throw FormatException(result.problem.detail ?? result.problem.title);
  }
}
