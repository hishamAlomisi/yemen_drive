import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../../../core/services/auth_session_service.dart';
import '../../../../core/realtime/tracking_hub_service.dart';
import '../../../ride/controllers/wallet_ride_payment_controller.dart';
import '../../../ride/models/wallet_ride_payment.dart';
import '../../account_routes.dart';
import '../repositories/wallet_top_up_repository.dart';
import '../../models/account_models.dart';
import '../repositories/wallet_repository.dart';

class WalletController extends GetxController with WidgetsBindingObserver {
  WalletController(this._repository);

  final WalletRepository _repository;
  StreamSubscription<TrackingHubEvent>? _walletEvents;
  StreamSubscription<void>? _walletReconnects;
  Future<void>? _walletRefresh;
  bool _walletRefreshRequested = false;
  final TextEditingController amountController = TextEditingController();
  final RxList<WalletTransaction> transactions = <WalletTransaction>[].obs;
  final RxDouble walletBalance = 0.0.obs;
  final RxDouble ledgerDebt = 0.0.obs;
  final RxDouble outstandingRideDebt = 0.0.obs;
  final rideDebts = <Map<String, Object?>>[].obs;
  final RxDouble totalSpent = 0.0.obs;
  final RxString amountText = ''.obs;
  final RxString selectedPaymentMethodId = ''.obs;
  final RxBool isLoading = true.obs;
  final RxBool hasLoaded = false.obs;
  final RxBool methodsLoading = false.obs;
  final RxString methodsError = ''.obs;
  final RxInt catalogRevision = 0.obs;
  WalletTopUpRepository? topUpRepository;
  WalletRidePaymentController? topUp;

  void _createTopUpFlow() {
    final repository = topUpRepository;
    if (repository == null) return;
    topUp?.dispose();
    topUp = WalletRidePaymentController(
      repository,
      onSucceeded: (_) {
        loadTransactions();
      },
    );
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    if (Get.isRegistered<TrackingHubService>()) {
      final hub = Get.find<TrackingHubService>();
      hub.stateChanges.register(this, (changes) async {
        if (changes.any((change) =>
            const {'wallet', 'account', 'ride'}.contains(change.resource))) {
          await loadTransactions(requireSuccess: true);
        }
      });
      _walletEvents = hub.events.listen((event) {
        if (event.name == 'notificationCreated' ||
            event.name == 'paymentUpdated' ||
            event.name == 'cashApprovalUpdated') unawaited(loadTransactions());
      });
      _walletReconnects =
          hub.connectionRestored.listen((_) => unawaited(loadTransactions()));
      unawaited(hub.setUserEventListening(this, true));
    }
    _selectInitialPaymentMethod();
    loadTransactions();
    if (Get.isRegistered<ApiClient>() &&
        Get.isRegistered<AuthSessionService>() &&
        Get.find<AuthSessionService>().currentUserId.value != null) {
      topUpRepository = WalletTopUpRepository(
        Get.find<ApiClient>(),
        Get.find<AuthSessionService>().currentUserId.value ?? 0,
      );
      _createTopUpFlow();
      topUp?.refresh('topup');
    }
    refreshMethods();
  }

  Future<void> refreshMethods() async {
    if (methodsLoading.value || !Get.isRegistered<ApiClient>()) return;
    methodsLoading.value = true;
    methodsError.value = '';
    try {
      if (!await AppEnvironment.loadPaymentMethods(Get.find<ApiClient>())) {
        methodsError.value = 'تعذر تحديث اتصال المحافظ. أعد المحاولة.';
      }
      catalogRevision.value++;
      if (selectedPaymentMethod == null) {
        selectedPaymentMethodId.value = '';
        _selectInitialPaymentMethod();
      }
    } catch (_) {
      methodsError.value = 'تعذر تحديث اتصال المحافظ. أعد المحاولة.';
    } finally {
      methodsLoading.value = false;
    }
  }

  Future<void> startTopUp() async {
    final flow = topUp;
    if (flow?.busy.value == true ||
        methodsLoading.value ||
        methodsError.value.isNotEmpty) {
      return;
    }
    final repository = topUpRepository;
    final method = selectedPaymentMethod;
    final amount = parsedAmount;
    if (flow == null ||
        repository == null ||
        method?.paymentMethodId == null ||
        amount == null ||
        !amount.isFinite ||
        amount <= 0 ||
        amount > 9999999999999999 ||
        (amount * 100 - (amount * 100).round()).abs() > .00001) {
      Get.snackbar('شحن المحفظة', 'أدخل مبلغاً صحيحاً واختر محفظة متاحة.');
      return;
    }
    repository.amount = amount;
    await flow.start('topup', method!.paymentMethodId!);
    if (flow.payment.value != null) {
      Get.toNamed<void>(AccountRoutes.topUpPayment);
    } else if (flow.error.value.isNotEmpty)
      Get.snackbar('تعذر الشحن', flow.error.value);
  }

