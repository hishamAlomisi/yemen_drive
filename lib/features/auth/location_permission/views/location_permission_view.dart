import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/map_backdrop.dart';
import '../controllers/location_permission_controller.dart';

class LocationPermissionScreen extends GetView<LocationPermissionController> {
  const LocationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: MapBackdrop(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Obx(
                        () => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 94,
                              height: 94,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: .16),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.my_location_rounded,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              'enable_location_title'.tr,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'enable_location_subtitle'.tr,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            AppButton(
                              label: 'use_my_location'.tr,
                              isLoading: controller.isLoading.value,
                              onPressed: controller.useMyLocation,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            AppButton(
                              label: 'skip_for_now'.tr,
                              variant: AppButtonVariant.text,
                              onPressed: controller.skip,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
