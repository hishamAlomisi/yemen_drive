import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/cache/persistent_network_image.dart';
import '../controllers/payment_controller.dart';

class PaymentMethodTile extends GetView<PaymentController> {
  const PaymentMethodTile({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.imageUrl,
    super.key,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) => Obx(() {
        final selected = controller.selectedMethod.value == id;
        final enabled = !controller.cashPaymentConfirmed.value &&
            !controller.isPaying.value;
        final colors = Theme.of(context).colorScheme;
        return Column(
          children: <Widget>[
            ListTile(
              enabled: enabled,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              leading: SizedBox(
                width: 32,
                height: 32,
                child: imageUrl == null || imageUrl!.isEmpty
                    ? Icon(icon, color: colors.onSurface)
                    : PersistentNetworkImage(imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(icon)),
              ),
              title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
              subtitle:
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              trailing: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? colors.onSurface : colors.outline),
              onTap: enabled ? () => controller.selectMethod(id) : null,
            ),
            const Divider(height: 1),
          ],
        );
      });
}

class RatingStars extends GetView<PaymentController> {
  const RatingStars({super.key});

  @override
  Widget build(BuildContext context) => Obx(
        () => Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: List<Widget>.generate(5, (index) {
            final value = index + 1.0;
            final selected = controller.rating.value >= value;
            return IconButton(
              onPressed: () => controller.setRating(value),
              iconSize: 39,
              tooltip: '$value من 5',
              color: AppColors.accent(context),
              icon: Icon(
                selected ? Icons.star_rounded : Icons.star_border_rounded,
              ),
            );
          }),
        ),
      );
}

class ReviewTag extends StatelessWidget {
  const ReviewTag({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => FilterChip(
        label: Text(label),
        onSelected: (_) {},
        selected: false,
        showCheckmark: false,
        side: BorderSide(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .12),
        ),
      );
}
