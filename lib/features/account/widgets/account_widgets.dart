import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/responsive/app_responsive.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../account_routes.dart';

class AccountPageTemplate extends StatelessWidget {
  const AccountPageTemplate({
    required this.title,
    required this.child,
    this.actions,
    this.bottomAction,
    this.showBack = true,
    this.bottomNavIndex,
    this.scrollable = true,
    this.padding = const EdgeInsets.only(top: AppSpacing.sm),
    super.key,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottomAction;
  final bool showBack;
  final int? bottomNavIndex;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: <Widget>[
        Expanded(
          child: scrollable
              ? SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: padding,
                  child: child,
                )
              : Padding(padding: padding, child: child),
        ),
        if (bottomAction != null)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: bottomAction,
          ),
      ],
    );

    return Directionality(
      textDirection: Directionality.of(context),
      child: AppScaffold(
        title: title,
        showBack: showBack,
        actions: actions,
        body: body,
        bottomNavigationBar: bottomNavIndex == null
            ? null
            : Directionality(
                textDirection: Directionality.of(context),
                child: AppBottomNav(
                  currentIndex: bottomNavIndex!,
                  onTap: (index) => _navigateFromBottomBar(
                    currentIndex: bottomNavIndex!,
                    nextIndex: index,
                  ),
                ),
              ),
      ),
    );
  }

  void _navigateFromBottomBar({
    required int currentIndex,
    required int nextIndex,
  }) {
    if (currentIndex == nextIndex) return;
    final route = switch (nextIndex) {
      0 => '/home',
      1 => AccountRoutes.favourites,
      2 => AccountRoutes.wallet,
      3 => AccountRoutes.offers,
      _ => AccountRoutes.profile,
    };
    Get.offNamed<void>(route);
  }
}

class AccountSectionTitle extends StatelessWidget {
  const AccountSectionTitle({
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
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

class AccountListTile extends StatelessWidget {
  const AccountListTile({
    required this.title,
    required this.icon,
    this.imageUrl,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? imageUrl;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                      (iconColor ?? AppColors.primary).withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? AppColors.primaryDark,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              trailing ?? Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            ],
          ),
        ),
      );
}

class AccountChoiceTile extends StatelessWidget {
  const AccountChoiceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.imageUrl,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? imageUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        borderColor: selected ? AppColors.primary : null,
        child: Row(
          children: <Widget>[
            _ChoiceLogo(imageUrl: imageUrl, icon: icon, selected: selected),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primaryDark : null,
            ),
          ],
        ),
      );
}

class _ChoiceLogo extends StatelessWidget {
  const _ChoiceLogo({required this.imageUrl, required this.icon, required this.selected});
  final String? imageUrl; final IconData icon; final bool selected;
  @override Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) return Icon(icon, color: selected ? AppColors.primaryDark : null);
    return SizedBox(width: 32, height: 32, child: Image.network(imageUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(icon, color: selected ? AppColors.primaryDark : null)));
  }
}

class AccountMetricCard extends StatelessWidget {
  const AccountMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.highlighted = false,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => AppCard(
        color: highlighted ? AppColors.primary : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon,
              color: highlighted
                  ? Theme.of(context).colorScheme.onPrimary
                  : AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: highlighted
                        ? Theme.of(context).colorScheme.onPrimary
                        : null,
                  ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: highlighted
                        ? Theme.of(context)
                            .colorScheme
                            .onPrimary
                            .withValues(alpha: .72)
                        : null,
                  ),
            ),
          ],
        ),
      );
}

class AccountResponsiveGrid extends StatelessWidget {
  const AccountResponsiveGrid({
    required this.children,
    this.mobileColumns = 2,
    this.wideColumns = 3,
    this.spacing = AppSpacing.sm,
    super.key,
  });

  final List<Widget> children;
  final int mobileColumns;
  final int wideColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = context.isCompactLayout ? mobileColumns : wideColumns;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: children
                .map((child) => SizedBox(width: width, child: child))
                .toList(growable: false),
          );
        },
      );
}

class AccountSuccessPanel extends StatelessWidget {
  const AccountSuccessPanel({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.value,
    super.key,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? value;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: <Widget>[
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success.withValues(alpha: .16),
              ),
              child: Icon(
                Icons.verified_rounded,
                color: AppColors.success,
                size: 48,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (value != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                value!,
                style: Theme.of(
                  context,
                )
                    .textTheme
                    .headlineLarge
                    ?.copyWith(color: AppColors.primaryDark),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: actionLabel, onPressed: onAction),
          ],
        ),
      );
}

class AccountRouteLine extends StatelessWidget {
  const AccountRouteLine({
    required this.pickup,
    required this.destination,
    super.key,
  });

  final String pickup;
  final String destination;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Icon(Icons.radio_button_checked, color: AppColors.primary),
              Container(
                height: 24,
                width: 2,
                color: Theme.of(context).dividerColor,
              ),
              Icon(Icons.location_on_rounded, color: AppColors.secondary),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('نقطة الانطلاق'),
                Text(pickup, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.sm),
                const Text('الوجهة'),
                Text(destination, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      );
}

class AccountInfoBanner extends StatelessWidget {
  const AccountInfoBanner({
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.color,
    super.key,
  });

  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bannerColor = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: bannerColor.withValues(alpha: .28)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: bannerColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
