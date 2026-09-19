import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'app/app.dart';
import 'core/config/app_environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  // Request Google's current renderer before any map is created. Besides its
  // better rendering path on real devices, this avoids MEmu falling back to
  // the older renderer when its installed Play Services supports the latest
  // renderer. Falling back is safe on devices where it is unavailable.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final maps = GoogleMapsFlutterPlatform.instance;
    if (maps is GoogleMapsFlutterAndroid) {
      try {
        // Hybrid composition is more tolerant of MEmu's virtual display than
        // the default texture layer. Physical devices may still use it safely.
        maps.useAndroidViewSurface = true;
        await maps.initializeWithRenderer(AndroidMapRenderer.latest);
        await maps.warmup();
      } catch (_) {
        // The Maps SDK selects its compatible renderer when a device cannot
        // provide the latest one. Map creation remains available.
      }
    }
  }
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
    signalRHubUrl: const String.fromEnvironment('SIGNALR_HUB_URL'),
  );
  runApp(const EasyRideApp());
}
