import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/services/locale_service.dart';
import '../../../../core/services/ride_preferences.dart';
import '../../../../core/services/theme_service.dart';

class SettingsController extends GetxController {
  final selectedLanguage = 'ar'.obs;
  final autoStartTransport = RidePreferences.autoStartTransport.obs;

  @override
  void onInit() {
    super.onInit();
    if (Get.isRegistered<LocaleService>()) {
      selectedLanguage.value =
          Get.find<LocaleService>().locale.value.languageCode;
    }
  }

  Future<void> setAutoStartTransport(bool value) async {
    autoStartTransport.value = value;
    await RidePreferences.setAutoStartTransport(value);
  }

  Future<void> setTheme(ThemeMode mode) async {
    if (Get.isRegistered<ThemeService>()) {
      await Get.find<ThemeService>().setMode(mode);
    } else {
      Get.changeThemeMode(mode);
    }
  }

  Future<void> setPalette(AppPalette palette) async {
    if (Get.isRegistered<ThemeService>()) {
      await Get.find<ThemeService>().setPalette(palette);
    }
  }
}
