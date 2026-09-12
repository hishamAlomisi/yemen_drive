import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../widgets/auth_fields.dart';
import '../../widgets/auth_form_page.dart';
import '../controllers/password_reset_controller.dart';

class NewPasswordScreen extends GetView<PasswordResetController> {
  const NewPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) => Obx(
        () => AuthFormPage(
          title: 'new_password_title'.tr,
          subtitle: 'new_password_subtitle'.tr,
          footer: AppButton(
            label: 'save'.tr,
            isLoading: controller.isLoading.value,
            onPressed: controller.submitNewPassword,
          ),
          children: <Widget>[
            Form(
              key: controller.passwordFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  PasswordTextField(
                    controller: controller.newPasswordController,
                    hint: 'new_password'.tr,
                    obscureText: controller.obscurePassword.value,
                    onToggleVisibility: controller.obscurePassword.toggle,
                    validator: AppValidators.password,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PasswordTextField(
                    controller: controller.confirmPasswordController,
                    hint: 'confirm_password'.tr,
                    obscureText: controller.obscureConfirmation.value,
                    onToggleVisibility: controller.obscureConfirmation.toggle,
                    validator: (String? value) => AppValidators.confirmPassword(
                      value,
                      controller.newPasswordController.text,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => controller.submitNewPassword(),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'password_hint'.tr,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
