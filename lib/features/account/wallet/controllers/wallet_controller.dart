import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../models/account_models.dart';
import '../repositories/wallet_repository.dart';

class WalletController extends GetxController {
  WalletController(this._repository);

  final WalletRepository _repository;
  final TextEditingController amountController = TextEditingController();
  final TextEditingController bankAccountController = TextEditingController();
  final RxList<WalletTransaction> transactions = <WalletTransaction>[].obs;
  final RxDouble walletBalance = 0.0.obs;
  final RxDouble totalSpent = 0.0.obs;
  final RxDouble lastAddedAmount = 0.0.obs;
  final RxString amountText = ''.obs;
  final RxString selectedPaymentMethodId = 'visa'.obs;
  final RxBool isLoading = true.obs;
  final RxBool isSubmitting = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadTransactions();
  }

  Future<void> loadTransactions() async {
    isLoading.value = true;
    try {
      final wallet = await _repository.wallet();
      transactions.assignAll(wallet.transactions);
      walletBalance.value = wallet.balance;
      totalSpent.value = wallet.totalSpent;
    } finally {
      isLoading.value = false;
    }
  }

  void setAmount(String value) => amountText.value = value;

  void selectQuickAmount(double value) {
    final text = value.toStringAsFixed(0);
    amountController.text = text;
    amountController.selection = TextSelection.collapsed(offset: text.length);
    amountText.value = text;
  }

  void selectPaymentMethod(String id) => selectedPaymentMethodId.value = id;

  double? get parsedAmount =>
      double.tryParse(amountText.value.replaceAll(',', '.').trim());

  bool get canSubmit => (parsedAmount ?? 0) > 0 && !isSubmitting.value;

  Future<bool> addAmount({bool includeBankAccount = false}) async {
    final value = parsedAmount;
    if (value == null || value <= 0) return false;
    if (includeBankAccount && bankAccountController.text.trim().length < 8) {
      return false;
    }
    isSubmitting.value = true;
    try {
      final added = await _repository.addAmount(
        amount: value,
        paymentMethodId: selectedPaymentMethodId.value,
        bankAccountNumber:
            includeBankAccount ? bankAccountController.text.trim() : null,
      );
      lastAddedAmount.value = added;
      walletBalance.value += added;
      return true;
    } finally {
      isSubmitting.value = false;
    }
  }

  @override
  void onClose() {
    amountController.dispose();
    bankAccountController.dispose();
    super.onClose();
  }
}
