import 'package:flutter/material.dart';

import '../network/api_client.dart';
import '../network/api_models.dart';
import '../../features/account/models/account_models.dart';

class AppEnvironment {
  AppEnvironment._();

  static late final String baseUrl;
  static String defaultCurrency = 'ر.ي';
  static String signalRHubUrl = '';
  static bool _isConfigured = false;

  static bool get isConfigured => _isConfigured;
  static List<PaymentMethodItem> paymentMethods = <PaymentMethodItem>[];

  static PaymentMethodItem? paymentMethodById(String id) {
    for (final method in paymentMethods) {
      if (method.id == id) return method;
    }
    return null;
  }

  static List<PaymentMethodItem> get externalPaymentMethods => paymentMethods
      .where((method) =>
          !<String>{'cash', 'wallet', 'yemendrivewallet'}
              .contains(method.id.toLowerCase()) &&
          (method.availableForRidePayment || method.availableForWalletTopUp))
      .toList(growable: false)
    ..sort((a, b) {
      final available = (b.canPayRide ? 1 : 0).compareTo(a.canPayRide ? 1 : 0);
      return available != 0 ? available : a.sortOrder.compareTo(b.sortOrder);
    });

  static List<PaymentMethodItem> get topUpPaymentMethods =>
      externalPaymentMethods
          .where((method) => method.availableForWalletTopUp)
          .toList()
        ..sort((a, b) {
          final available = (b.canTopUp ? 1 : 0).compareTo(a.canTopUp ? 1 : 0);
          return available != 0
              ? available
              : a.sortOrder.compareTo(b.sortOrder);
        });

  static Future<bool> loadPaymentMethods(ApiClient client) async {
    final result = await client.execute<Object?>(
        model: 'PaymentMethodModel', operation: 'list');
    if (result is! ApiSuccess || result.data is! List) return false;
    paymentMethods = (result.data as List)
        .whereType<Map<Object?, Object?>>()
        .where((raw) => raw['isActive'] == true || raw['kind'] == 3)
        .map((raw) {
      final kind = (raw['kind'] as num?)?.toInt() ?? 0;
      return PaymentMethodItem(
        id: '${raw['code'] ?? raw['id']}',
        paymentMethodId: int.tryParse('${raw['id']}'),
        providerCode: '${raw['providerCode'] ?? ''}',
        label: '${raw['nameAr'] ?? ''}',
        subtitle: '${raw['descriptionAr'] ?? ''}',
        kind: kind,
        isActive: raw['isActive'] == true,
        isProviderConnected: raw['isProviderConnected'] == true,
        isServiceAvailable: kind == 3
            ? raw['isServiceAvailable'] == true &&
                raw['isProviderConnected'] == true
            : raw['isActive'] == true,
        sortOrder: (raw['sortOrder'] as num?)?.toInt() ?? 0,
        imageUrl: '${raw['imageUrl'] ?? ''}'.trim().isEmpty
            ? null
            : '${raw['imageUrl']}',
        availableForRidePayment: raw['isAvailableForRidePayment'] == true,
        availableForWalletTopUp: raw['isAvailableForWalletTopUp'] == true,
        icon: kind == 1
            ? Icons.credit_card_rounded
            : kind == 2
                ? Icons.account_balance_rounded
                : Icons.account_balance_wallet_rounded,
      );
    }).toList(growable: false);
    return true;
  }

  static void configure({
    required String baseUrl,
    String signalRHubUrl = '',
  }) {
    AppEnvironment.baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    AppEnvironment.signalRHubUrl = signalRHubUrl.isEmpty
        ? _defaultSignalRHubUrl(AppEnvironment.baseUrl)
        : signalRHubUrl;
    _isConfigured = true;
  }

  static String _defaultSignalRHubUrl(String apiBaseUrl) {
    // The API controllers are under /api, while the actual Hub is mapped at
    // the host root (/hubs/tracking).
    final root = apiBaseUrl.replaceFirst(
      RegExp(r'/api(?:/v[0-9]+)?/?$', caseSensitive: false),
      '',
    );
    return '$root/hubs/tracking';
  }
}
