import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import 'app/app.dart';
import 'core/config/app_environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  AppEnvironment.configure(
    flavor: const String.fromEnvironment('FLAVOR', defaultValue: 'dev'),
    baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      // Android emulator reaches the local ASP.NET profile through 10.0.2.2.
      // Override with --dart-define=API_BASE_URL=... for a device or server.
      // Android emulator maps the host machine to 10.0.2.2. Keep this as the
      // development default; physical devices should override it with the
      // host LAN address using --dart-define=API_BASE_URL=...
      defaultValue: 'http://10.0.2.2:5080/api',
    ),
    useDemoData: const bool.fromEnvironment(
      'USE_DEMO_DATA',
      defaultValue: false,
    ),
    googleMapsApiKey: const String.fromEnvironment(
      'GOOGLE_MAPS_API_KEY',
    ),
    googleRoutesApiKey: const String.fromEnvironment(
      'GOOGLE_ROUTES_API_KEY',
    ),
    googleGeocodingApiKey: const String.fromEnvironment(
      'GOOGLE_GEOCODING_API_KEY',
    ),
    googlePlacesApiKey: const String.fromEnvironment(
      'GOOGLE_PLACES_API_KEY',
    ),
    androidPackageName: const String.fromEnvironment(
      'ANDROID_PACKAGE_NAME',
      defaultValue: '',
    ),
    androidCertSha1: const String.fromEnvironment(
      'ANDROID_CERT_SHA1',
      defaultValue: '',
    ),
    signalRHubUrl: const String.fromEnvironment('SIGNALR_HUB_URL'),
  );
  runApp(const EasyRideApp());
}
