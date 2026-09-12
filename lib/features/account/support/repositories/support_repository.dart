import '../../../../core/network/api_client.dart';

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
    await _client.execute<Object?>(
        model: 'SupportTicketModel',
        operation: 'add',
        data: {'category': category, 'message': message});
  }
}

class ApiReferralRepository implements ReferralRepository {
  const ApiReferralRepository(this._client);
  final ApiClient _client;
  @override
  Future<void> submit(String code) async {
    await _client.execute<Object?>(
        model: 'ReferralModel', operation: 'add', data: {'code': code});
  }
}
