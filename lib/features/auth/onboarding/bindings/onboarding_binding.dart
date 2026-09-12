import 'package:get/get.dart';

import '../controllers/onboarding_controller.dart';

class OnboardingBinding extends Bindings {
  OnboardingBinding(this.initialPage);
  final int initialPage;

  @override
  void dependencies() {
    Get.lazyPut<OnboardingController>(
      () => OnboardingController(initialPage: initialPage),
      fenix: true,
    );
  }
}
