import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/config/app_environment.dart';
import '../../models/account_models.dart';
import '../repositories/wallet_repository.dart';

class WalletController extends GetxController {
  WalletController(this._repository);

  final WalletRepository _repository;
  final TextEditingController amountController = TextEditingController();
  final RxList<WalletTransaction> transactions = <WalletTransaction>[].obs;
  final RxDouble walletBalance = 0.0.obs;
  final RxDouble totalSpent = 0.0.obs;
  final RxString amountText = ''.obs;
  final RxString selectedPaymentMethodId = ''.obs;
  final RxBool isLoading = true.obs;
  final RxBool hasLoaded = false.obs;

  @override
  void onInit() {
    super.onInit();
    _selectInitialPaymentMethod();
    loadTransactions();
  }

  void _selectInitialPaymentMethod() {
    if (selectedPaymentMethodId.value.isNotEmpty) return;
    for (final method in AppEnvironment.paymentMethods) {
      if (method.availableForWalletTopUp) {
        selectedPaymentMethodId.value = method.id;
        return;
      }
    }
  }

  Future<void> loadTransactions() async {
    isLoading.value = true;
    try {
      final wallet = await _repository.wallet();
      transactions.assignAll(wallet.transactions);
      walletBalance.value = wallet.balance;
      totalSpent.value = wallet.totalSpent;
      hasLoaded.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  void setAmount(String value) => amountText.value = value;

  void selectPaymentMethod(String id) => selectedPaymentMethodId.value = id;

  PaymentMethodItem? get selectedPaymentMethod {
    final id = selectedPaymentMethodId.value;
    for (final method in AppEnvironment.paymentMethods) {
      if (method.id == id && method.availableForWalletTopUp) return method;
    }
    return null;
  }

  bool get requiresBankAccount => selectedPaymentMethod?.kind == 2;

  double? get parsedAmount =>
      double.tryParse(amountText.value.replaceAll(',', '.').trim());

  @override
  void onClose() {
    amountController.dispose();
    super.onClose();
  }
}
