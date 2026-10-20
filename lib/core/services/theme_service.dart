import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';

class ThemeService extends GetxService {
  ThemeService({GetStorage? storage}) : _storage = storage ?? GetStorage();

  static const String _key = 'theme_mode';
  static const String _paletteKey = 'app_palette';
  final GetStorage _storage;
  // The application must start in the light theme unless the passenger has
  // explicitly selected another mode and it was saved on this device.
  final Rx<ThemeMode> mode = ThemeMode.light.obs;
  final Rx<AppPalette> palette = AppPalette.olive.obs;

  Future<ThemeService> init() async {
    final saved = _storage.read<String>(_key);
    mode.value = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };
    // Apply the new visual identity once, then respect subsequent choices.
    if (_storage.read<int>('passenger_design_version') != 2) {
      if (_storage.read<String>(_paletteKey) == null) {
        await _storage.write(_paletteKey, 'olive');
      }
      await _storage.write('passenger_design_version', 2);
    }
    palette.value = switch (_storage.read<String>(_paletteKey)) {
      'lime' => AppPalette.lime,
      'olive' => AppPalette.olive,
      'yemenDrive' => AppPalette.yemenDrive,
      'blueGold' => AppPalette.blueGold,
      'midnightBurgundy' => AppPalette.midnightBurgundy,
      'modern' => AppPalette.modern,
      _ => AppPalette.olive,
    };
    AppColors.setPalette(palette.value);
    return this;
  }

  Future<void> setMode(ThemeMode value) async {
    mode.value = value;
    await _storage.write(_key, value.name);
    Get.changeThemeMode(value);
  }

  Future<void> toggle() =>
      setMode(Get.isDarkMode ? ThemeMode.light : ThemeMode.dark);

  Future<void> setPalette(AppPalette value) async {
    palette.value = value;
    AppColors.setPalette(value);
    await _storage.write(_paletteKey, value.name);
  }
}
