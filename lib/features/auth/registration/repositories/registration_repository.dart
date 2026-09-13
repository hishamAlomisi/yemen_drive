import '../../models/auth_models.dart';
import '../models/registration_models.dart';
import '../providers/registration_provider.dart';

abstract interface class RegistrationRepository {
  Future<String?> requestOtp(SignUpDraft draft);
  Future<String?> verifyOtp(
      {required String phone, required String code, String? challengeId});
  Future<AuthSession> complete({
    required SignUpDraft signUp,
    required ProfileDraft profile,
    required String password,
    String? verificationToken,
  });
}

class ApiRegistrationRepository implements RegistrationRepository {
  const ApiRegistrationRepository(this._provider);

  final RegistrationProvider _provider;

  @override
  Future<String?> requestOtp(SignUpDraft draft) async {
    final data = (await _provider.requestOtp(draft)).data;
    return _payload(data)['challengeId']?.toString();
  }

  @override
  Future<String?> verifyOtp(
      {required String phone,
      required String code,
      String? challengeId}) async {
    final payload = _payload((await _provider.verifyOtp(
            phone: phone, code: code, challengeId: challengeId))
        .data);
    return payload['verificationToken']?.toString() ??
        payload['token']?.toString();
  }

  @override
  Future<AuthSession> complete({
    required SignUpDraft signUp,
    required ProfileDraft profile,
    required String password,
    String? verificationToken,
  }) async {
    final payload = _payload((await _provider.complete(
      signUp: signUp,
      profile: profile,
      password: password,
      verificationToken: verificationToken,
    ))
        .data);
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
    if (map['success'] == false) {
      final message = map['message']?.toString().trim();
      throw FormatException(
        message == null || message.isEmpty
            ? 'تعذر إنشاء الحساب. حاول مرة أخرى.'
            : message,
      );
    }
    final nested = map['data'];
    return nested is Map ? Map<String, Object?>.from(nested) : map;
  }
}
