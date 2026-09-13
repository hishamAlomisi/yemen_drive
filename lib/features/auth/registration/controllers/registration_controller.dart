import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_session_service.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../models/auth_models.dart';
import '../../routes/auth_routes.dart';
import '../models/registration_models.dart';
import '../repositories/registration_repository.dart';

class RegistrationController extends GetxController {
  RegistrationController(this._repository);

  final RegistrationRepository _repository;
  final signUpFormKey = GlobalKey<FormState>();
  final passwordFormKey = GlobalKey<FormState>();
  final profileFormKey = GlobalKey<FormState>();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final profileNameController = TextEditingController();
  final streetController = TextEditingController();
  final isLoading = false.obs;
  final termsAccepted = false.obs;
  final obscurePassword = true.obs;
  final obscureConfirmation = true.obs;
  final selectedGender = ''.obs;
  final selectedCity = ''.obs;
  final selectedDistrict = ''.obs;
  final country = PhoneCountry.yemen.obs;
  final cities = const <String>['صنعاء', 'ذمار', 'عدن', 'تعز', 'الحديدة'];
  final districts = const <String>[
    'وسط المدينة',
    'الشمال',
    'الشرق',
    'الغرب',
    'الجنوب'
  ];

  String? _verificationToken;
  String? _challengeId;
  String _password = '';

  void toggleTerms(bool? value) => termsAccepted.value = value ?? false;
  void selectCountry(PhoneCountry value) => country.value = value;
  void selectGender(String? value) => selectedGender.value = value ?? '';
  void selectCity(String? value) => selectedCity.value = value ?? '';
  void selectDistrict(String? value) => selectedDistrict.value = value ?? '';

  Future<void> submit() async {
    if (!(signUpFormKey.currentState?.validate() ?? false)) return;
    if (!termsAccepted.value) {
      Get.snackbar('request_failed'.tr, 'accept_terms'.tr);
      return;
    }
    await _run(() async {
      _challengeId = await _repository.requestOtp(_draft);
    }, () => Get.toNamed<void>(AuthRoutes.verifySignUpOtp));
  }

  Future<void> verifyOtp(String code) async {
    if (!_validOtp(code)) return;
    await _run(() async {
      _verificationToken = await _repository.verifyOtp(
          phone: _draft.phone, code: code, challengeId: _challengeId);
    }, () => Get.toNamed<void>(AuthRoutes.setPassword));
  }

  Future<void> resendOtp() => _run(
        () async {
          _challengeId = await _repository.requestOtp(_draft);
        },
        () => Get.snackbar('app_name'.tr, 'code_resent'.tr),
      );

  void submitPassword() {
    if (!(passwordFormKey.currentState?.validate() ?? false)) return;
    _password = passwordController.text;
    Get.toNamed<void>(AuthRoutes.completeProfile);
  }

  Future<void> completeProfile() async {
    if (!(profileFormKey.currentState?.validate() ?? false)) return;
    await _run(() async {
      final session = await _repository.complete(
        signUp: _draft,
        profile: ProfileDraft(
          fullName: profileNameController.text.trim(),
          phone: _draft.phone,
          gender: selectedGender.value,
          street: streetController.text.trim(),
          city: selectedCity.value,
          district: selectedDistrict.value,
        ),
        password: _password,
        verificationToken: _verificationToken,
      );
      await Get.find<AuthSessionService>().activate(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        remember: true,
        userId: session.userId,
      );
      await Get.find<SecureStorageService>().trustPhone(_draft.phone);
      Get.find<AuthSessionService>().continueAfterAuthentication();
    });
  }

  SignUpDraft get _draft =>
      SignUpDraft(phone: _normalize(phoneController.text, country.value));

  bool _validOtp(String code) {
    if (code.length == 6) return true;
    Get.snackbar('request_failed'.tr, 'invalid_otp'.tr);
    return false;
  }

  Future<void> _run(Future<void> Function() action,
      [VoidCallback? success]) async {
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      await action();
      success?.call();
    } catch (error) {
      var message = error is FormatException ? error.message : 'try_again'.tr;
      if (error is! FormatException && Get.isRegistered<ApiClient>()) {
        final problem = Get.find<ApiClient>().problemFrom(error);
        message = problem.detail ?? problem.title;
      }
      Get.snackbar('request_failed'.tr, message);
    } finally {
      isLoading.value = false;
    }
  }

  String _normalize(String value, PhoneCountry selectedCountry) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final withoutCountryCode = digits.startsWith(selectedCountry.phoneCode)
        ? digits.substring(selectedCountry.phoneCode.length)
        : digits;
    return withoutCountryCode.startsWith('0')
        ? withoutCountryCode.substring(1)
        : withoutCountryCode;
  }

  @override
  void onClose() {
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    profileNameController.dispose();
    streetController.dispose();
    super.onClose();
  }
}
