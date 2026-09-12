import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../ride_routes.dart';

class PaymentController extends GetxController {
  final RxString selectedMethod = 'cash'.obs;
  final RxBool useWalletBalance = false.obs;
  final RxDouble rating = 0.0.obs;
  final TextEditingController reviewController = TextEditingController();

  void selectMethod(String id) => selectedMethod.value = id;

  void pay() => Get.toNamed<void>(RideRoutes.activeRide);

  void setRating(double value) => rating.value = value;

  void submitReview() => Get.offAllNamed<void>(RideRoutes.rideThanks);

  @override
  void onClose() {
    reviewController.dispose();
    super.onClose();
  }
}
