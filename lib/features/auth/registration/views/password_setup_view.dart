import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../widgets/auth_fields.dart';
import '../../widgets/auth_form_page.dart';
import '../controllers/registration_controller.dart';

class PasswordSetupScreen extends GetView<RegistrationController> {
  const PasswordSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => Obx(
        () => AuthFormPage(
          title: 'set_password_title'.tr,
          subtitle: 'set_password_subtitle'.tr,
          footer: AppButton(
            label: 'register'.tr,
            onPressed: controller.submitPassword,
          ),
          children: <Widget>[
            Form(
              key: controller.passwordFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  PasswordTextField(
                    controller: controller.passwordController,
                    hint: 'password'.tr,
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
                      controller.passwordController.text,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => controller.submitPassword(),
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
