import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_session_service.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../models/auth_models.dart';
import '../models/login_models.dart';
import '../repositories/login_repository.dart';

class LoginController extends GetxController {
  LoginController(this._repository);

  final LoginRepository _repository;
  final signInFormKey = GlobalKey<FormState>();
  final signInIdentityController = TextEditingController();
  final signInPasswordController = TextEditingController();
  final isLoading = false.obs;
  final rememberMe = false.obs;
  final obscurePassword = true.obs;
  final signInCountry = PhoneCountry.yemen.obs;

  String _pendingPhone = '';
  String _challengeId = '';

  AuthSessionService get _session => Get.find<AuthSessionService>();
  SecureStorageService get _storage => Get.find<SecureStorageService>();
  String get maskedDevicePhone => _mask(_pendingPhone);

  void toggleRememberMe(bool? value) => rememberMe.value = value ?? false;
  void selectCountry(PhoneCountry value) => signInCountry.value = value;

  Future<void> submit() async {
    if (!(signInFormKey.currentState?.validate() ?? false) || isLoading.value)
      return;
    final phone =
        _normalize(signInIdentityController.text, signInCountry.value);
    await _run(() async {
      final result = await _repository.login(LoginRequest(
        phone: phone.replaceAll('+', ''),
        password: signInPasswordController.text,
        deviceId: _session.deviceId,
        isTrustedDevice: await _storage.isTrustedPhone(phone),
      ));
      if (result.requiresOtp) {
        _pendingPhone = phone.replaceAll('+', '');
        _challengeId = result.challengeId ?? '';
        Get.toNamed<void>('/auth/sign-in/verify-device');
        return;
      }
      await _activate(result.session!, phone);
    });
  }

  Future<void> verifyDeviceOtp(String code) async {
    if (code.length != 6 || isLoading.value) return;
    await _run(() async {
      final session = await _repository.verifyDeviceOtp(DeviceOtpRequest(
        phone: _pendingPhone,
        code: code,
        challengeId: _challengeId,
        deviceId: _session.deviceId,
      ));
      await _activate(session, _pendingPhone);
    });
  }

  Future<void> _activate(AuthSession session, String phone) async {
    await _session.activate(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      remember: rememberMe.value,
      userId: session.userId,
    );
    await _storage.trustPhone(phone);
    _session.continueAfterAuthentication();
  }

  Future<void> _run(Future<void> Function() action) async {
    isLoading.value = true;
    try {
      await action();
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

  String _normalize(String value, PhoneCountry country) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final withoutCountryCode = digits.startsWith(country.phoneCode)
        ? digits.substring(country.phoneCode.length)
        : digits;
    return withoutCountryCode.startsWith('0')
        ? withoutCountryCode.substring(1)
        : withoutCountryCode;
  }

  String _mask(String phone) => phone.length < 5
      ? '•••• ••••'
      : '${phone.substring(0, 4)} •••• ${phone.substring(phone.length - 2)}';

  @override
  void onClose() {
    signInIdentityController.dispose();
    signInPasswordController.dispose();
    super.onClose();
  }
}
