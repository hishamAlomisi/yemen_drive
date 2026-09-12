import 'package:get/get.dart';

import '../../../../core/network/api_client.dart';
import '../controllers/password_reset_controller.dart';
import '../providers/password_reset_provider.dart';
import '../repositories/password_reset_repository.dart';

class PasswordResetBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<PasswordResetRepository>()) {
      final repository = ApiPasswordResetRepository(
          PasswordResetProvider(Get.find<ApiClient>()));
      Get.put<PasswordResetRepository>(repository);
    }
    if (!Get.isRegistered<PasswordResetController>()) {
      Get.put(PasswordResetController(Get.find<PasswordResetRepository>()));
    }
  }
}
