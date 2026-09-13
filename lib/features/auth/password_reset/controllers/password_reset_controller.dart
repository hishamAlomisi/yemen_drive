import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/network/api_client.dart';
import '../../models/auth_models.dart';
import '../../routes/auth_routes.dart';
import '../models/password_reset_models.dart';
import '../repositories/password_reset_repository.dart';

class PasswordResetController extends GetxController {
  PasswordResetController(this._repository);
  final PasswordResetRepository _repository;
  final recoveryFormKey = GlobalKey<FormState>();
  final passwordFormKey = GlobalKey<FormState>();
  final identityController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final isLoading = false.obs;
  final obscurePassword = true.obs;
  final obscureConfirmation = true.obs;
  final country = PhoneCountry.yemen.obs;
  final channel = RecoveryChannel.sms.obs;
  String? _verificationToken;

  String get maskedIdentity => _mask(_identity);
  void selectCountry(PhoneCountry value) => country.value = value;
  void selectChannel(RecoveryChannel value) => channel.value = value;

  Future<void> submitIdentity() async {
    if (!(recoveryFormKey.currentState?.validate() ?? false)) return;
    await sendCode();
  }

  Future<void> sendCode() => _run(
        () => _repository.request(identity: _identity, channel: channel.value),
        () => Get.toNamed<void>(AuthRoutes.verifyResetOtp),
      );

  Future<void> resendCode() => _run(
        () => _repository.request(identity: _identity, channel: channel.value),
        () => Get.snackbar('app_name'.tr, 'code_resent'.tr),
      );

  Future<void> verifyCode(String code) async {
    if (code.length != 6) {
      Get.snackbar('request_failed'.tr, 'invalid_otp'.tr);
      return;
    }
    await _run(() async {
      _verificationToken =
          await _repository.verify(identity: _identity, code: code);
    }, () => Get.toNamed<void>(AuthRoutes.setNewPassword));
  }

  Future<void> submitNewPassword() async {
    if (!(passwordFormKey.currentState?.validate() ?? false)) return;
    await _run(
      () => _repository.reset(
          identity: _identity,
          password: newPasswordController.text,
          verificationToken: _verificationToken),
      () {
        Get.snackbar('app_name'.tr, 'password_updated'.tr);
        Get.offAllNamed<void>(AuthRoutes.signIn);
      },
    );
  }

  String get _identity => _normalize(identityController.text, country.value);

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

  String _mask(String value) => value.length < 5
      ? '•••• ••••'
      : '${value.substring(0, 4)} •••• ${value.substring(value.length - 2)}';

  @override
  void onClose() {
    identityController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}
