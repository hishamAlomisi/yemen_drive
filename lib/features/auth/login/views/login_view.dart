import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../routes/auth_routes.dart';
import '../../widgets/auth_fields.dart';
import '../../widgets/auth_form_page.dart';
import '../controllers/login_controller.dart';

class LoginView extends GetView<LoginController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) => Obx(
        () => AuthFormPage(
          title: 'sign_in_title'.tr,
          footer: Column(
            children: <Widget>[
              AppButton(
                label: 'sign_in'.tr,
                isLoading: controller.isLoading.value,
                onPressed: controller.submit,
              ),
              AuthInlineAction(
                label: 'dont_have_account'.tr,
                actionLabel: 'sign_up'.tr,
                onPressed: () => Get.offNamed<void>(AuthRoutes.signUp),
              ),
            ],
          ),
          children: <Widget>[
            Form(
              key: controller.signInFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  PhoneTextField(
                    controller: controller.signInIdentityController,
                    validator: AppValidators.phone,
                    country: controller.signInCountry.value,
                    onCountryChanged: controller.selectCountry,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PasswordTextField(
                    controller: controller.signInPasswordController,
                    hint: 'password'.tr,
                    obscureText: controller.obscurePassword.value,
                    onToggleVisibility: controller.obscurePassword.toggle,
                    validator: AppValidators.required,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => controller.submit(),
                  ),
                  CheckboxListTile(
                    value: controller.rememberMe.value,
                    onChanged: controller.toggleRememberMe,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      'remember_me'.tr,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: () =>
                          Get.toNamed<void>(AuthRoutes.recoveryIdentity),
                      child: Text('forgot_password'.tr),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
