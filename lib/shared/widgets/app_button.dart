import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

enum AppButtonVariant { primary, secondary, outline, text, danger }

enum AppButtonSize { small, medium, large }

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.large,
    this.isLoading = false,
    this.isDisabled = false,
    this.fullWidth = true,
    this.leading,
    this.trailing,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool isLoading;
  final bool isDisabled;
  final bool fullWidth;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final enabled = !isLoading && !isDisabled && onPressed != null;
    final foreground = switch (variant) {
      AppButtonVariant.primary => Theme.of(context).colorScheme.onPrimary,
      AppButtonVariant.secondary => Colors.white,
      AppButtonVariant.danger => Colors.white,
      AppButtonVariant.outline ||
      AppButtonVariant.text =>
        Theme.of(context).colorScheme.onSurface,
    };
    final background = switch (variant) {
      AppButtonVariant.primary => Theme.of(context).colorScheme.primary,
      AppButtonVariant.secondary => Theme.of(context).colorScheme.onSurface,
      AppButtonVariant.danger => AppColors.error,
      AppButtonVariant.outline || AppButtonVariant.text => Colors.transparent,
    };
    final verticalPadding = switch (size) {
      AppButtonSize.small => 10.0,
      AppButtonSize.medium => 13.0,
      AppButtonSize.large => 16.0,
    };
    final border = variant == AppButtonVariant.outline
        ? BorderSide(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .85),
          )
        : BorderSide.none;
    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: isLoading
          ? SizedBox(
              key: const ValueKey<String>('loading'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: foreground,
              ),
            )
          : Row(
              key: const ValueKey<String>('content'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  leading!,
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: verticalPadding,
          ),
          foregroundColor: foreground,
          backgroundColor: background,
          disabledBackgroundColor: background.withValues(alpha: .42),
          disabledForegroundColor: foreground.withValues(alpha: .65),
          side: border,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: child,
      ),
    );
  }
}
