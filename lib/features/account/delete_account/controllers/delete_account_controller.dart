import 'package:get/get.dart';

import '../repositories/delete_account_repository.dart';
import '../../../../core/services/auth_session_service.dart';

class DeleteAccountController extends GetxController {
  DeleteAccountController(this._repository);
  final DeleteAccountRepository _repository;
  final isSubmitting = false.obs;

  Future<bool> deleteAccount() async {
    isSubmitting.value = true;
    try {
      await _repository.delete();
      await Get.find<AuthSessionService>().signOut();
      return true;
    } finally {
      isSubmitting.value = false;
    }
  }
}
