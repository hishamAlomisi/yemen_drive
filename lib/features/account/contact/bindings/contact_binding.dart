import 'package:get/get.dart';

import '../controllers/contact_controller.dart';
import '../../../../core/network/api_client.dart';

class ContactBinding extends Bindings {
  @override
  void dependencies() =>
      Get.lazyPut(() => ContactController(Get.find<ApiClient>()));
}
