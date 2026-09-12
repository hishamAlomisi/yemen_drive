import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';

class ThemeService extends GetxService {
  static const String _key = 'theme_mode';
  static const String _paletteKey = 'app_palette';
  final GetStorage _storage = GetStorage();
  final Rx<ThemeMode> mode = ThemeMode.system.obs;
  final Rx<AppPalette> palette = AppPalette.blueGold.obs;

  Future<ThemeService> init() async {
    final saved = _storage.read<String>(_key);
    mode.value = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    palette.value = switch (_storage.read<String>(_paletteKey)) {
      'yemenDrive' => AppPalette.yemenDrive,
      'blueGold' => AppPalette.blueGold,
      'midnightBurgundy' => AppPalette.midnightBurgundy,
      _ => AppPalette.blueGold,
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
