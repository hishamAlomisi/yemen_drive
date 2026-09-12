import 'package:get_storage/get_storage.dart';

abstract final class RidePreferences {
  static const autoStartTransportKey = 'auto_start_transport';
  static final GetStorage _storage = GetStorage();

  static bool get autoStartTransport =>
      _storage.read<bool>(autoStartTransportKey) ?? true;

  static Future<void> setAutoStartTransport(bool value) =>
      _storage.write(autoStartTransportKey, value);
}
