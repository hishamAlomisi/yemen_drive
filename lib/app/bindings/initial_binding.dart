import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/config/app_environment.dart';
import '../../core/network/api_client.dart';
import '../../core/services/auth_session_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/locale_service.dart';
import '../../core/services/theme_service.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../features/account/models/account_models.dart';

class InitialBinding extends Bindings {
  @override
  Future<void> dependencies() async {
    if (!Get.isRegistered<SecureStorageService>()) {
      Get.put<SecureStorageService>(SecureStorageService(), permanent: true);
    }
    if (!Get.isRegistered<ThemeService>()) {
      await Get.putAsync<ThemeService>(
        () => ThemeService().init(),
        permanent: true,
      );
    }
    if (!Get.isRegistered<LocaleService>()) {
      await Get.putAsync<LocaleService>(
        () => LocaleService().init(),
        permanent: true,
      );
    }
    if (!Get.isRegistered<ConnectivityService>()) {
      await Get.putAsync<ConnectivityService>(
        () => ConnectivityService().init(),
        permanent: true,
      );
    }
    if (!Get.isRegistered<ApiClient>()) {
      await Get.putAsync<ApiClient>(
        () => ApiClient(Get.find<SecureStorageService>()).init(),
        permanent: true,
      );
    }
    if (!Get.isRegistered<AuthSessionService>()) {
      await Get.putAsync<AuthSessionService>(
        () => AuthSessionService(
          Get.find<SecureStorageService>(),
          Get.find<ApiClient>(),
        ).init(),
        permanent: true,
      );
    }

    AppEnvironment.paymentMethods = <PaymentMethodItem>[
      PaymentMethodItem(
        id: 'visa',
        label: 'بطاقة Visa',
        subtitle: 'تنتهي بالرقم 4821',
        icon: Icons.credit_card_rounded,
      ),
      PaymentMethodItem(
        id: 'jaib',
        label: 'محفظة جيب',
        subtitle: 'دفع سريع وآمن',
        icon: Icons.phone_iphone_rounded,
      ),
      PaymentMethodItem(
        id: 'jwali',
        label: 'محفظة جوالي',
        subtitle: 'دفع سريع وآمن',
        icon: Icons.phone_iphone_rounded,
      ),
      PaymentMethodItem(
        id: 'oneCash',
        label: 'محفظة ون كاش',
        subtitle: 'دفع سريع وآمن',
        icon: Icons.phone_iphone_rounded,
      ),
      PaymentMethodItem(
        id: 'apple_pay',
        label: 'Apple Pay',
        subtitle: 'دفع سريع وآمن',
        icon: Icons.phone_iphone_rounded,
      ),
      PaymentMethodItem(
        id: 'bank',
        label: 'حساب بنكي',
        subtitle: 'إضافة بيانات حساب جديد',
        icon: Icons.account_balance_rounded,
      ),
    ];
  }
}
