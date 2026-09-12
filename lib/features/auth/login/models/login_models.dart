import '../../models/auth_models.dart';

class LoginRequest {
  const LoginRequest({
    required this.phone,
    required this.password,
    required this.deviceId,
    required this.isTrustedDevice,
  });

  final String phone;
  final String password;
  final String deviceId;
  final bool isTrustedDevice;
}

class DeviceOtpRequest {
  const DeviceOtpRequest({
    required this.phone,
    required this.code,
    required this.challengeId,
    required this.deviceId,
  });

  final String phone;
  final String code;
  final String challengeId;
  final String deviceId;
}

typedef LoginResult = SignInResult;
typedef LoginSession = AuthSession;
