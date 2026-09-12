import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/services/locale_service.dart';

class LanguageController extends GetxController {
  final selectedLanguage = 'ar'.obs;

  @override
  void onInit() {
    super.onInit();
    if (Get.isRegistered<LocaleService>()) {
      selectedLanguage.value =
          Get.find<LocaleService>().locale.value.languageCode;
    }
  }

  Future<void> changeLanguage(String code) async {
    selectedLanguage.value = code;
    if (Get.isRegistered<LocaleService>()) {
      await Get.find<LocaleService>().setLocale(
        code == 'ar' ? const Locale('ar', 'SA') : const Locale('en', 'US'),
      );
    }
  }
}
