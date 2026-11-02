import 'package:get/get.dart';
import '../controllers/payment_controller.dart';

/// The review must survive disposal of the payment route it replaces.
class RideReviewBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<PaymentController>(
        tag: PaymentController.reviewTag)) {
      Get.lazyPut<PaymentController>(PaymentController.new,
          tag: PaymentController.reviewTag);
    }
  }
}
