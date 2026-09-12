import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/directional_arrow.dart';

class AuthFormPage extends StatelessWidget {
  const AuthFormPage({
    required this.title,
    required this.children,
    required this.footer,
    this.subtitle,
    this.showBack = true,
    this.resizeToAvoidBottomInset = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget footer;
  final bool showBack;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: Directionality.of(context),
        child: AppScaffold(
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          body: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (showBack)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: Get.back<void>,
                          icon: const DirectionalArrowIcon(
                            forward: false,
                            size: 16,
                          ),
                          label: Text('back'.tr),
                        ),
                      ),
                    SizedBox(
                      height: showBack ? AppSpacing.sm : AppSpacing.lg,
                    ),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
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
                    const SizedBox(height: AppSpacing.lg),
                    ...children,
                    // A scroll view provides unbounded height; Spacer and
                    // IntrinsicHeight are intentionally avoided here.
                    const SizedBox(height: AppSpacing.lg),
                    footer,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class AuthInlineAction extends StatelessWidget {
  const AuthInlineAction({
    required this.label,
    required this.actionLabel,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(label),
          TextButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      );
}
