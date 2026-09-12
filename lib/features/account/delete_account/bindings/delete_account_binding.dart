import 'package:get/get.dart';
import '../../../../core/network/api_client.dart';

import '../controllers/delete_account_controller.dart';
import '../repositories/delete_account_repository.dart';

class DeleteAccountBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<DeleteAccountRepository>()) {
      Get.lazyPut<DeleteAccountRepository>(
          () => ApiDeleteAccountRepository(Get.find<ApiClient>()),
          fenix: true);
    }
    Get.lazyPut(
      () => DeleteAccountController(Get.find<DeleteAccountRepository>()),
    );
  }
}
