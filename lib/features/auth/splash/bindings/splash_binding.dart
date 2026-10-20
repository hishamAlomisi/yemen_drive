import 'package:get/get.dart';

import '../../../../core/services/startup_connection_service.dart';
import '../controllers/splash_controller.dart';

class SplashBinding extends Bindings {
  @override
  void dependencies() {
    final connection = Get.isRegistered<StartupConnectionService>()
        ? Get.find<StartupConnectionService>()
        : Get.put(StartupConnectionService(), permanent: true);
    Get.put(SplashController(connection: connection));
  }
}
