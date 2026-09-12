import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../widgets/auth_form_page.dart';
import '../../widgets/otp_code_field.dart';
import '../controllers/registration_controller.dart';

class RegistrationOtpView extends StatefulWidget {
  const RegistrationOtpView({this.initialCode = '', super.key});
  final String initialCode;

  @override
  State<RegistrationOtpView> createState() => _RegistrationOtpViewState();
}

class _RegistrationOtpViewState extends State<RegistrationOtpView> {
  late String _code = widget.initialCode;
  final RegistrationController controller = Get.find<RegistrationController>();

  @override
  Widget build(BuildContext context) => Obx(
        () => AuthFormPage(
          title: 'otp_title'.tr,
          subtitle: 'otp_subtitle'.tr,
          footer: AppButton(
            label: 'verify'.tr,
            isLoading: controller.isLoading.value,
            onPressed: () => controller.verifyOtp(_code),
          ),
          children: <Widget>[
            OtpCodeField(
              initialCode: widget.initialCode,
              onChanged: (value) => _code = value,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed:
                  controller.isLoading.value ? null : controller.resendOtp,
              child: Text('resend'.tr),
            ),
          ],
        ),
      );
}
