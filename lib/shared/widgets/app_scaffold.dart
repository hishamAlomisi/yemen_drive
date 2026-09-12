import 'package:flutter/material.dart';

import '../../core/responsive/app_responsive.dart';
import 'directional_arrow.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.body,
    this.title,
    this.actions,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset = true,
    this.safeTop = true,
    this.safeBottom = true,
    this.showBack = false,
    this.applyHorizontalPadding = true,
    this.backgroundColor,
    super.key,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool resizeToAvoidBottomInset;
  final bool safeTop;
  final bool safeBottom;
  final bool showBack;
  final bool applyHorizontalPadding;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    Widget content = AdaptiveContent(
      padding: applyHorizontalPadding ? context.pagePadding : EdgeInsets.zero,
      child: body,
    );
    content = SafeArea(top: safeTop, bottom: safeBottom, child: content);
    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              leading: showBack
                  ? IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const DirectionalArrowIcon(forward: false),
                    )
                  : null,
              actions: actions,
            ),
      body: content,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}
