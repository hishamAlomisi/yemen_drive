import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../ride/ride_routes.dart';
import '../../routes/auth_routes.dart';

class SplashController extends GetxController {
  SplashController({GetStorage? storage}) : _storage = storage ?? GetStorage();
  final GetStorage _storage;

  @override
  void onReady() {
    super.onReady();
    _continueAfterSplash();
  }

  Future<void> _continueAfterSplash() async {
    await Future<void>.delayed(const Duration(milliseconds: 1450));
    if (isClosed) return;
    final hasSeenOnboarding =
        _storage.read<bool>('has_seen_onboarding') ?? false;
    Get.offAllNamed<void>(
      hasSeenOnboarding ? RideRoutes.homeTransport : AuthRoutes.onboardingOne,
    );
  }
}
