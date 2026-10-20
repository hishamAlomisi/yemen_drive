import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/utils/validators.dart';
import '../../models/auth_models.dart';
import '../../routes/auth_routes.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../widgets/auth_fields.dart';
import '../../widgets/auth_form_page.dart';
import '../controllers/login_controller.dart';

class LoginView extends GetView<LoginController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(title: const Text('يمن درايف')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Obx(() => _LoginPanel(
                      controller: controller,
                      country: controller.signInCountry.value,
                      obscurePassword: controller.obscurePassword.value,
                      rememberMe: controller.rememberMe.value,
                      isLoading: controller.isLoading.value,
                      onCreateAccount: () =>
                          Get.offNamed<void>(AuthRoutes.signUp),
                    )),
              ),
            ),
          ),
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

  static const Color _hint = Color(0xFF777973);
  static const Color _border = Color(0xFFE7E8E2);

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final scheme = baseTheme.colorScheme;
    final isDark = baseTheme.brightness == Brightness.dark;
    final accent = scheme.primary;
    final panelColor = isDark
        ? scheme.surface.withValues(alpha: .98)
        : Colors.white.withValues(alpha: .98);
    final fieldColor =
        isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainer;
    final foreground = scheme.onSurface;
    final hintColor = isDark ? scheme.onSurface.withValues(alpha: .62) : _hint;
    final borderColor =
        isDark ? scheme.onSurface.withValues(alpha: .20) : _border;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: borderColor, width: 1.35),
    );
    final fieldTheme = baseTheme.copyWith(
      colorScheme: scheme.copyWith(primary: accent),
      textTheme: baseTheme.textTheme.copyWith(
        bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(
          color: foreground,
          fontSize: 16,
        ),
      ),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: fieldColor,
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        hintStyle: TextStyle(
          color: hintColor,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: accent, width: 1.8),
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
      color: panelColor,
      elevation: 0,
      shadowColor: const Color(0x29102C50),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark
              ? scheme.onSurface.withValues(alpha: .14)
              : const Color(0x99FFFFFF),
          width: 1.2,
        ),
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
                        foregroundColor: accent,
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
                      style: TextStyle(
                        color: foreground,
                        fontSize: 28,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
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
                          activeColor: accent,
                          checkboxShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                          title: Text(
                            'remember_me'.tr,
                            style: TextStyle(
                              color: foreground,
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
                              foregroundColor: accent,
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

  @override
  Widget build(BuildContext context) => AppButton(
        label: 'sign_in'.tr,
        isLoading: isLoading,
        onPressed: onPressed,
      );
}
