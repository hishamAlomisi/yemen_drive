import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../shared/widgets/app_button.dart';
import '../../../../../shared/widgets/app_card.dart';
import '../../../../../shared/widgets/app_states.dart';
import '../../account_routes.dart';
import '../../models/account_models.dart';
import '../../widgets/account_widgets.dart';
import '../controllers/offers_controller.dart';

class OffersPage extends GetView<OffersController> {
  const OffersPage({this.embedded = false, super.key});

  final bool embedded;

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'العروض',
        showBack: false,
        bottomNavIndex: embedded ? null : 3,
        child: Obx(() {
          if (controller.isLoading.value) {
            return const SizedBox(height: 420, child: AppLoading());
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const AccountSectionTitle(
                title: 'عروض مخصصة لك',
                subtitle: 'استخدم الكوبون قبل تأكيد الحجز للاستفادة من الخصم',
              ),
              const SizedBox(height: AppSpacing.sm),
              ...controller.offers.map(
                (offer) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _OfferTile(
                    offer: offer,
                    onTap: () {
                      controller.select(offer);
                      Get.toNamed<void>(
                        AccountRoutes.offerDetails,
                        parameters: <String, String>{'id': offer.id},
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        }),
      );
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, required this.onTap});

  final RideOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .16),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.local_offer_rounded,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    offer.discount,
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    offer.title,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    offer.expiryLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_back_ios_new_rounded, size: 16),
          ],
        ),
      );
}

class OfferDetailsPage extends GetView<OffersController> {
  const OfferDetailsPage({super.key});

  @override
  Widget build(BuildContext context) => AccountPageTemplate(
        title: 'تفاصيل العرض',
        child: Obx(() {
          if (controller.isLoading.value) {
            return const SizedBox(height: 420, child: AppLoading());
          }
          final offer = controller.selectedOffer;
          if (offer == null) {
            return const SizedBox(
              height: 420,
              child: AppEmptyState(
                title: 'العرض غير متاح',
                message: 'قد يكون العرض منتهيًا أو غير متاح حاليًا.',
                icon: Icons.local_offer_outlined,
              ),
            );
          }
          return _OfferDetails(offer: offer);
        }),
      );
}

class _OfferDetails extends StatelessWidget {
  const _OfferDetails({required this.offer});

  final RideOffer offer;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .16),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.confirmation_number_rounded,
                size: 44,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              offer.discount,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(offer.title, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: offer.code));
                Get.snackbar('تم النسخ', 'نُسخ رمز الخصم إلى الحافظة.');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      offer.code,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        letterSpacing: 2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(Icons.copy_rounded, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(offer.description, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(
              offer.expiryLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'استخدام العرض',
              onPressed: () => Get.offAllNamed<void>('/home'),
            ),
          ],
        ),
      );
}
