import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../models/registration_models.dart';

class RegistrationProvider {
  const RegistrationProvider(this._client);

  final ApiClient _client;

  Future<Response<Object?>> requestOtp(SignUpDraft draft) =>
      _client.dio.post<Object?>(
        '${ApiEndpoints.signUp}/request-otp',
        data: draft.toJson(),
      );

  Future<Response<Object?>> verifyOtp({
    required String phone,
    required String code,
    String? challengeId,
  }) =>
      _client.dio.post<Object?>(
        'auth/verify-otp',
        data: <String, Object?>{
          'destination': phone,
          'code': code,
          'purpose': 'signUp',
          'challengeId': challengeId,
        },
      );

  Future<Response<Object?>> complete({
    required SignUpDraft signUp,
    required ProfileDraft profile,
    required String password,
    String? verificationToken,
  }) =>
      _client.dio.post<Object?>(
        ApiEndpoints.signUp,
        data: <String, Object?>{
          'phoneNumber': signUp.phone,
          'displayName': profile.fullName,
          'role': 'Customer',
          'password': password,
          'verificationToken': verificationToken,
          'gender': profile.gender,
          'street': profile.street,
          'city': profile.city,
          'district': profile.district,
        },
      );
}
