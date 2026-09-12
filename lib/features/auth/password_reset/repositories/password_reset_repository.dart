import '../models/password_reset_models.dart';
import '../providers/password_reset_provider.dart';

abstract interface class PasswordResetRepository {
  Future<void> request(
      {required String identity, required RecoveryChannel channel});
  Future<String?> verify({required String identity, required String code});
  Future<void> reset(
      {required String identity,
      required String password,
      String? verificationToken});
}

class ApiPasswordResetRepository implements PasswordResetRepository {
  const ApiPasswordResetRepository(this._provider);
  final PasswordResetProvider _provider;

  @override
  Future<void> request(
          {required String identity, required RecoveryChannel channel}) async =>
      _provider.request(identity: identity, channel: channel);

  @override
  Future<String?> verify(
      {required String identity, required String code}) async {
    final data = (await _provider.verify(identity: identity, code: code)).data;
    if (data is! Map) return null;
    final map = Map<String, Object?>.from(data);
    final raw = map['data'] is Map
        ? Map<String, Object?>.from(map['data']! as Map)
        : map;
    return raw['verificationToken']?.toString() ?? raw['token']?.toString();
  }

  @override
  Future<void> reset(
          {required String identity,
          required String password,
          String? verificationToken}) async =>
      _provider.reset(
          identity: identity,
          password: password,
          verificationToken: verificationToken);
}
