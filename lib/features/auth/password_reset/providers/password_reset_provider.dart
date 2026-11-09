import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/services/otp_sms_service.dart';
import '../../../../core/services/push_notifications_service.dart';
import '../models/password_reset_models.dart';

class PasswordResetProvider {
  const PasswordResetProvider(this._client, {OtpPushDataSupplier? otpPushData})
      : _otpPushData = otpPushData ?? requestOtpPushData;
  final ApiClient _client;
  final OtpPushDataSupplier _otpPushData;

  Future<Response<Object?>> request({
    required String identity,
    required RecoveryChannel channel,
  }) async =>
      _client.dio.post<Object?>(
        'auth/password/request-reset',
        data: <String, Object?>{
          ...await OtpSmsService.prepareRequest(pushFields: _otpPushData),
          'identity': identity,
          'channel': channel.name,
        },
      );

  Future<Response<Object?>> verify({
    required String identity,
    required String code,
  }) =>
      _client.dio.post<Object?>(
        'auth/verify-otp',
        data: <String, Object?>{
          'destination': identity,
          'code': code,
          'purpose': 'passwordReset',
        },
      );

  Future<Response<Object?>> reset({
    required String identity,
    required String password,
    String? verificationToken,
  }) =>
      _client.dio.post<Object?>(
        'auth/password/reset',
        data: <String, Object?>{
          'identity': identity,
          'newPassword': password,
          'verificationToken': verificationToken,
        },
      );
}
