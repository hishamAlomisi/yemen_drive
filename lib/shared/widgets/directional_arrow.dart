import 'package:flutter/material.dart';

class DirectionalArrowIcon extends StatelessWidget {
  const DirectionalArrowIcon({required this.forward, this.size, super.key});

  final bool forward;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final icon = forward
        ? (rtl ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded)
        : (rtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Icon(icon, size: size),
    );
  }
}
