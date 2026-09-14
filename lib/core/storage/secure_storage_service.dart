import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

class SecureStorageService extends GetxService {
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _rememberMeKey = 'remember_me';
  static const String _deviceIdKey = 'device_id';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<String?> get accessToken => _readSafely(_accessTokenKey);
  Future<String?> get refreshToken => _readSafely(_refreshTokenKey);
  Future<bool> get rememberMe async =>
      await _readSafely(_rememberMeKey) == 'true';
  Future<String?> get deviceId => _readSafely(_deviceIdKey);

  Future<String?> _readSafely(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object {
      // A restored emulator backup or a re-signed debug build can leave
      // Android Keystore entries that no longer decrypt. They are unusable
      // credentials, so discard them and let the user sign in again.
      try {
        await _storage.deleteAll();
      } on Object {
        // The next startup will retry cleanup; never crash while reading auth.
      }
      return null;
    }
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) =>
      Future.wait<void>(<Future<void>>[
        _storage.write(key: _accessTokenKey, value: accessToken),
        _storage.write(key: _refreshTokenKey, value: refreshToken),
      ]);

  Future<void> setRememberMe(bool value) =>
      _storage.write(key: _rememberMeKey, value: value.toString());

  Future<void> saveDeviceId(String value) =>
      _storage.write(key: _deviceIdKey, value: value);

  Future<bool> isTrustedPhone(String phone) async =>
      await _storage.read(key: 'trusted_device_$phone') == 'true';

  Future<void> trustPhone(String phone) =>
      _storage.write(key: 'trusted_device_$phone', value: 'true');

  Future<void> clear() => Future.wait<void>(<Future<void>>[
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
        _storage.delete(key: _rememberMeKey),
      ]);

  static Future<void> write({
    required String key,
    required String value,
  }) =>
      Future.wait<void>(<Future<void>>[
        _storage.write(key: key, value: value),
      ]);
  static Future<void> delete({required String key}) =>
      _storage.delete(key: key);

  static Future<String> read({required String key}) async {
    final result = await _storage.read(key: key);
    if (result != null) {
      return result;
    }
    return "";
  }
}
