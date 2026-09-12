import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../widgets/auth_fields.dart';
import '../../widgets/auth_form_page.dart';
import '../controllers/password_reset_controller.dart';

class RecoveryIdentityScreen extends GetView<PasswordResetController> {
  const RecoveryIdentityScreen({super.key});

  @override
  Widget build(BuildContext context) => Obx(
        () => AuthFormPage(
          title: 'recovery_identity_title'.tr,
          subtitle: 'recovery_identity_subtitle'.tr,
          footer: AppButton(
            label: 'send_otp'.tr,
            isLoading: controller.isLoading.value,
            onPressed: controller.submitIdentity,
          ),
          children: <Widget>[
            Form(
              key: controller.recoveryFormKey,
              child: PhoneTextField(
                controller: controller.identityController,
                validator: AppValidators.phone,
                country: controller.country.value,
                onCountryChanged: controller.selectCountry,
                textInputAction: TextInputAction.done,
              ),
            ),
          ],
        ),
      );
}
