import 'package:get/get.dart';
import '../../bindings/account_binding.dart';
import '../../../../core/network/api_client.dart';
import '../repositories/profile_repository.dart';
import '../controllers/profile_controller.dart';

class ProfileBinding extends Bindings {
  @override
  void dependencies() {
    AccountBinding().dependencies();
    Get.lazyPut<ProfileRepository>(
        () => ApiProfileRepository(Get.find<ApiClient>()));
    Get.lazyPut<ProfileController>(
        () => ProfileController(Get.find<ProfileRepository>()));
  }
}
