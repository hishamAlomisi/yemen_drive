import 'dart:math' as math;

import 'package:flutter/material.dart';

abstract final class AppBreakpoints {
  static const double mobile = 600;
  static const double tablet = 1024;
  static const double maxContent = 720;
}

extension ResponsiveContext on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);
  bool get isCompactLayout => screenSize.width < AppBreakpoints.mobile;
  bool get isMediumLayout =>
      screenSize.width >= AppBreakpoints.mobile &&
      screenSize.width < AppBreakpoints.tablet;
  bool get isExpandedLayout => screenSize.width >= AppBreakpoints.tablet;

  double responsiveValue({
    required double phone,
    double? tablet,
    double? wide,
  }) {
    if (isExpandedLayout) return wide ?? tablet ?? phone;
    if (isMediumLayout) return tablet ?? phone;
    return phone;
  }

  EdgeInsets get pagePadding => EdgeInsets.symmetric(
        horizontal: responsiveValue(phone: 16, tablet: 28, wide: 40),
      );
}

class AdaptiveContent extends StatelessWidget {
  const AdaptiveContent({
    required this.child,
    this.maxWidth = AppBreakpoints.maxContent,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(maxWidth, MediaQuery.sizeOf(context).width),
          ),
          child: Padding(padding: padding, child: child),
        ),
      );
}
