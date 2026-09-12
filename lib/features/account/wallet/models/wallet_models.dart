import 'package:flutter/material.dart';

class WalletTransaction {
  const WalletTransaction(
      {required this.id,
      required this.title,
      required this.date,
      required this.amount,
      required this.isCredit});
  final String id;
  final String title;
  final DateTime date;
  final double amount;
  final bool isCredit;
}

class PaymentMethodItem {
  const PaymentMethodItem(
      {required this.id,
      required this.label,
      required this.subtitle,
      required this.icon});
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
}
