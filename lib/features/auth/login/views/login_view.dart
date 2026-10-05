import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/utils/validators.dart';
import '../../models/auth_models.dart';
import '../../routes/auth_routes.dart';
import '../../widgets/auth_backdrop.dart';
import '../../widgets/auth_fields.dart';
import '../../widgets/auth_form_page.dart';
import '../controllers/login_controller.dart';

class LoginView extends GetView<LoginController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final height = constraints.maxHeight;
            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            final shortScreen = height < 700;
            final panelHeight = keyboardOpen
                ? height * .94
                : height * (shortScreen ? .59 : .55);
            final bottomGap =
                keyboardOpen ? 0.0 : height * (shortScreen ? .24 : .28);

            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned.fill(
                  child: const AuthBackdrop(showHeaderActions: false),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: bottomGap,
                  height: panelHeight,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 440),
                    curve: Curves.easeOutCubic,
                    builder: (context, progress, child) => Transform.translate(
                      offset:
                          Offset(0, (1 - progress) * (panelHeight + bottomGap)),
                      child: child,
                    ),
                    child: Obx(
                      () => _LoginPanel(
                        controller: controller,
                        country: controller.signInCountry.value,
                        obscurePassword: controller.obscurePassword.value,
                        rememberMe: controller.rememberMe.value,
                        isLoading: controller.isLoading.value,
                        onCreateAccount: () =>
                            Get.offNamed<void>(AuthRoutes.signUp),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.controller,
    required this.country,
    required this.obscurePassword,
    required this.rememberMe,
    required this.isLoading,
    required this.onCreateAccount,
  });

  final LoginController controller;
  final PhoneCountry country;
  final bool obscurePassword;
  final bool rememberMe;
  final bool isLoading;
  final VoidCallback onCreateAccount;

  static const Color _navy = Color(0xFF102C50);
  static const Color _blue = Color(0xFF087AC1);
  static const Color _cyan = Color(0xFF159FCB);
  static const Color _hint = Color(0xFF8298B1);
  static const Color _border = Color(0xFFC9DFFC);

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: const BorderSide(color: _border, width: 1.35),
    );
    final fieldTheme = baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(primary: _blue),
      textTheme: baseTheme.textTheme.copyWith(
        bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(
          color: _navy,
          fontSize: 17,
        ),
      ),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: const Color(0xFFF9FCFF),
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        hintStyle: const TextStyle(
          color: _hint,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: _blue, width: 1.8),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: Color(0xFFD94B55), width: 1.4),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: Color(0xFFD94B55), width: 1.8),
        ),
      ),
    );

    return Material(
      color: Colors.white.withValues(alpha: .98),
      elevation: 12,
      shadowColor: const Color(0x29102C50),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(42),
        side: const BorderSide(color: Color(0x99FFFFFF), width: 1.2),
      ),
      child: Theme(
        data: fieldTheme,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 15, 12, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 31,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => Get.back<void>(),
                      style: TextButton.styleFrom(
                        foregroundColor: _blue,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(48, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: Directionality.of(context) ==
                                TextDirection.rtl
                            ? <Widget>[
                                const Icon(
                                  Icons.arrow_back_rounded,
                                  size: 21,
                                ),
                                const SizedBox(width: 7),
                                Text('back'.tr),
                              ]
                            : <Widget>[
                                Text('back'.tr),
                                const SizedBox(width: 7),
                                const Icon(Icons.arrow_back_rounded, size: 21),
                              ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'sign_in_title'.tr,
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 28,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 17),
                  Form(
                    key: controller.signInFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        PhoneTextField(
                          controller: controller.signInIdentityController,
                          validator: AppValidators.phone,
                          country: country,
                          onCountryChanged: controller.selectCountry,
                          trailingIcon: Icons.phone_iphone_rounded,
                        ),
                        const SizedBox(height: 12),
                        PasswordTextField(
                          controller: controller.signInPasswordController,
                          hint: 'password'.tr,
                          obscureText: obscurePassword,
                          onToggleVisibility: controller.obscurePassword.toggle,
                          validator: AppValidators.required,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => controller.submit(),
                        ),
                        const SizedBox(height: 4),
                        CheckboxListTile(
                          value: rememberMe,
                          onChanged: controller.toggleRememberMe,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          visualDensity: const VisualDensity(
                            horizontal: -3,
                            vertical: -3,
                          ),
                          activeColor: _blue,
                          checkboxShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                          title: Text(
                            'remember_me'.tr,
                            style: const TextStyle(
                              color: _navy,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: () =>
                                Get.toNamed<void>(AuthRoutes.recoveryIdentity),
                            style: TextButton.styleFrom(
                              foregroundColor: _cyan,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              minimumSize: const Size(0, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'forgot_password'.tr,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SignInButton(
                    isLoading: isLoading,
                    onPressed: controller.submit,
                  ),
                  const SizedBox(height: 6),
                  AuthInlineAction(
                    label: 'dont_have_account'.tr,
                    actionLabel: 'sign_up'.tr,
                    onPressed: onCreateAccount,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  static const Color _blue = Color(0xFF087AC1);
  static const Color _cyan = Color(0xFF159FCB);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[_cyan, _blue],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _blue.withValues(alpha: .20),
                blurRadius: 15,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: TextButton(
            onPressed: isLoading ? null : onPressed,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white70,
              backgroundColor: Colors.transparent,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    textDirection: Directionality.of(context),
                    children: Directionality.of(context) == TextDirection.rtl
                        ? <Widget>[
                            const SizedBox(width: 27),
                            Expanded(
                              child: Center(
                                child: Text(
                                  'sign_in'.tr,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_forward_rounded, size: 27),
                          ]
                        : <Widget>[
                            const Icon(Icons.arrow_forward_rounded, size: 27),
                            Expanded(
                              child: Center(
                                child: Text(
                                  'sign_in'.tr,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 27),
                          ],
                  ),
          ),
        ),
      );
}
