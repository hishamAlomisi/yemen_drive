import 'package:flutter/material.dart';

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.title,
    required this.date,
    required this.amount,
    required this.isCredit,
    required this.type,
    this.externalReference,
  });
  final String id;
  final String title;
  final DateTime date;
  final double amount;
  final bool isCredit;
  final int type;
  final String? externalReference;
  String? get transferReference =>
      !isCredit && externalReference?.startsWith('wallet-transfer:') == true
          ? externalReference!.substring('wallet-transfer:'.length)
          : null;
  String? get topUpId => externalReference?.startsWith('wallet-top-up:') == true
      ? externalReference!.split(':').last
      : null;
}

class WalletSnapshot {
  const WalletSnapshot({
    required this.balance,
    required this.transactions,
    this.outstandingRideDebt = 0,
    this.ledgerDebt = 0,
    this.rideDebts = const [],
  });

  final double balance;
  final double ledgerDebt;
  final List<WalletTransaction> transactions;
  final double outstandingRideDebt;
  final List<Map<String, Object?>> rideDebts;

  double get totalSpent => transactions
      .where((transaction) => !transaction.isCredit)
      .fold<double>(0, (sum, transaction) => sum + transaction.amount);
}

class PaymentMethodItem {
  const PaymentMethodItem({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    this.imageUrl,
    this.paymentMethodId,
    this.providerCode = '',
    this.kind = 0,
    this.isActive = true,
    this.isProviderConnected = true,
    this.isServiceAvailable = true,
    this.sortOrder = 0,
    this.availableForRidePayment = true,
    this.availableForWalletTopUp = true,
  });
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final String? imageUrl;
  final int? paymentMethodId;
  final String providerCode;
  final int kind;
  final bool isActive;
  final bool isProviderConnected;
  final bool isServiceAvailable;
  final int sortOrder;
  bool get canPayRide =>
      isActive &&
      isServiceAvailable &&
      availableForRidePayment &&
      isProviderConnected &&
      const {'floosak', 'jaib'}.contains(providerCode.toLowerCase());
  bool get canTopUp =>
      isActive &&
      isServiceAvailable &&
      isProviderConnected &&
      availableForWalletTopUp &&
      const {'floosak', 'jaib'}.contains(providerCode.toLowerCase());
  final bool availableForRidePayment;
  final bool availableForWalletTopUp;
}
