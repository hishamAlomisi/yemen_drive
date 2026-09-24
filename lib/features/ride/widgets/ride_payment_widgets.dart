import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
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
        final enabled = !controller.cashPaymentConfirmed.value;
        return Opacity(
          opacity: enabled ? 1 : .52,
          child: AppCard(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            onTap: enabled ? () => controller.selectMethod(id) : null,
            borderColor: selected ? AppColors.primary : null,
            child: Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: imageUrl == null || imageUrl!.isEmpty
                      ? Icon(icon, color: AppColors.primaryDark)
                      : Image.network(imageUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              Icon(icon, color: AppColors.primaryDark)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.primary : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : Theme.of(context).colorScheme.outline,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: Colors.black,
                        )
                      : null,
                ),
              ],
            ),
          ),
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
              color: AppColors.primaryDark,
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