  Future<void> changeTopUpMethod() async {
    final flow = topUp;
    if (flow == null || flow.busy.value) return;
    if (flow.payment.value?.canCancel == true) await flow.confirm(false);
    if (!flow.stateKnown.value || flow.payment.value?.canStartAnother != true) {
      return;
    }
    await topUpRepository?.clearFinished();
    _createTopUpFlow();
    await topUp?.refresh('topup');
    await refreshMethods();
    Get.offNamed<void>(AccountRoutes.addAmount);
  }

  Future<void> newTopUp() async {
    if (topUp?.payment.value?.succeeded == true) {
      await topUpRepository?.clearFinished();
      _createTopUpFlow();
      await topUp?.refresh('topup');
    }
    await refreshMethods();
    Get.toNamed<void>(
      topUp?.payment.value != null &&
              topUp?.payment.value?.canStartAnother != true
          ? AccountRoutes.topUpPayment
          : AccountRoutes.addAmount,
    );
  }

  Future<void> openInvoice(String id) async {
    final result = await topUpRepository?.getById(id);
    if (result is ApiSuccess<WalletRidePayment?> && result.data != null) {
      _createTopUpFlow();
      await topUp?.refresh('topup');
      Get.toNamed<void>(AccountRoutes.topUpPayment);
    } else {
      Get.snackbar('فاتورة الشحن', 'تعذر تحميل الفاتورة. أعد المحاولة.');
    }
  }

  void _selectInitialPaymentMethod() {
    if (selectedPaymentMethodId.value.isNotEmpty) return;
    for (final method in AppEnvironment.topUpPaymentMethods) {
      if (method.canTopUp) {
        selectedPaymentMethodId.value = method.id;
        return;
      }
    }
  }

  Future<void> loadTransactions({bool requireSuccess = false}) async {
    final running = _walletRefresh;
    if (running != null) {
      _walletRefreshRequested = true;
      try {
        await running;
      } catch (_) {
        if (requireSuccess) rethrow;
      }
      return;
    }
    final task = _loadTransactions();
    _walletRefresh = task;
    try {
      await task;
    } catch (_) {
      if (requireSuccess) rethrow;
    } finally {
      if (identical(_walletRefresh, task)) _walletRefresh = null;
    }
  }

  Future<void> _loadTransactions() async {
    isLoading.value = true;
    try {
      do {
        _walletRefreshRequested = false;
        final hub = Get.isRegistered<TrackingHubService>()
            ? Get.find<TrackingHubService>()
            : null;
        const resources = {'wallet', 'account', 'ride'};
        final epoch = hub?.stateChanges.epochForResources(resources);
        final wallet = await _repository.wallet();
        if (isClosed) return;
        if (epoch != hub?.stateChanges.epochForResources(resources)) {
          _walletRefreshRequested = true;
          continue;
        }
        transactions.assignAll(wallet.transactions);
        walletBalance.value = wallet.balance;
        ledgerDebt.value = wallet.ledgerDebt;
        outstandingRideDebt.value = wallet.outstandingRideDebt;
        rideDebts.assignAll(wallet.rideDebts);
        totalSpent.value = wallet.totalSpent;
        hasLoaded.value = true;
      } while (_walletRefreshRequested);
    } catch (_) {
      // Retain the last confirmed balance until reconnect or manual retry.
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  void setAmount(String value) => amountText.value = value;

  void selectPaymentMethod(String id) {
    if (AppEnvironment.paymentMethodById(id)?.canTopUp == true) {
      selectedPaymentMethodId.value = id;
    }
  }

  PaymentMethodItem? get selectedPaymentMethod {
    if (methodsError.value.isNotEmpty) return null;
    final id = selectedPaymentMethodId.value;
    for (final method in AppEnvironment.paymentMethods) {
      if (method.id == id && method.canTopUp) return method;
    }
    return null;
  }

  bool get requiresBankAccount => selectedPaymentMethod?.kind == 2;

  double? get parsedAmount => double.tryParse(
        amountText.value.runes
            .map(
              (rune) => rune >= 0x0660 && rune <= 0x0669
                  ? '${rune - 0x0660}'
                  : rune >= 0x06F0 && rune <= 0x06F9
                      ? '${rune - 0x06F0}'
                      : String.fromCharCode(rune),
            )
            .join()
            .replaceAll(',', '.')
            .replaceAll('٫', '.')
            .trim(),
      );

  @override
  void onClose() {
    if (Get.isRegistered<TrackingHubService>())
      Get.find<TrackingHubService>().stateChanges.unregister(this);
    WidgetsBinding.instance.removeObserver(this);
    _walletEvents?.cancel();
    _walletReconnects?.cancel();
    if (Get.isRegistered<TrackingHubService>())
      unawaited(
          Get.find<TrackingHubService>().setUserEventListening(this, false));
    topUp?.dispose();
    amountController.dispose();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !isClosed)
      unawaited(loadTransactions());
  }
}
