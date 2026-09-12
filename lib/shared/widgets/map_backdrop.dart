import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

class MapBackdrop extends StatelessWidget {
  const MapBackdrop({
    this.child,
    this.showMarker = true,
    this.showRoute = false,
    super.key,
  });

  final Widget? child;
  final bool showMarker;
  final bool showRoute;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CustomPaint(
            painter: _MapPainter(
              isDark: Theme.of(context).brightness == Brightness.dark,
              showRoute: showRoute,
            ),
          ),
          if (showMarker)
            Center(
              child: Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: .17),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.location_on_rounded, color: Colors.black),
                ),
              ),
            ),
          if (child != null) child!,
        ],
      );
}

class _MapPainter extends CustomPainter {
  const _MapPainter({required this.isDark, required this.showRoute});

  final bool isDark;
  final bool showRoute;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..color = isDark ? AppColors.mapLandDark : AppColors.mapLandLight;
    canvas.drawRect(Offset.zero & size, background);

    final road = Paint()
      ..color = isDark ? AppColors.mapRoadDark : AppColors.mapRoadLight
      ..strokeWidth = math.max(7, size.shortestSide * .025)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final thinRoad = Paint()
      ..color = road.color.withValues(alpha: .8)
      ..strokeWidth = math.max(3, size.shortestSide * .012)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final paths = <Path>[
      Path()
        ..moveTo(-20, size.height * .18)
        ..quadraticBezierTo(
          size.width * .38,
          size.height * .33,
          size.width + 30,
          size.height * .08,
        ),
      Path()
        ..moveTo(size.width * .18, -20)
        ..quadraticBezierTo(
          size.width * .30,
          size.height * .48,
          size.width * .05,
          size.height + 20,
        ),
      Path()
        ..moveTo(size.width * .72, -20)
        ..quadraticBezierTo(
          size.width * .55,
          size.height * .52,
          size.width * .92,
          size.height + 20,
        ),
      Path()
        ..moveTo(-20, size.height * .72)
        ..quadraticBezierTo(
          size.width * .54,
          size.height * .55,
          size.width + 20,
          size.height * .80,
        ),
    ];
    for (var i = 0; i < paths.length; i++) {
      canvas.drawPath(paths[i], i.isEven ? road : thinRoad);
    }

    if (showRoute) {
      final route = Paint()
        ..color = AppColors.primary
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(size.width * .18, size.height * .78)
        ..cubicTo(
          size.width * .20,
          size.height * .35,
          size.width * .76,
          size.height * .68,
          size.width * .77,
          size.height * .22,
        );
      canvas.drawPath(path, route);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.showRoute != showRoute;
}
