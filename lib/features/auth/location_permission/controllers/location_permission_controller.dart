import 'package:get/get.dart';

class LocationPermissionController extends GetxController {
  final isLoading = false.obs;

  Future<void> useMyLocation() async => Get.offAllNamed<void>('/home');
  void skip() => Get.offAllNamed<void>('/home');
}
