import 'package:get/get.dart';

import '../controllers/change_password_controller.dart';
import '../../../../core/network/api_client.dart';

class ChangePasswordBinding extends Bindings {
  @override
  void dependencies() =>
      Get.lazyPut(() => ChangePasswordController(Get.find<ApiClient>()));
}
