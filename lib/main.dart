import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'app/app.dart';
import 'core/config/app_environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await Firebase.initializeApp();
  }
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
        // MEmu's virtual GPU crashes inside the latest vector renderer
        // (eglChooseConfig) while opening route/service screens. The legacy
        // renderer is stable on the emulator and remains fully compatible
        // with the Maps SDK on physical devices.
        await maps.initializeWithRenderer(AndroidMapRenderer.legacy);
        await maps.warmup();
      } catch (_) {
        // The Maps SDK selects its compatible renderer when a device cannot
        // provide the latest one. Map creation remains available.
      }
    }
  }
  AppEnvironment.configure(
    baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://192.168.89.72:5080/api',
    ),
    signalRHubUrl: const String.fromEnvironment('SIGNALR_HUB_URL'),
  );
  runApp(const EasyRideApp());
}
