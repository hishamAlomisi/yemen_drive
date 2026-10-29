import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_models.dart';
import '../../../core/realtime/tracking_hub_service.dart';
import '../ride_routes.dart';
import '../repositories/wallet_ride_payment_repository.dart';
import 'ride_controller.dart';
import 'wallet_ride_payment_controller.dart';

class PaymentController extends GetxController {
  final ApiClient _api = Get.find<ApiClient>();
  final RideController _ride = Get.find<RideController>();
  RxString get selectedMethod => _ride.preferredPaymentMethod;
  final RxBool useWalletBalance = false.obs;
  final RxDouble walletBalance = 0.0.obs;
  final RxDouble totalDue = 0.0.obs;
  final RxDouble waitingFee = 0.0.obs;
  final RxDouble baseFare = 0.0.obs;
  final RxDouble routeChangeFees = 0.0.obs;
  final RxDouble routeCompletedFare = 0.0.obs;
  final RxDouble serviceFeeAmount = 0.0.obs;
  final RxString summaryRideId = ''.obs;
  final RxDouble cancellationFee = 0.0.obs;
  final RxBool cashPaymentConfirmed = false.obs;
  final RxBool paymentCompleted = false.obs;
  final RxBool rideCompletedByDriver = false.obs;
  final RxInt cashRequestStatus = (-1).obs;
  final RxBool isPaying = false.obs;
  final RxString paymentActionError = ''.obs;
  final RxString summaryError = ''.obs;
  final RxBool isSubmittingReview = false.obs;
  final RxDouble rating = 0.0.obs;
  final TextEditingController reviewController = TextEditingController();
  StreamSubscription<TrackingHubEvent>? _hubEventSubscription;
  StreamSubscription<void>? _hubConnectionSubscription;
  bool _summaryLoading = false;
  bool _summaryRefreshRequested = false;
  final RxnString _dismissedExternalPaymentId = RxnString();
  late final WalletRidePaymentController externalPayment =
      WalletRidePaymentController(ApiWalletRidePaymentRepository(_api),
          onSucceeded: (_) {
    paymentCompleted.value = true;
    _ride.activeRidePaymentCompleted.value = true;
    unawaited(_ride.refreshActiveRide());
  });

  bool get selectedExternalWalletSupported => const {'floosak', 'jaib'}
      .contains(AppEnvironment.paymentMethodById(selectedMethod.value)
          ?.providerCode
          .toLowerCase());

  String get selectedExternalWalletName =>
      AppEnvironment.paymentMethodById(selectedMethod.value)?.label ??
      'المحفظة';

  bool get paymentOptionsLocked =>
      paymentCompleted.value ||
      isPaying.value ||
      externalPayment.locksOtherMethods;

  bool get mandatoryPaymentPending => _ride.mandatoryPaymentPending;

  void setPaymentPageMounted(bool mounted) {
    _ride.setPaymentPageMounted(mounted);
  }

  bool get showExternalPayment {
    final current = externalPayment.payment.value;
    if (current == null || current.rideId != _ride.currentRideId) return false;
    // A failed earlier wallet attempt must not replace a later confirmed cash
    // or internal-wallet payment for this ride.
    if (current.canStartAnother && paymentCompleted.value) return false;
    return !current.canStartAnother ||
        _dismissedExternalPaymentId.value != current.id;
  }

  void dismissExternalPayment() {
    final current = externalPayment.payment.value;
    if (current == null ||
        !current.canStartAnother ||
        externalPayment.busy.value ||
        !externalPayment.stateKnown.value) return;
    _dismissedExternalPaymentId.value = current.id;
    selectMethod('cash');
  }

  void selectMethod(String id) {
    if (!paymentOptionsLocked) {
      selectedMethod.value = id;
      paymentActionError.value = '';
    }
  }

  @override
  void onReady() {
    super.onReady();
    unawaited(loadPaymentSummary());
    if (Get.isRegistered<TrackingHubService>()) {
      final hub = Get.find<TrackingHubService>();
      _hubEventSubscription = hub.events.listen(_handleRealtimeEvent);
      _hubConnectionSubscription = hub.connectionRestored.listen((_) {
        unawaited(loadPaymentSummary());
      });
      unawaited(hub.setUserEventListening(this, true));
    }
  }

  void _handleRealtimeEvent(TrackingHubEvent event) {
    if (event.name != 'paymentUpdated' &&
        event.name != 'cashApprovalUpdated' &&
        event.name != 'rideStatusUpdated') {
      return;
    }
    final rideId = _ride.currentRideId;
    if (rideId == null || event.payload['rideId']?.toString() != rideId) return;
    unawaited(loadPaymentSummary());
  }

  Future<void> loadPaymentSummary() async {
    if (_summaryLoading) {
      _summaryRefreshRequested = true;
      return;
    }
    _summaryLoading = true;
    try {
      do {
        _summaryRefreshRequested = false;
        final rideId = _ride.currentRideId;
        if (rideId == null) return;
        await _loadPaymentSummary(rideId);
      } while (_summaryRefreshRequested);
    } finally {
      _summaryLoading = false;
    }
  }

