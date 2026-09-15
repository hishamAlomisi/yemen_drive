import 'package:get/get.dart';
import '../../models/account_models.dart';
import '../repositories/history_repository.dart';

class HistoryController extends GetxController {
  HistoryController(this._repository);

  final HistoryRepository _repository;
  final RxList<RideHistoryItem> rides = <RideHistoryItem>[].obs;
  final RxBool isLoading = true.obs;
  final RxString cancellingRideId = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    try {
      rides.assignAll(await _repository.list());
    } finally {
      isLoading.value = false;
    }
  }

  List<RideHistoryItem> byStatus(RideHistoryStatus status) =>
      rides.where((ride) => ride.status == status).toList(growable: false);

  Future<bool> cancelPaidCashRide(
    RideHistoryItem ride, {
    required bool creditCustomerWallet,
  }) async {
    if (cancellingRideId.value.isNotEmpty) return false;
    cancellingRideId.value = ride.id;
    try {
      await _repository.cancelPaidCashRide(
        ride.id,
        creditCustomerWallet: creditCustomerWallet,
      );
      await load();
      Get.snackbar(
        'تم إلغاء الرحلة',
        creditCustomerWallet
            ? 'أُضيف مبلغ الاسترداد إلى محفظتك بعد خصم رسم الإلغاء.'
            : 'سُجل استرداد المبلغ من السائق مباشرة.',
      );
      return true;
    } catch (_) {
      Get.snackbar('تعذر الإلغاء', 'تحقق من حالة الرحلة ثم أعد المحاولة.');
      return false;
    } finally {
      cancellingRideId.value = '';
    }
  }
}
