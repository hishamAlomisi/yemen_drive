import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../models/login_models.dart';

class LoginProvider {
  const LoginProvider(this._client);

  final ApiClient _client;

  Future<Response<Object?>> login(LoginRequest request) =>
      _client.dio.post<Object?>(
        ApiEndpoints.signIn,
        data: <String, Object?>{
          'phoneNumber': request.phone,
          'password': request.password,
          'deviceId': request.deviceId,
          'isTrustedDevice': request.isTrustedDevice,
        },
      );

  Future<Response<Object?>> verifyDeviceOtp(DeviceOtpRequest request) =>
      _client.dio.post<Object?>(
        'auth/sign-in/verify-device',
        data: <String, Object?>{
          'phoneNumber': request.phone,
          'code': request.code,
          'challengeId': request.challengeId,
          'deviceId': request.deviceId,
        },
      );
}
