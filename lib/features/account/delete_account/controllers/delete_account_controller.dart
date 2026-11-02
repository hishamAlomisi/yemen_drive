import 'package:get/get.dart';

import '../repositories/delete_account_repository.dart';

class DeleteAccountController extends GetxController {
  DeleteAccountController(this._repository);
  final DeleteAccountRepository _repository;
  final isSubmitting = false.obs;

  Future<bool> deleteAccount() async {
    isSubmitting.value = true;
    try {
      await _repository.delete();
      return true;
    } finally {
      isSubmitting.value = false;
    }
  }
}
