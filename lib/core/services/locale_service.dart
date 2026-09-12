import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
class LocaleService extends GetxService {
  static const String _key = 'locale';
  final GetStorage _storage = GetStorage();
  final Rx<Locale> locale = const Locale('ar', 'SA').obs;

  Future<LocaleService> init() async {
    final saved = _storage.read<String>(_key);
    locale.value = (saved == 'en_US'
        ? const Locale('en', 'US')
        : const Locale('ar', 'SA'));
    return this;
  }

  Future<void> setLocale(Locale value) async {
    locale.value = value;
    await _storage.write(_key, '${value.languageCode}_${value.countryCode}');
    await Get.updateLocale(value);
  }
}
