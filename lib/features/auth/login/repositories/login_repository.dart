import '../../models/auth_models.dart';
import '../models/login_models.dart';
import '../providers/login_provider.dart';

abstract interface class LoginRepository {
  Future<LoginResult> login(LoginRequest request);
  Future<LoginSession> verifyDeviceOtp(DeviceOtpRequest request);
}

class ApiLoginRepository implements LoginRepository {
  const ApiLoginRepository(this._provider);

  final LoginProvider _provider;

  @override
  Future<LoginResult> login(LoginRequest request) async {
    final payload = _payload((await _provider.login(request)).data);
    if (payload['requiresOtp'] == true) {
      return SignInResult.requiresOtp(payload['challengeId']?.toString() ?? '');
    }
    return SignInResult.authenticated(_session(payload));
  }

  @override
  Future<LoginSession> verifyDeviceOtp(DeviceOtpRequest request) async {
    final payload = _payload((await _provider.verifyDeviceOtp(request)).data);
    return _session(payload);
  }

  AuthSession _session(Map<String, Object?> payload) {
    final access = payload['accessToken']?.toString();
    if (access == null || access.isEmpty) {
      throw const FormatException('Authentication response has no tokens.');
    }
    return AuthSession(
      accessToken: access,
      refreshToken: payload['refreshToken']?.toString() ?? '',
      userId: _userId(payload),
    );
  }

  int? _userId(Map<String, Object?> payload) {
    final user = payload['user'];
    if (user is Map) return int.tryParse('${user['id']}');
    return int.tryParse('${payload['userId']}');
  }

  Map<String, Object?> _payload(Object? data) {
    if (data is! Map) return <String, Object?>{};
    final map = Map<String, Object?>.from(data);
    final nested = map['data'];
    return nested is Map ? Map<String, Object?>.from(nested) : map;
  }
}
