import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../widgets/auth_form_page.dart';
import '../../widgets/otp_code_field.dart';
import '../controllers/login_controller.dart';

class LoginOtpView extends StatefulWidget {
  const LoginOtpView({super.key});

  @override
  State<LoginOtpView> createState() => _LoginOtpViewState();
}

class _LoginOtpViewState extends State<LoginOtpView> {
  String _code = '';
  final LoginController controller = Get.find<LoginController>();

  @override
  Widget build(BuildContext context) => Obx(
        () => AuthFormPage(
          title: 'التحقق من الجهاز الجديد',
          subtitle: 'otp_sent_to'.trParams(
            <String, String>{'contact': controller.maskedDevicePhone},
          ),
          footer: AppButton(
            label: 'verify'.tr,
            isLoading: controller.isLoading.value,
            onPressed: () => controller.verifyDeviceOtp(_code),
          ),
          children: <Widget>[
            OtpCodeField(onChanged: (value) => _code = value),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      );
}
