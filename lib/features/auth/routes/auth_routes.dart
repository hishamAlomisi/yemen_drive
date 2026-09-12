import 'package:get/get.dart';

import '../login/bindings/login_binding.dart';
import '../login/views/login_otp_view.dart';
import '../login/views/login_view.dart';
import '../location_permission/bindings/location_permission_binding.dart';
import '../location_permission/views/location_permission_view.dart';
import '../onboarding/views.dart';
import '../onboarding/bindings/onboarding_binding.dart';
import '../password_reset/bindings/password_reset_binding.dart';
import '../password_reset/views.dart';
import '../registration/bindings/registration_binding.dart';
import '../registration/views.dart';
import '../splash/bindings/splash_binding.dart';
import '../splash/views/splash_view.dart';
import '../welcome/views/welcome_view.dart';

abstract final class AuthRoutes {
  static const String splash = '/';
  static const String onboardingOne = '/onboarding/1';
  static const String onboardingTwo = '/onboarding/2';
  static const String onboardingThree = '/onboarding/3';
  static const String enableLocation = '/auth/location';
  static const String welcome = '/auth/welcome';
  static const String signUp = '/auth/sign-up';
  static const String verifySignUpOtp = '/auth/sign-up/verify';
  static const String verifySignUpOtpFilled =
      '/auth/sign-up/verify/preview-filled';
  static const String setPassword = '/auth/sign-up/password';
  static const String completeProfile = '/auth/sign-up/profile';
  static const String signIn = '/auth/sign-in';
  static const String verifyDeviceOtp = '/auth/sign-in/verify-device';
  static const String recoveryIdentity = '/auth/recovery/contact';
  static const String forgotPasswordMethod = '/auth/recovery/method';
  static const String verifyResetOtp = '/auth/recovery/verify';
  static const String verifyResetOtpFilled =
      '/auth/recovery/verify/preview-filled';
  static const String setNewPassword = '/auth/recovery/password';
  static const String postAuthentication = '/home';
}

final List<GetPage<dynamic>> authPages = <GetPage<dynamic>>[
  GetPage<dynamic>(
    name: AuthRoutes.splash,
    page: SplashScreen.new,
    binding: SplashBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.onboardingOne,
    page: OnboardingScreen.new,
    binding: OnboardingBinding(0),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.onboardingTwo,
    page: OnboardingScreen.new,
    binding: OnboardingBinding(1),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.onboardingThree,
    page: OnboardingScreen.new,
    binding: OnboardingBinding(2),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.enableLocation,
    page: LocationPermissionScreen.new,
    binding: LocationPermissionBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.welcome,
    page: WelcomeScreen.new,
  ),
  GetPage<dynamic>(
    name: AuthRoutes.signUp,
    page: SignUpScreen.new,
    binding: RegistrationBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.verifySignUpOtp,
    page: RegistrationOtpView.new,
    binding: RegistrationBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.verifySignUpOtpFilled,
    page: () => const RegistrationOtpView(initialCode: '25'),
    binding: RegistrationBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.setPassword,
    page: PasswordSetupScreen.new,
    binding: RegistrationBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.completeProfile,
    page: CompleteProfileScreen.new,
    binding: RegistrationBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.signIn,
    page: LoginView.new,
    binding: LoginBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.verifyDeviceOtp,
    page: LoginOtpView.new,
    binding: LoginBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.recoveryIdentity,
    page: RecoveryIdentityScreen.new,
    binding: PasswordResetBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.forgotPasswordMethod,
    page: ForgotPasswordMethodScreen.new,
    binding: PasswordResetBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.verifyResetOtp,
    page: PasswordResetOtpView.new,
    binding: PasswordResetBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.verifyResetOtpFilled,
    page: () => const PasswordResetOtpView(initialCode: '25'),
    binding: PasswordResetBinding(),
  ),
  GetPage<dynamic>(
    name: AuthRoutes.setNewPassword,
    page: NewPasswordScreen.new,
    binding: PasswordResetBinding(),
  ),
];
