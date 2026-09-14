import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_models.dart';
import 'ride_controller.dart';
import '../ride_routes.dart';

class PaymentController extends GetxController {
  final ApiClient _api = Get.find<ApiClient>();
  final RideController _ride = Get.find<RideController>();
  final RxString selectedMethod = 'cash'.obs;
  final RxBool useWalletBalance = false.obs;
  final RxDouble walletBalance = 0.0.obs;
  final RxDouble totalDue = 0.0.obs;
  final RxBool isPaying = false.obs;
  final RxDouble rating = 0.0.obs;
  final TextEditingController reviewController = TextEditingController();

  void selectMethod(String id) => selectedMethod.value = id;

  @override
  void onReady() {
    super.onReady();
    loadPaymentSummary();
  }

  Future<void> loadPaymentSummary() async {
    final rideId = _ride.currentRideId;
    if (rideId == null) return;
    final detail = await _api.execute<Object?>(
      model: 'RideModel',
      operation: 'get',
      data: <String, Object?>{'id': rideId},
    );
    if (detail is ApiSuccess && detail.data is Map) {
      final values = Map<Object?, Object?>.from(detail.data as Map);
      final ride = values['ride'] is Map
          ? Map<Object?, Object?>.from(values['ride'] as Map)
          : values;
      final storedTotal = _number(ride['totalAmount'] ?? values['totalAmount']);
      final fare = _number(ride['customerPrice'] ?? ride['serverPrice']);
      final serviceFee = _number(ride['serviceFee'] ?? values['serviceFee']);
      // Older development rides can predate the total snapshot. The agreed
      // fare plus its stored fee remains the authoritative display fallback.
      totalDue.value = storedTotal > 0 ? storedTotal : fare + serviceFee;
    }
    final wallet = await _api.execute<Object?>(
      model: 'WalletModel',
      operation: 'get',
      data: const <String, Object?>{},
    );
    if (wallet is ApiSuccess && wallet.data is Map) {
      walletBalance.value = _number((wallet.data as Map)['balance']);
    }
  }

  Future<void> pay() async {
    if (selectedMethod.value == 'cash') {
      await _confirmCashCollection();
      return;
    }
    if (selectedMethod.value != 'wallet') {
      Get.snackbar(
          'وسيلة غير متاحة', 'هذه الوسيلة ستتاح عند ربط مزود دفع معتمد.');
      return;
    }
    final rideId = _ride.currentRideId;
    if (rideId == null || totalDue.value <= 0 || isPaying.value) return;
    isPaying.value = true;
    try {
      final result = await _api.execute<Object?>(
        model: 'PaymentModel',
        operation: 'add',
        data: <String, Object?>{
          'rideId': rideId,
          'amount': totalDue.value,
          'provider': 'YemenDriveWallet',
          'idempotencyKey':
              'wallet-$rideId-${DateTime.now().microsecondsSinceEpoch}',
        },
      );
      if (result is! ApiSuccess)
        throw const FormatException('تعذر إتمام الدفع من المحفظة.');
      await loadPaymentSummary();
      Get.offAllNamed<void>(RideRoutes.rideThanks);
    } catch (_) {
      Get.snackbar('تعذر الدفع', 'تحقق من رصيد المحفظة ثم أعد المحاولة.');
    } finally {
      isPaying.value = false;
    }
  }

  Future<void> _confirmCashCollection() async {
    final rideId = _ride.currentRideId;
    if (rideId == null || isPaying.value) return;
    isPaying.value = true;
    try {
      final result = await _api.execute<Object?>(
        model: 'RideModel',
        operation: 'get',
        data: <String, Object?>{'id': rideId},
      );
      if (result is! ApiSuccess || result.data is! Map) {
        throw const FormatException('تعذر التحقق من تحصيل السائق.');
      }
      final payload = Map<Object?, Object?>.from(result.data as Map);
      final payments = payload['payments'];
      final cashCollected = payments is List && payments.any((raw) {
        if (raw is! Map) return false;
        final payment = Map<Object?, Object?>.from(raw);
        final provider = '${payment['provider'] ?? ''}'.toLowerCase();
        final status = '${payment['status'] ?? ''}'.toLowerCase();
        return provider == 'cash' && (status == '2' || status == 'paid');
      });
      if (!cashCollected) {
        Get.snackbar(
          'لم يُسجّل التحصيل بعد',
          'لم يؤكد السائق استلام المبلغ النقدي. اطلب منه تسجيل التحصيل أولاً.',
        );
        return;
      }
      await loadPaymentSummary();
      Get.snackbar('تم تأكيد الدفع', 'سجّل السائق التحصيل النقدي بنجاح.');
      Get.offAllNamed<void>(RideRoutes.rideThanks);
    } catch (_) {
      Get.snackbar('تعذر التحقق', 'تعذر التحقق من تحصيل السائق، حاول مرة أخرى.');
    } finally {
      isPaying.value = false;
    }
  }

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;

  void setRating(double value) => rating.value = value;

  void submitReview() => Get.offAllNamed<void>(RideRoutes.rideThanks);

  @override
  void onClose() {
    reviewController.dispose();
    super.onClose();
  }
}