  Future<void> _loadPaymentSummary(String rideId) async {
    if (summaryRideId.value != rideId) {
      paymentCompleted.value = false;
      cashPaymentConfirmed.value = false;
      rideCompletedByDriver.value = false;
      totalDue.value = 0;
    }
    final detail = await _api.execute<Object?>(
      model: 'RideModel',
      operation: 'get',
      data: <String, Object?>{'id': rideId},
    );
    if (detail is ApiSuccess && detail.data is Map) {
      summaryError.value = '';
      final values = Map<Object?, Object?>.from(detail.data as Map);
      final ride = values['ride'] is Map
          ? Map<Object?, Object?>.from(values['ride'] as Map)
          : values;
      final storedTotal = _number(ride['totalAmount'] ?? values['totalAmount']);
      final fare = _number(ride['customerPrice'] ?? ride['serverPrice']);
      final serviceFee = _number(ride['serviceFee'] ?? values['serviceFee']);
      if (_ride.currentRideId != rideId) return;
      _ride.applyPaymentChoiceSnapshot(ride);
      waitingFee.value = _number(ride['waitingFee']);
      routeChangeFees.value = _number(ride['routeChangeFees']);
      routeCompletedFare.value = _number(ride['routeCompletedFare']);
      baseFare.value = fare;
      summaryRideId.value = rideId;
      serviceFeeAmount.value = serviceFee;
      // Older development rides can predate the total snapshot. The agreed
      // fare plus its stored fee remains the authoritative display fallback.
      totalDue.value =
          storedTotal > 0 ? storedTotal : fare + serviceFee + waitingFee.value;
      cancellationFee.value = _number(ride['cancellationFee']);
      final rideStatus = '${ride['status'] ?? values['status'] ?? ''}';
      rideCompletedByDriver.value =
          rideStatus == 'Completed' || rideStatus == '6';
      final payments = values['payments'];
      paymentCompleted.value = values['paymentCompleted'] == true ||
          payments is List &&
              payments.any((raw) {
                if (raw is! Map) return false;
                final payment = Map<Object?, Object?>.from(raw);
                final status = '${payment['status'] ?? ''}'.toLowerCase();
                return status == '2' || status == 'paid';
              });
      _ride.activeRidePaymentCompleted.value = paymentCompleted.value;
      _ride.reconcilePaymentNavigation();
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
      if (_ride.currentRideId != rideId) return;
      await externalPayment.refresh(rideId);
      if (_ride.currentRideId == rideId &&
          externalPayment.payment.value?.rideId == rideId &&
          externalPayment.payment.value?.succeeded == true) {
        paymentCompleted.value = true;
      }
    } else {
      summaryError.value = detail is ApiFailure
          ? detail.problem.detail ?? detail.problem.title
          : 'تعذر تحديث بيانات الدفع. أعد المحاولة.';
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

  @override
  void onClose() {
    externalPayment.dispose();
    _hubEventSubscription?.cancel();
    _hubConnectionSubscription?.cancel();
    if (Get.isRegistered<TrackingHubService>()) {
      unawaited(
          Get.find<TrackingHubService>().setUserEventListening(this, false));
    }
    reviewController.dispose();
    super.onClose();
  }

  Future<void> pay() async {
    if (paymentCompleted.value ||
        isPaying.value ||
        externalPayment.locksOtherMethods) return;
    if (selectedExternalWalletSupported) {
      await startExternalWalletPayment();
      return;
    }
    if (selectedMethod.value == 'cash') {
      if (mandatoryPaymentPending) {
        await confirmCashSelection();
      } else {
        await _requestCashConfirmation();
      }
      return;
    }
    if (selectedMethod.value != 'wallet') {
      Get.snackbar('وسيلة غير متاحة',
          'الدفع بهذه الوسيلة غير متاح حالياً. اختر النقد أو محفظة يمن درايف.');
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
      if (rideCompletedByDriver.value) {
        Get.offAllNamed<void>(RideRoutes.review);
      } else {
        _ride.openActiveRide();
        Get.snackbar('تم الدفع', 'تم الدفع، وبانتظار إنهاء الرحلة من السائق.');
      }
    } catch (_) {
      Get.snackbar('تعذر الدفع', 'تحقق من رصيد المحفظة ثم أعد المحاولة.');
    } finally {
      isPaying.value = false;
    }
  }

  Future<void> startExternalWalletPayment() async {
    final rideId = _ride.currentRideId;
    final method = AppEnvironment.paymentMethodById(selectedMethod.value);
    if (rideId == null ||
        paymentCompleted.value ||
        isPaying.value ||
        method == null ||
        method.paymentMethodId == null ||
        !selectedExternalWalletSupported) {
      return;
    }
    await externalPayment.start(rideId, method.paymentMethodId!);
  }

  Future<void> retryExternalPayment() async {
    final current = externalPayment.payment.value;
    final rideId = _ride.currentRideId;
    if (current == null ||
        rideId == null ||
        current.rideId != rideId ||
        !current.canStartAnother ||
        paymentCompleted.value ||
        isPaying.value) {
      return;
    }
    // Recovery keeps the provider's server-owned method ID even if the catalog
    // has not been loaded after restarting the app.
    await externalPayment.start(rideId, current.paymentMethodId);
  }

  Future<void> refreshExternalPayment() async {
    final rideId = _ride.currentRideId;
    if (rideId != null) await externalPayment.refresh(rideId);
  }

  void finishPaidRide() {
    if (!paymentCompleted.value) return;
    if (rideCompletedByDriver.value ||
        _ride.pendingRatingRideId.value == _ride.currentRideId) {
      Get.offAllNamed<void>(RideRoutes.review);
    } else {
      _ride.activeRidePaymentCompleted.value = true;
      _ride.openActiveRide();
      Get.snackbar('تم الدفع', 'بانتظار إنهاء الرحلة من السائق.');
    }
  }

  Future<void> confirmCashSelection() async {
    final rideId = _ride.currentRideId;
    if (rideId == null ||
        !mandatoryPaymentPending ||
        paymentOptionsLocked ||
        selectedMethod.value != 'cash') return;
    isPaying.value = true;
    paymentActionError.value = '';
    try {
      final result = await _api.execute<Object?>(
        model: 'RideModel',
        operation: 'update',
        data: <String, Object?>{
          'id': rideId,
          'paymentMethodCode': 'cash',
        },
      );
      if (result is ApiFailure) {
        throw FormatException(result.problem.detail ?? result.problem.title);
      }
      await _ride.refreshActiveRide(requireSuccess: true);
      if (_ride.currentRideId != rideId) return;
      if (_ride.mandatoryPaymentPending ||
          _ride.activePaymentMethodCode.value.toLowerCase() != 'cash') {
        throw const FormatException(
            'لم يُؤكد تغيير وسيلة الدفع. حدّث الحالة ثم أعد المحاولة.');
      }
      _ride.openActiveRide();
    } on Object catch (error) {
      paymentActionError.value = error is FormatException
          ? error.message.toString()
          : 'تعذر اعتماد الدفع النقدي. تحقق من الاتصال ثم أعد المحاولة.';
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
          'idempotencyKey':
              'cash-request-$rideId-${DateTime.now().microsecondsSinceEpoch}',
        },
      );
      if (result is! ApiSuccess || result.data is! Map)
        throw const FormatException();
      cashRequestStatus.value =
          int.tryParse('${(result.data as Map)['status']}') ?? 0;
      await loadPaymentSummary();
      Get.snackbar('أُرسل طلب التأكيد',
          'سيصل السائق طلباً لتأكيد استلام المبلغ النقدي.');
    } catch (_) {
      Get.snackbar(
          'تعذر إرسال الطلب', 'تعذر طلب تأكيد الدفع النقدي من السائق.');
    } finally {
      isPaying.value = false;
    }
  }

