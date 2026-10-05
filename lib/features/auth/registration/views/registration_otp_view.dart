import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../widgets/auth_otp_page.dart';
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
        () => AuthOtpPage(
          title: 'otp_title'.tr,
          subtitle: 'otp_subtitle'.tr,
          isLoading: controller.isLoading.value,
          onVerify: () => controller.verifyOtp(_code),
          codeField: OtpCodeField(
            initialCode: widget.initialCode,
            onChanged: (value) => _code = value,
          ),
          resendAction: TextButton(
            onPressed: controller.isLoading.value ? null : controller.resendOtp,
            child: Text('resend'.tr),
          ),
        ),
      );
}
