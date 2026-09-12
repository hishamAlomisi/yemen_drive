import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';

class ChangePasswordController extends GetxController {
  ChangePasswordController(this._client);
  final ApiClient _client;
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final isSubmitting = false.obs;
  final hideCurrentPassword = true.obs;
  final hideNewPassword = true.obs;
  final hideConfirmPassword = true.obs;

  bool get validPassword {
    final next = newPasswordController.text;
    return currentPasswordController.text.isNotEmpty &&
        next.length >= 8 &&
        next == confirmPasswordController.text;
  }

  Future<bool> savePassword() async {
    if (!validPassword) return false;
    isSubmitting.value = true;
    try {
      final result = await _client.dio
          .post<Object?>('auth/password/change', data: <String, Object?>{
        'currentPassword': currentPasswordController.text,
        'newPassword': newPasswordController.text,
      });
      final body = result.data;
      if (body is Map && body['success'] == true) return true;
      final problem = body is Map
          ? ApiProblemDetails.fromJson(Map<String, Object?>.from(body))
          : null;
      Get.snackbar(
          'تعذر التحديث', problem?.detail ?? 'تعذر تغيير كلمة المرور.');
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  @override
  void onClose() {
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.onClose();
  }
}
