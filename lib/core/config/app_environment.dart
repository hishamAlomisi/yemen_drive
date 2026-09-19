import 'package:flutter/material.dart';

import '../network/api_client.dart';
import '../network/api_models.dart';
import '../../features/account/models/account_models.dart';

class AppEnvironment {
  AppEnvironment._();

  static late final String flavor;
  static late final String baseUrl;
  static String defaultCurrency = 'ر.ي';
  static bool useDemoData = true;
  // Used only by the web build. Android reads the restricted Maps SDK key
  // from the native manifest placeholder in local.properties.
  static String googleMapsApiKey = '';
  static String signalRHubUrl = '';
  static bool _isConfigured = false;

  static bool get isConfigured => _isConfigured;
  static bool get isProduction => flavor == 'prod';
  static List<PaymentMethodItem> paymentMethods = <PaymentMethodItem>[];

  static Future<void> loadPaymentMethods(ApiClient client) async {
    final result = await client.execute<Object?>(
        model: 'PaymentMethodModel', operation: 'list');
    if (result is! ApiSuccess || result.data is! List) return;
    paymentMethods = (result.data as List)
        .whereType<Map<Object?, Object?>>()
        .where((raw) => raw['isActive'] == true)
        .map((raw) {
      final kind = (raw['kind'] as num?)?.toInt() ?? 0;
      return PaymentMethodItem(
        id: '${raw['code'] ?? raw['id']}',
        label: '${raw['nameAr'] ?? ''}',
        subtitle: '${raw['descriptionAr'] ?? ''}',
        kind: kind,
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
  }

  static void configure({
    required String flavor,
    required String baseUrl,
    bool useDemoData = true,
    String googleMapsApiKey = '',
    String signalRHubUrl = '',
  }) {
    AppEnvironment.flavor = flavor;
    AppEnvironment.baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    AppEnvironment.useDemoData = useDemoData;
    AppEnvironment.googleMapsApiKey = googleMapsApiKey;
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
