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

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
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
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: scheme.surface,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: scheme.surface),
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
                    height: 80,
                    child: Row(
                      textDirection: Directionality.of(context),
                      children: <Widget>[
                        if (showHeaderActions)
                          if (isRtl) backAction else notificationsAction,
                        Expanded(
                          child: Center(
                            child: Image.asset(
                              'assets/images/branding/yemen_drive_brand_logo.png',
                              width: 75,
                              height: 75,
                              fit: BoxFit.cover,
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
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: .96),
              shape: const CircleBorder(),
              elevation: 0,
              shadowColor: const Color(0x33102C50),
              child: IconButton(
                tooltip: tooltip,
                onPressed: onPressed,
                color: Theme.of(context).colorScheme.onSurface,
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
