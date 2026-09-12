import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';

class ContactController extends GetxController {
  ContactController(this._client);
  final ApiClient _client;
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final messageController = TextEditingController();
  final isSubmitting = false.obs;

  Future<bool> send() async {
    final valid = nameController.text.trim().isNotEmpty &&
        messageController.text.trim().length >= 10;
    if (!valid) return false;
    isSubmitting.value = true;
    try {
      final result = await _client.execute<Object?>(
          model: 'SupportTicketModel',
          operation: 'add',
          data: <String, Object?>{
            'category': 'contact',
            'message':
                '${nameController.text.trim()}\n${emailController.text.trim()}\n${phoneController.text.trim()}\n${messageController.text.trim()}',
          });
      if (result is ApiSuccess) return true;
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  @override
  void onClose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    messageController.dispose();
    super.onClose();
  }
}
