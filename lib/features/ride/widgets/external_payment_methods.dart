import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/cache/persistent_network_image.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/network/api_client.dart';
import '../../account/wallet/models/wallet_models.dart';

/// Uses the same catalog as ride settlement and wallet top-up. Opening or
/// selecting an item never starts a payment or changes the booking payload.
class ExternalPaymentMethodsTile extends StatelessWidget {
  const ExternalPaymentMethodsTile({
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final method = AppEnvironment.paymentMethodById(selected);
    final isExternal = selected != 'cash' && selected != 'wallet';
    return ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: const Icon(Icons.account_balance_wallet_outlined),
      title: Text('booking_external_wallets'.tr),
      subtitle: isExternal && method != null ? Text(method.label) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isExternal) ...<Widget>[
            const Icon(Icons.radio_button_checked),
            const SizedBox(width: 8),
          ],
          const Icon(Icons.arrow_forward_ios, size: 18),
        ],
      ),
      onTap: !enabled
          ? null
          : () async {
              final result = await Navigator.of(context).push<String>(
                MaterialPageRoute<String>(
                  builder: (_) =>
                      ExternalPaymentMethodsPage(selected: selected),
                ),
              );
              if (context.mounted && result != null) onSelected(result);
            },
    );
  }
}

class ExternalPaymentMethodsPage extends StatefulWidget {
  const ExternalPaymentMethodsPage({required this.selected, super.key});

  final String selected;

  @override
  State<ExternalPaymentMethodsPage> createState() =>
      _ExternalPaymentMethodsPageState();
}

class _ExternalPaymentMethodsPageState
    extends State<ExternalPaymentMethodsPage> {
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    var success = false;
    try {
      if (Get.isRegistered<ApiClient>()) {
        success =
            await AppEnvironment.loadPaymentMethods(Get.find<ApiClient>());
      }
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = !success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final methods = AppEnvironment.externalPaymentMethods;
    return Scaffold(
      appBar: AppBar(title: Text('booking_external_wallets'.tr)),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed
                ? _message(
                    'booking_external_load_error'.tr,
                    Icons.wifi_off_outlined,
                  )
                : methods.isEmpty
                    ? _message(
                        'booking_external_empty'.tr,
                        Icons.account_balance_wallet_outlined,
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: <Widget>[
                            Text('booking_external_hint'.tr,
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 16),
                            for (final method in methods) ...<Widget>[
                              _methodTile(context, method),
                              const Divider(height: 1),
                            ],
                          ],
                        ),
                      ),
      ),
    );
  }

  Widget _message(String message, IconData icon) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 40),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: Text('booking_external_retry'.tr),
              ),
            ],
          ),
        ),
      );

  Widget _methodTile(BuildContext context, PaymentMethodItem method) {
    final selected = method.id == widget.selected;
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      enabled: method.availableForRidePayment,
      leading: PaymentCatalogIcon(method: method),
      title: Text(method.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (method.subtitle.isNotEmpty) Text(method.subtitle),
          if (!method.availableForRidePayment)
            Text('booking_external_top_up_only'.tr),
        ],
      ),
      trailing: method.availableForRidePayment
          ? Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? colors.onSurface : colors.outline,
            )
          : null,
      onTap: method.availableForRidePayment
          ? () => Navigator.of(context).pop(method.id)
          : null,
    );
  }
}

class PaymentCatalogIcon extends StatelessWidget {
  const PaymentCatalogIcon({required this.method, super.key});

  final PaymentMethodItem method;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32,
        height: 32,
        child: method.imageUrl == null || method.imageUrl!.isEmpty
            ? Icon(method.icon)
            : PersistentNetworkImage(
                method.imageUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(method.icon),
              ),
      );
}
