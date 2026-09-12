import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../widgets/auth_fields.dart';
import '../../widgets/auth_form_page.dart';
import '../controllers/registration_controller.dart';

class CompleteProfileScreen extends GetView<RegistrationController> {
  const CompleteProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => Obx(
        () => AuthFormPage(
          title: 'complete_profile_title'.tr,
          footer: Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: 'cancel'.tr,
                  variant: AppButtonVariant.outline,
                  onPressed: Get.back<void>,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'save'.tr,
                  isLoading: controller.isLoading.value,
                  onPressed: controller.completeProfile,
                ),
              ),
            ],
          ),
          children: <Widget>[
            Form(
              key: controller.profileFormKey,
              child: Column(
                children: <Widget>[
                  const _ProfileAvatar(),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    controller: controller.profileNameController,
                    hint: 'full_name'.tr,
                    validator: AppValidators.required,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AuthDropdownField(
                    hint: 'select_gender'.tr,
                    items: <String>['gender_male'.tr, 'gender_female'.tr],
                    value: controller.selectedGender.value,
                    onChanged: controller.selectGender,
                    validator: AppValidators.required,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppTextField(
                    controller: controller.streetController,
                    hint: 'street'.tr,
                    validator: AppValidators.required,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AuthDropdownField(
                    hint: 'select_city'.tr,
                    items: controller.cities,
                    value: controller.selectedCity.value,
                    onChanged: controller.selectCity,
                    validator: AppValidators.required,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AuthDropdownField(
                    hint: 'select_district'.tr,
                    items: controller.districts,
                    value: controller.selectedDistrict.value,
                    onChanged: controller.selectDistrict,
                    validator: AppValidators.required,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar();

  @override
  Widget build(BuildContext context) => Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            CircleAvatar(
              radius: 48,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              child: Icon(
                Icons.person_rounded,
                size: 52,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: .40),
              ),
            ),
            PositionedDirectional(
              bottom: -2,
              start: -2,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.black,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      );
}
