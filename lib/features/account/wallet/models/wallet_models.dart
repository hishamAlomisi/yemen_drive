import 'package:flutter/material.dart';

class WalletTransaction {
  const WalletTransaction(
      {required this.id,
      required this.title,
      required this.date,
      required this.amount,
      required this.isCredit,
      required this.type});
  final String id;
  final String title;
  final DateTime date;
  final double amount;
  final bool isCredit;
  final int type;
}

class WalletSnapshot {
  const WalletSnapshot({required this.balance, required this.transactions});

  final double balance;
  final List<WalletTransaction> transactions;

  double get totalSpent => transactions
      .where((transaction) => !transaction.isCredit)
      .fold<double>(0, (sum, transaction) => sum + transaction.amount);
}

class PaymentMethodItem {
  const PaymentMethodItem(
      {required this.id,
      required this.label,
      required this.subtitle,
      required this.icon,
      this.imageUrl,
      this.kind = 0,
      this.availableForRidePayment = true,
      this.availableForWalletTopUp = true});
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final String? imageUrl;
  final int kind;
  final bool availableForRidePayment;
  final bool availableForWalletTopUp;
}