  Future<void> finishCollectedCashRide() async {
    // Completing a ride is exclusively a driver operation. The customer can
    // only observe the confirmed payment and wait for the driver's finish.
    if (cashPaymentConfirmed.value && rideCompletedByDriver.value) {
      Get.offAllNamed<void>(RideRoutes.review);
    } else if (cashPaymentConfirmed.value) {
      Get.snackbar('تم استلام المبلغ', 'بانتظار إنهاء الرحلة من تطبيق السائق.');
    }
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

  Future<void> submitReview() async {
    if (rating.value < 1 || rating.value > 5) {
      Get.snackbar('اختر التقييم', 'حدد عدد النجوم قبل إرسال التقييم.');
      return;
    }
    final rideId = _ride.currentRideId;
    if (rideId == null || isSubmittingReview.value) {
      Get.snackbar('تعذر إرسال التقييم', 'لم يتم العثور على الرحلة الحالية.');
      return;
    }

    isSubmittingReview.value = true;
    try {
      final result = await _api.execute<Object?>(
        model: 'DriverRatingModel',
        operation: 'add',
        data: <String, Object?>{
          'rideId': int.tryParse(rideId),
          'score': rating.value,
          'comment': reviewController.text.trim(),
        },
      );
      if (result is! ApiSuccess) {
        throw const FormatException('تعذر حفظ تقييم السائق. حاول مرة أخرى.');
      }
      _ride.ratingSubmitted(rideId);
      rating.value = 0;
      reviewController.clear();
      Get.offAllNamed<void>(RideRoutes.rideThanks);
    } catch (_) {
      Get.snackbar('تعذر إرسال التقييم', 'تحقق من الاتصال ثم حاول مرة أخرى.');
    } finally {
      isSubmittingReview.value = false;
    }
  }
}
