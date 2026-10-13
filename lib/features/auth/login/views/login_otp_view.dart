import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/auth_otp_page.dart';
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
        () => AuthOtpPage(
          title: 'التحقق من الجهاز الجديد',
          subtitle: 'otp_sent_to'.trParams(
            <String, String>{'contact': controller.maskedDevicePhone},
          ),
          isLoading: controller.isLoading.value,
          onVerify: () => controller.verifyDeviceOtp(_code),
          codeField: OtpCodeField(
            key: ValueKey<int>(controller.otpFieldRevision.value),
            onChanged: (value) => _code = value,
          ),
          resendAction: TextButton(
            onPressed:
                controller.isLoading.value ? null : controller.resendDeviceOtp,
            child: Text('resend'.tr),
          ),
        ),
      );
}
