import 'package:get/get.dart';

import '../../core/config/app_environment.dart';
import '../../core/network/api_client.dart';
import '../../core/services/auth_session_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/locale_service.dart';
import '../../core/services/theme_service.dart';
import '../../core/storage/secure_storage_service.dart';

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

    await AppEnvironment.loadPaymentMethods(Get.find<ApiClient>());
  }
}
