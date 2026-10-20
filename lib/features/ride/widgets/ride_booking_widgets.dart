import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/config/app_environment.dart';
import '../../../shared/widgets/app_button.dart';
import '../controllers/ride_controller.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import 'external_payment_methods.dart';

/// Choosing a method is a preference only. Settlement remains on the payment page.
class RidePaymentPreferenceButton extends GetView<RideController> {
  const RidePaymentPreferenceButton({super.key});

  @override
  Widget build(BuildContext context) => Obx(() => PaymentPreferenceButton(
        method: controller.preferredPaymentMethod.value,
        enabled:
            !controller.isSearchingForDriver.value && !controller.bookingLocked,
        onSelected: (method) {
          if (!controller.bookingLocked)
            controller.preferredPaymentMethod.value = method;
        },
      ));
}

class PaymentPreferenceButton extends StatelessWidget {
  const PaymentPreferenceButton({
    required this.method,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final String method;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final externalMethod = AppEnvironment.paymentMethodById(method);
    return SizedBox(
      width: 52,
      height: 52,
      child: IconButton(
        padding: const EdgeInsets.all(4),
        tooltip: 'payment_method'.tr,
        onPressed: !enabled
            ? null
            : () async {
                final selected = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  useSafeArea: true,
                  builder: (_) => PaymentPreferenceSheet(selected: method),
                );
                if (selected != null) onSelected(selected);
              },
        icon: method != 'cash' && method != 'wallet' && externalMethod != null
            ? Semantics(
                label: externalMethod.label,
                child: PaymentCatalogIcon(method: externalMethod),
              )
            : Icon(
                method != 'cash'
                    ? Icons.account_balance_wallet_outlined
                    : Icons.payments_outlined,
                semanticLabel: (method == 'wallet'
                        ? 'booking_wallet'
                        : method == 'cash'
                            ? 'booking_cash'
                            : 'booking_external_wallets')
                    .tr,
                color: AppColors.accent(context),
                size: 25,
              ),
      ),
    );
  }
}

class PaymentPreferenceSheet extends StatelessWidget {
  const PaymentPreferenceSheet({required this.selected, super.key});

  final String selected;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('payment_method'.tr,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              for (final option in <(String, String, IconData)>[
                ('cash', 'booking_cash', Icons.payments_outlined),
                (
                  'wallet',
                  'booking_wallet',
                  Icons.account_balance_wallet_outlined
                ),
              ])
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  leading: Icon(option.$3),
                  title: Text(option.$2.tr),
                  trailing: Icon(
                    selected == option.$1
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected == option.$1
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.outline,
                  ),
                  onTap: () => Navigator.of(context).pop(option.$1),
                ),
              ExternalPaymentMethodsTile(
                selected: selected,
                onSelected: (method) => Navigator.of(context).pop(method),
              ),
              const SizedBox(height: 12),
              Text('booking_payment_hint'.tr,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

/// Payment stays physically to the right of the search action in either locale.
class BookingActionBar extends StatelessWidget {
  const BookingActionBar({
    required this.label,
    required this.onPressed,
    required this.paymentButton,
    this.isLoading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget paymentButton;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return Row(
      textDirection: TextDirection.ltr,
      children: <Widget>[
        Expanded(
          child: Directionality(
            textDirection: direction,
            child: AppButton(
                label: label, onPressed: onPressed, isLoading: isLoading),
          ),
        ),
        const SizedBox(width: 6),
        Directionality(textDirection: direction, child: paymentButton),
      ],
    );
  }
}

class BookingRouteCard extends GetView<LocationController> {
  const BookingRouteCard({super.key});

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _BookingLocationRow(
              controller: controller.fromController,
              hint: 'booking_pickup'.tr,
              icon: Icons.person_pin_circle_outlined,
              onTap: () => controller.startSearch(field: 0),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1, color: Theme.of(context).dividerColor),
            ),
            _BookingLocationRow(
              controller: controller.toController,
              hint: 'booking_destination'.tr,
              icon: Icons.flag_outlined,
              onTap: () => controller.startSearch(field: 1),
            ),
          ],
        ),
      );
}

class _BookingLocationRow extends StatelessWidget {
  const _BookingLocationRow({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.onTap,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (_, value, __) => Text(
                    value.text.trim().isEmpty ? hint : value.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.edit_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      );
}
