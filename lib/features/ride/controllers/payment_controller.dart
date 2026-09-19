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
  final RxDouble cancellationFee = 0.0.obs;
  final RxBool cashPaymentConfirmed = false.obs;
  final RxInt cashRequestStatus = (-1).obs;
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
      cancellationFee.value = _number(ride['cancellationFee']);
      final payments = values['payments'];
      cashPaymentConfirmed.value = payments is List &&
          payments.any((raw) {
            if (raw is! Map) return false;
            final payment = Map<Object?, Object?>.from(raw);
            final provider = '${payment['provider'] ?? ''}'.toLowerCase();
            final status = '${payment['status'] ?? ''}'.toLowerCase();
            return provider == 'cash' && (status == '2' || status == 'paid');
          });
      if (!cashPaymentConfirmed.value) {
        final cashRequest = await _api.execute<Object?>(
          model: 'CashPaymentRequestModel',
          operation: 'get',
          data: <String, Object?>{'rideId': rideId},
        );
        if (cashRequest is ApiSuccess && cashRequest.data is Map) {
          cashRequestStatus.value =
              int.tryParse('${(cashRequest.data as Map)['status']}') ?? -1;
        } else {
          cashRequestStatus.value = -1;
        }
      } else {
        cashRequestStatus.value = -1;
      }
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
      await _requestCashConfirmation();
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

  Future<void> _requestCashConfirmation() async {
    final rideId = _ride.currentRideId;
    if (rideId == null || isPaying.value) return;
    if (cashRequestStatus.value == 0 || cashRequestStatus.value == 1) {
      Get.snackbar('بانتظار السائق', 'تم إرسال طلب الدفع النقدي إلى السائق.');
      return;
    }
    isPaying.value = true;
    try {
      final result = await _api.execute<Object?>(
        model: 'CashPaymentRequestModel',
        operation: 'add',
        data: <String, Object?>{
          'rideId': rideId,
          'idempotencyKey': 'cash-request-$rideId-${DateTime.now().microsecondsSinceEpoch}',
        },
      );
      if (result is! ApiSuccess || result.data is! Map) throw const FormatException();
      cashRequestStatus.value = int.tryParse('${(result.data as Map)['status']}') ?? 0;
      await loadPaymentSummary();
      Get.snackbar('أُرسل طلب التأكيد', 'سيصل السائق طلباً لتأكيد استلام المبلغ النقدي.');
    } catch (_) {
      Get.snackbar('تعذر إرسال الطلب', 'تعذر طلب تأكيد الدفع النقدي من السائق.');
    } finally {
      isPaying.value = false;
    }
  }

  Future<void> finishCollectedCashRide() async {
    if (!cashPaymentConfirmed.value) return;
    await loadPaymentSummary();
    if (!cashPaymentConfirmed.value) {
      Get.snackbar('لم يكتمل التحصيل', 'لم يسجل السائق التحصيل النقدي بعد.');
      return;
    }
    Get.offAllNamed<void>(RideRoutes.rideThanks);
  }

  Future<bool> cancelCashPaidRide({required bool creditCustomerWallet}) async {
    final rideId = _ride.currentRideId;
    if (rideId == null || isPaying.value || !cashPaymentConfirmed.value) {
      return false;
    }
    isPaying.value = true;
    try {
      final result = await _api.execute<Object?>(
        model: 'RideModel',
        operation: 'cancel',
        data: <String, Object?>{
          'id': rideId,
          // The API uses explicit numeric values so the request is stable
          // without relying on enum-name serialization in Flutter.
          'cashCancellationRefundMethod': creditCustomerWallet ? 2 : 1,
        },
      );
      if (result is! ApiSuccess) {
        throw const FormatException('تعذر إلغاء الرحلة النقدية.');
      }
      cashPaymentConfirmed.value = false;
      await loadPaymentSummary();
      Get.snackbar(
        'تم إلغاء الرحلة',
        creditCustomerWallet
            ? 'أُضيف مبلغ الاسترداد إلى محفظتك بعد خصم رسم الإلغاء.'
            : 'سُجل استرداد المبلغ من السائق مباشرة.',
      );
      Get.offAllNamed<void>(RideRoutes.homeTransport);
      return true;
    } catch (_) {
      Get.snackbar(
        'تعذر الإلغاء',
        'تعذر تنفيذ الاسترداد الآن. تحقق من حالة الرحلة وحاول مرة أخرى.',
      );
      return false;
    } finally {
      isPaying.value = false;
    }
  }

  Future<bool> decideCashShortfall(
      {required int approvalId, required bool accept}) async {
    if (isPaying.value) return false;
    isPaying.value = true;
    try {
      final result = await _api.execute<Object?>(
        model: 'CashCollectionApprovalModel',
        operation: accept ? 'accept' : 'reject',
        data: <String, Object?>{'id': approvalId},
      );
      if (result is! ApiSuccess) throw const FormatException();
      await _ride.refreshActiveRide();
      Get.snackbar(
          accept ? 'تمت الموافقة' : 'تم الرفض',
          accept
              ? 'يمكن للسائق إكمال تسجيل التحصيل الآن.'
              : 'لن يتم خصم أي مبلغ من محفظتك.');
      return true;
    } catch (_) {
      Get.snackbar(
          'تعذر تنفيذ القرار', 'تحقق من الرصيد والاتصال ثم أعد المحاولة.');
      return false;
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
