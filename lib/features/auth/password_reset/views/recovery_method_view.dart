import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../shared/widgets/app_button.dart';
import '../../widgets/auth_fields.dart';
import '../../widgets/auth_form_page.dart';
import '../controllers/password_reset_controller.dart';
import '../models/password_reset_models.dart';

class ForgotPasswordMethodScreen extends GetView<PasswordResetController> {
  const ForgotPasswordMethodScreen({super.key});

  @override
  Widget build(BuildContext context) => Obx(
        () => AuthFormPage(
          title: 'forgot_password'.tr,
          footer: AppButton(
            label: 'send_otp'.tr,
            isLoading: controller.isLoading.value,
            onPressed: controller.sendCode,
          ),
          children: <Widget>[
            RecoveryMethodCard(
              channel: RecoveryChannel.sms,
              selected: true,
              maskedValue: controller.maskedIdentity,
              onTap: () => controller.selectChannel(RecoveryChannel.sms),
            ),
          ],
        ),
      );
}
