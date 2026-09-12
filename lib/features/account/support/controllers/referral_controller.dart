import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../repositories/support_repository.dart';

class ReferralController extends GetxController {
  ReferralController(this._repository);

  final ReferralRepository _repository;
  final TextEditingController codeController = TextEditingController();
  final RxBool isSubmitting = false.obs;

  Future<bool> submit() async {
    if (codeController.text.trim().length < 4) return false;
    isSubmitting.value = true;
    try {
      await _repository.submit(codeController.text.trim());
      return true;
    } finally {
      isSubmitting.value = false;
    }
  }

  @override
  void onClose() {
    codeController.dispose();
    super.onClose();
  }
}
