import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'auth_backdrop.dart';

/// Shared OTP screen styling for registration, device verification and recovery.
class AuthOtpPage extends StatelessWidget {
  const AuthOtpPage({
    required this.title,
    required this.subtitle,
    required this.codeField,
    required this.isLoading,
    required this.onVerify,
    this.resendAction,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget codeField;
  final bool isLoading;
  final VoidCallback onVerify;
  final Widget? resendAction;

  static const Color _blue = Color(0xFF087AC1);
  static const Color _cyan = Color(0xFF159FCB);

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = keyboardInset > 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const Positioned.fill(
            child: AuthBackdrop(showHeaderActions: false),
          ),
          AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(
              top: keyboardOpen ? MediaQuery.paddingOf(context).top : 0,
              bottom: keyboardInset,
            ),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final height = constraints.maxHeight;
                final shortScreen = height < 700;
                final panelHeight =
                    keyboardOpen ? height : height * (shortScreen ? .62 : .57);
                final bottomGap =
                    keyboardOpen ? 0.0 : height * (shortScreen ? .22 : .26);

                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: 14,
                      end: 14,
                      bottom: bottomGap,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        height: panelHeight,
                        child: _OtpPanel(
                          title: title,
                          subtitle: subtitle,
                          codeField: codeField,
                          isLoading: isLoading,
                          onVerify: onVerify,
                          resendAction: resendAction,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpPanel extends StatelessWidget {
  const _OtpPanel({
    required this.title,
    required this.subtitle,
    required this.codeField,
    required this.isLoading,
    required this.onVerify,
    this.resendAction,
  });

  final String title;
  final String subtitle;
  final Widget codeField;
  final bool isLoading;
  final VoidCallback onVerify;
  final Widget? resendAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = scheme.primary;
    final foreground = scheme.onSurface;
    final hintColor = isDark
        ? scheme.onSurface.withValues(alpha: .62)
        : const Color(0xFF8298B1);
    final borderColor = isDark
        ? scheme.onSurface.withValues(alpha: .20)
        : const Color(0xFFC9DFFC);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: borderColor, width: 1.35),
    );
    final themedChild = Theme(
      data: theme.copyWith(
        colorScheme: scheme.copyWith(primary: accent),
        textTheme: theme.textTheme.copyWith(
          bodyLarge: theme.textTheme.bodyLarge?.copyWith(
            color: foreground,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor:
              isDark ? scheme.surfaceContainerHigh : const Color(0xFFF9FCFF),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 14,
          ),
          hintStyle: TextStyle(color: hintColor, fontSize: 16),
          border: inputBorder,
          enabledBorder: inputBorder,
          focusedBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: accent, width: 1.8),
          ),
        ),
      ),
      child: Material(
        color: isDark
            ? scheme.surface.withValues(alpha: .98)
            : Colors.white.withValues(alpha: .98),
        elevation: 12,
        shadowColor: const Color(0x29102C50),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(42),
          side: BorderSide(
            color: isDark
                ? scheme.onSurface.withValues(alpha: .14)
                : const Color(0x99FFFFFF),
            width: 1.2,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsetsDirectional.fromSTEB(18, 15, 18, 16),
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
                                const Icon(Icons.arrow_back_rounded, size: 21),
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
                  Text(
                    title,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 27,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: hintColor,
                      fontSize: 15,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  codeField,
                  if (resendAction != null) ...<Widget>[
                    const SizedBox(height: 7),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: resendAction!,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _VerifyButton(isLoading: isLoading, onPressed: onVerify),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return themedChild;
  }
}

class _VerifyButton extends StatelessWidget {
  const _VerifyButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  static const Color _blue = AuthOtpPage._blue;
  static const Color _cyan = AuthOtpPage._cyan;

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
                : Text(
                    'verify'.tr,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      );
}
