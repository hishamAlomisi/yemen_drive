import 'package:get/get.dart';

import '../../../../core/network/api_client.dart';
import '../controllers/login_controller.dart';
import '../providers/login_provider.dart';
import '../repositories/login_repository.dart';

class LoginBinding extends Bindings {
  @override
  void dependencies() {
    final repository = ApiLoginRepository(LoginProvider(Get.find<ApiClient>()));
    Get.lazyPut<LoginRepository>(() => repository);
    Get.lazyPut<LoginController>(
        () => LoginController(Get.find<LoginRepository>()));
  }
}
