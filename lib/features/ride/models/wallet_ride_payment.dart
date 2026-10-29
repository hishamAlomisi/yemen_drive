class WalletRidePayment {
  const WalletRidePayment({
    required this.id,
    required this.rideId,
    required this.paymentMethodId,
    required this.providerCode,
    required this.providerName,
    required this.status,
    required this.nextAction,
    required this.customerName,
    required this.customerIsProviderVerified,
    required this.mobile,
    required this.amount,
    required this.currency,
    required this.feeCurrency,
    required this.feesKnown,
    required this.recipient,
    required this.message,
    this.fees,
    this.providerReference,
    this.paidAtUtc,
  });

  factory WalletRidePayment.fromJson(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}';
    final rideId = '${json['rideId'] ?? ''}';
    final methodId = int.tryParse('${json['paymentMethodId']}');
    final amount = _number(json['amount']);
    final providerCode = '${json['providerCode'] ?? ''}';
    final providerName = '${json['providerName'] ?? ''}'.trim();
    final customerName = '${json['customerName'] ?? ''}'.trim();
    if (id.isEmpty || rideId.isEmpty || methodId == null || amount == null) {
      throw const FormatException('Invalid wallet payment response');
    }
    return WalletRidePayment(
      id: id,
      rideId: rideId,
      paymentMethodId: methodId,
      providerCode: providerCode,
      providerName: providerName.isNotEmpty
          ? providerName
          : switch (providerCode.toLowerCase()) {
              'jaib' => 'جيب',
              'floosak' => 'فلوسك',
              _ => 'المحفظة الإلكترونية',
            },
      status: '${json['status'] ?? ''}',
      nextAction: '${json['nextAction'] ?? 'None'}',
      customerName: customerName,
      customerIsProviderVerified: json.containsKey('customerIsProviderVerified')
          ? json['customerIsProviderVerified'] == true
          : customerName.isNotEmpty,
      mobile: '${json['mobile'] ?? ''}',
      amount: amount,
      fees: _number(json['fees']),
      feesKnown: json['feesKnown'] == true && _number(json['fees']) != null,
      currency: '${json['currency'] ?? ''}',
      feeCurrency: '${json['feeCurrency'] ?? ''}',
      recipient: '${json['recipient'] ?? 'يمن درايف'}',
      message: '${json['message'] ?? ''}',
      providerReference: json['providerReference']?.toString(),
      paidAtUtc: DateTime.tryParse('${json['paidAtUtc'] ?? ''}'),
    );
  }

  final String id;
  final String rideId;
  final int paymentMethodId;
  final String providerCode;
  final String providerName;
  final String status;
  final String nextAction;
  final String customerName;
  final bool customerIsProviderVerified;
  final String mobile;
  final double amount;
  final double? fees;
  final bool feesKnown;
  final String currency;
  final String feeCurrency;
  final String recipient;
  final String message;
  final String? providerReference;
  final DateTime? paidAtUtc;

  bool get succeeded => status == 'Succeeded';
  bool get awaitingConfirmation =>
      status == 'AwaitingConfirmation' && nextAction == 'Confirmation';
  bool get awaitingCode =>
      status == 'AwaitingCode' &&
      const {'OneTimePassword', 'Pin', 'Voucher'}.contains(nextAction);
  bool get processing => status == 'Processing';
  bool get canStartAnother => status == 'Failed' || status == 'Cancelled';
  bool get locksOtherMethods => !canStartAnother;

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
}
