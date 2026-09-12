import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../widgets/auth_form_page.dart';
import '../../widgets/otp_code_field.dart';
import '../controllers/password_reset_controller.dart';

class PasswordResetOtpView extends StatefulWidget {
  const PasswordResetOtpView({this.initialCode = '', super.key});
  final String initialCode;

  @override
  State<PasswordResetOtpView> createState() => _PasswordResetOtpViewState();
}

class _PasswordResetOtpViewState extends State<PasswordResetOtpView> {
  late String _code = widget.initialCode;
  final PasswordResetController controller =
      Get.find<PasswordResetController>();

  @override
  Widget build(BuildContext context) => Obx(
        () => AuthFormPage(
          title: 'reset_otp_title'.tr,
          subtitle: 'otp_sent_to'
              .trParams(<String, String>{'contact': controller.maskedIdentity}),
          footer: AppButton(
            label: 'verify'.tr,
            isLoading: controller.isLoading.value,
            onPressed: () => controller.verifyCode(_code),
          ),
          children: <Widget>[
            OtpCodeField(
              initialCode: widget.initialCode,
              onChanged: (value) => _code = value,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed:
                  controller.isLoading.value ? null : controller.resendCode,
              child: Text('resend'.tr),
            ),
          ],
        ),
      );
}
