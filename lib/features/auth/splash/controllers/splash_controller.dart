import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../../core/services/auth_session_service.dart';
import '../../../../core/services/startup_connection_service.dart';
import '../../../ride/ride_routes.dart';
import '../../routes/auth_routes.dart';

class SplashController extends GetxController {
  SplashController({required this.connection, GetStorage? storage})
      : _storage = storage ?? GetStorage();
  final GetStorage _storage;
  final StartupConnectionService connection;
  bool _continuing = false;

  @override
  void onReady() {
    super.onReady();
    retry();
  }

  Future<void> retry() async {
    if (_continuing) return;
    _continuing = true;
    try {
      final connected = connection.isVerified || await connection.verify();
      if (!connected || isClosed) return;
      _continueAfterSplash();
    } finally {
      _continuing = false;
    }
  }

  void _continueAfterSplash() {
    final hasSeenOnboarding =
        _storage.read<bool>('has_seen_onboarding') ?? false;
    final session = Get.find<AuthSessionService>();
    if (session.hasPendingNotificationOpen) {
      if (session.isAuthenticated.value) {
        session.continueAfterAuthentication(
          fallbackRoute: RideRoutes.homeTransport,
        );
      } else {
        Get.offAllNamed<void>(AuthRoutes.signIn);
      }
      return;
    }
    Get.offAllNamed<void>(
      hasSeenOnboarding ? RideRoutes.homeTransport : AuthRoutes.onboardingOne,
    );
  }
}
