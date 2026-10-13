import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../features/ride/ride_routes.dart';

/// Shared branded background for the welcome page and the login sheet.
/// The logo and controls stay in this layer while the form card is shown.
class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({
    this.content,
    this.onBack,
    this.showHeaderActions = true,
    super.key,
  });

  final Widget? content;
  final VoidCallback? onBack;
  final bool showHeaderActions;

  static const Color _navy = Color(0xFF102C50);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final backAction = _HeaderAction(
      icon: isRtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
      tooltip: 'back'.tr,
      onPressed: onBack ?? () => Get.back<void>(),
    );
    final notificationsAction = _HeaderAction(
      icon: Icons.notifications_none_rounded,
      tooltip: 'notifications'.tr,
      showUnreadDot: true,
      onPressed: () => Get.toNamed<void>(RideRoutes.notifications),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFF5F8FB),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0xFFEAF5FF),
                  Color(0xFFFAFCFF),
                  Color(0xFFF5F8FB),
                ],
                stops: <double>[0, .56, 1],
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 0,
            right: 0,
            height: screenHeight * .18,
            child: IgnorePointer(
              child: Opacity(
                opacity: .78,
                child: Image.asset(
                  'assets/images/branding/sanaa_city_skyline.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: screenHeight * .285,
            child: IgnorePointer(
              child: Image.asset(
                'assets/images/branding/login_bottom_artwork.png',
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    6,
                    AppSpacing.md,
                    0,
                  ),
                  child: SizedBox(
                    height: 104,
                    child: Row(
                      textDirection: Directionality.of(context),
                      children: <Widget>[
                        if (showHeaderActions)
                          if (isRtl) backAction else notificationsAction,
                        Expanded(
                          child: Center(
                            child: Image.asset(
                              'assets/images/branding/yemen_drive_brand_logo.png',
                              width: 250,
                              height: 125,
                              fit: BoxFit.contain,
                              semanticLabel: 'يمن درايف',
                            ),
                          ),
                        ),
                        if (showHeaderActions)
                          if (isRtl) notificationsAction else backAction,
                      ],
                    ),
                  ),
                ),
                if (content != null) Expanded(child: content!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showUnreadDot = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool showUnreadDot;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Material(
              color: Colors.white.withValues(alpha: .96),
              shape: const CircleBorder(),
              elevation: 5,
              shadowColor: const Color(0x33102C50),
              child: IconButton(
                tooltip: tooltip,
                onPressed: onPressed,
                color: AuthBackdrop._navy,
                icon: Icon(icon, size: 25),
              ),
            ),
            if (showUnreadDot)
              const PositionedDirectional(
                top: 10,
                start: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFE53945),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 9, height: 9),
                ),
              ),
          ],
        ),
      );
}
