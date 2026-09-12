import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/responsive/app_responsive.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/directional_arrow.dart';

class RidePageFrame extends StatelessWidget {
  const RidePageFrame({
    required this.body,
    this.title,
    this.actions,
    this.bottomNavigationBar,
    this.footer,
    this.showBack = true,
    this.applyHorizontalPadding = true,
    this.resizeToAvoidBottomInset = true,
    super.key,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? footer;
  final bool showBack;
  final bool applyHorizontalPadding;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: Directionality.of(context),
        child: AppScaffold(
          title: title,
          actions: actions,
          showBack: showBack,
          applyHorizontalPadding: applyHorizontalPadding,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          bottomNavigationBar: footer == null
              ? bottomNavigationBar
              : SafeArea(
                  top: false,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 8,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppBreakpoints.maxContent,
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            context.pagePadding.left,
                            AppSpacing.sm,
                            context.pagePadding.right,
                            AppSpacing.sm,
                          ),
                          child: footer!,
                        ),
                      ),
                    ),
                  ),
                ),
          body: body,
        ),
      );
}

class RideSectionHeader extends StatelessWidget {
  const RideSectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: .62),
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

class RideIconButton extends StatelessWidget {
  const RideIconButton({
    this.icon = Icons.circle,
    required this.onPressed,
    this.tooltip,
    this.backgroundColor,
    this.foregroundColor,
    this.badge = false,
    this.iconWidget,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool badge;
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Material(
            color: backgroundColor ?? Theme.of(context).colorScheme.surface,
            shape: const CircleBorder(),
            elevation: 2,
            child: IconButton(
              onPressed: onPressed,
              tooltip: tooltip,
              color: foregroundColor,
              icon: iconWidget ?? Icon(icon),
            ),
          ),
          if (badge)
            PositionedDirectional(
              top: 2,
              start: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 9, height: 9),
              ),
            ),
        ],
      );
}

class RideStatusPill extends StatelessWidget {
  const RideStatusPill({
    required this.label,
    this.icon,
    this.color,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final pillColor = color ?? Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pillColor.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 17, color: pillColor),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: pillColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RideSuccessView extends StatelessWidget {
  const RideSuccessView({
    required this.title,
    required this.message,
    required this.action,
    required this.actionLabel,
    this.icon = Icons.check_rounded,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback action;
  final String actionLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveContext(
              context,
            ).responsiveValue(phone: 8, tablet: 48),
            vertical: AppSpacing.xl,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: .18),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                  child: Icon(
                    icon,
                    size: 40,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                )
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.7,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .66),
                    ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: ResponsiveContext(
                  context,
                ).responsiveValue(phone: double.infinity, tablet: 360),
                child: FilledButton(
                  onPressed: action,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    actionLabel,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class RideBackButton extends StatelessWidget {
  const RideBackButton({super.key});

  @override
  Widget build(BuildContext context) => RideIconButton(
        icon: Icons.arrow_forward_ios_rounded,
        iconWidget: const DirectionalArrowIcon(forward: false),
        tooltip: 'رجوع',
        onPressed: () => Get.back<void>(),
      );
}
