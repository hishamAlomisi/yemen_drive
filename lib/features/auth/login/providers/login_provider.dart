import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/services/otp_sms_service.dart';
import '../../../../core/services/push_notifications_service.dart';
import '../models/login_models.dart';

class LoginProvider {
  const LoginProvider(this._client, {OtpPushDataSupplier? otpPushData})
      : _otpPushData = otpPushData ?? requestOtpPushData;

  final ApiClient _client;
  final OtpPushDataSupplier _otpPushData;

  Future<Response<Object?>> login(LoginRequest request) async {
    final otpFields = await OtpSmsService.prepareRequest(
      pushFields: _otpPushData,
      allowPushFailure: true,
    );
    return _client.dio.post<Object?>(
      ApiEndpoints.signIn,
      data: <String, Object?>{
        ...otpFields,
        'phoneNumber': request.phone,
        'password': request.password,
        'deviceId': request.deviceId,
        'trustedDeviceToken': request.trustedDeviceToken,
        'clientType': 'customer',
      },
    );
  }

  Future<Response<Object?>> verifyDeviceOtp(DeviceOtpRequest request) =>
      _client.dio.post<Object?>(
        'auth/sign-in/verify-device',
        data: <String, Object?>{
          'phoneNumber': request.phone,
          'code': request.code,
          'challengeId': request.challengeId,
          'deviceId': request.deviceId,
          'clientType': 'customer',
        },
      );
}
