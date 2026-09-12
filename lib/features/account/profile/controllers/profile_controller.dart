import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../repositories/profile_repository.dart';

class ProfileController extends GetxController {
  ProfileController(this._repository);
  final ProfileRepository _repository;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final RxString gender = ''.obs;
  final RxString displayName = ''.obs;
  final RxBool isSaving = false.obs;
  final RxBool isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    try {
      final profile = await _repository.get();
      nameController.text = profile.name ?? '';
      displayName.value = nameController.text;
      phoneController.text = profile.phone ?? '';
      addressController.text = profile.street ?? '';
      gender.value = profile.gender ?? '';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> save() async {
    isSaving.value = true;
    try {
      final profile = await _repository.update(
          name: nameController.text.trim(),
          phone: phoneController.text.trim(),
          gender: gender.value,
          street: addressController.text.trim());
      nameController.text = profile.name ?? nameController.text;
      displayName.value = nameController.text;
      phoneController.text = profile.phone ?? phoneController.text;
    } finally {
      isSaving.value = false;
    }
  }

  @override
  void onClose() {
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    super.onClose();
  }
}
