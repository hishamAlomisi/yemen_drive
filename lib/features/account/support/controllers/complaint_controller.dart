import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../repositories/support_repository.dart';

class ComplaintController extends GetxController {
  ComplaintController(this._repository);

  final ComplaintRepository _repository;
  final TextEditingController messageController = TextEditingController();
  final RxString category = 'السائق'.obs;
  final RxBool isSubmitting = false.obs;

  Future<bool> submit() async {
    if (messageController.text.trim().length < 10) return false;
    isSubmitting.value = true;
    try {
      await _repository.submit(
        category: category.value,
        message: messageController.text.trim(),
      );
      return true;
    } finally {
      isSubmitting.value = false;
    }
  }

  @override
  void onClose() {
    messageController.dispose();
    super.onClose();
  }
}
