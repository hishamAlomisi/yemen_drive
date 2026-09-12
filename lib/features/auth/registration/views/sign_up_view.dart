import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../routes/auth_routes.dart';
import '../../widgets/auth_fields.dart';
import '../../widgets/auth_form_page.dart';
import '../controllers/registration_controller.dart';

class SignUpScreen extends GetView<RegistrationController> {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) => Obx(
        () => AuthFormPage(
          title: 'sign_up_title'.tr,
          footer: Column(
            children: <Widget>[
              AppButton(
                label: 'sign_up'.tr,
                isLoading: controller.isLoading.value,
                onPressed: controller.submit,
              ),
              AuthInlineAction(
                label: 'already_have_account'.tr,
                actionLabel: 'sign_in'.tr,
                onPressed: () => Get.offNamed<void>(AuthRoutes.signIn),
              ),
            ],
          ),
          children: <Widget>[
            Form(
              key: controller.signUpFormKey,
              child: Column(
                children: <Widget>[
                  PhoneTextField(
                    controller: controller.phoneController,
                    validator: AppValidators.phone,
                    country: controller.country.value,
                    onCountryChanged: controller.selectCountry,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  CheckboxListTile(
                    value: controller.termsAccepted.value,
                    onChanged: controller.toggleTerms,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      'terms_agreement'.tr,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
