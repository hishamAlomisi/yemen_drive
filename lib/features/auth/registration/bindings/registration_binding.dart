import 'package:get/get.dart';

import '../../../../core/network/api_client.dart';
import '../controllers/registration_controller.dart';
import '../providers/registration_provider.dart';
import '../repositories/registration_repository.dart';

class RegistrationBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<RegistrationRepository>()) {
      final repository = ApiRegistrationRepository(
          RegistrationProvider(Get.find<ApiClient>()));
      Get.put<RegistrationRepository>(repository);
    }
    if (!Get.isRegistered<RegistrationController>()) {
      Get.put(RegistrationController(Get.find<RegistrationRepository>()));
    }
  }
}
