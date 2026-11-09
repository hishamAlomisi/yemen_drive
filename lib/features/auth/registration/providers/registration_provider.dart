import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/services/otp_sms_service.dart';
import '../../../../core/services/push_notifications_service.dart';
import '../models/registration_models.dart';

class RegistrationProvider {
  const RegistrationProvider(this._client, {OtpPushDataSupplier? otpPushData})
      : _otpPushData = otpPushData ?? requestOtpPushData;

  final ApiClient _client;
  final OtpPushDataSupplier _otpPushData;

  Future<Response<Object?>> requestOtp(SignUpDraft draft) async =>
      _client.dio.post<Object?>(
        '${ApiEndpoints.signUp}/request-otp',
        data: <String, Object?>{
          ...draft.toJson(),
          ...await OtpSmsService.prepareRequest(pushFields: _otpPushData),
        },
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
    required String deviceId,
  }) =>
      _client.dio.post<Object?>(
        ApiEndpoints.signUp,
        data: <String, Object?>{
          'phoneNumber': signUp.phone,
          'displayName': profile.fullName,
          'role': 'Customer',
          'password': password,
          'verificationToken': verificationToken,
          'deviceId': deviceId,
          'gender': profile.gender,
          'street': profile.street,
          'city': profile.city,
          'district': profile.district,
        },
      );
}
