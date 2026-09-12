import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../models/auth_models.dart';

class AuthBrandMark extends StatelessWidget {
  const AuthBrandMark({this.size = 92, this.showName = true, super.key});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(size * .28),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: .12),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(
              Icons.local_taxi_rounded,
              size: size * .56,
              color: AppColors.primaryDark,
            ),
          ),
          if (showName) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              'يمن درايف',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
            ),
          ],
        ],
      );
}

class AuthIllustration extends StatelessWidget {
  const AuthIllustration({required this.artwork, this.height = 260, super.key});

  final OnboardingArtwork artwork;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) => Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                size: Size(constraints.maxWidth, height),
                painter: _CityArtworkPainter(
                  artwork: artwork,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
              Positioned(
                bottom: height * .15,
                child: Transform.rotate(
                  angle: artwork == OnboardingArtwork.fastPickup ? -.08 : 0,
                  child: Icon(
                    Icons.local_taxi_rounded,
                    size: math.min(112, constraints.maxWidth * .28),
                    color: AppColors.primary,
                    shadows: <Shadow>[
                      Shadow(
                        color: Colors.black.withValues(alpha: .35),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                ),
              ),
              if (artwork == OnboardingArtwork.liveTracking)
                Positioned(
                  top: height * .18,
                  right: constraints.maxWidth * .18,
                  child: const _LocationPulse(),
                ),
            ],
          ),
        ),
      );
}

class _LocationPulse extends StatelessWidget {
  const _LocationPulse();

  @override
  Widget build(BuildContext context) => Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: .18),
          shape: BoxShape.circle,
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
      );
}

class _CityArtworkPainter extends CustomPainter {
  const _CityArtworkPainter({required this.artwork, required this.isDark});

  final OnboardingArtwork artwork;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final muted = Paint()
      ..color = isDark ? const Color(0xFF252730) : const Color(0xFFEDEEF1);
    final primary = Paint()..color = AppColors.primary;
    final ink = Paint()
      ..color = isDark ? const Color(0xFFF8F8F8) : const Color(0xFF202124);

    final sunCenter = Offset(size.width * .73, size.height * .20);
    canvas.drawCircle(sunCenter, size.shortestSide * .06, primary);
    canvas.drawCircle(sunCenter, size.shortestSide * .025, ink);

    final groundY = size.height * .78;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .08, groundY, size.width * .84, 5),
        const Radius.circular(4),
      ),
      muted,
    );

    final buildings = <Rect>[
      Rect.fromLTWH(
        size.width * .14,
        size.height * .34,
        size.width * .12,
        size.height * .44,
      ),
      Rect.fromLTWH(
        size.width * .28,
        size.height * .22,
        size.width * .14,
        size.height * .56,
      ),
      Rect.fromLTWH(
        size.width * .60,
        size.height * .43,
        size.width * .12,
        size.height * .35,
      ),
      Rect.fromLTWH(
        size.width * .74,
        size.height * .31,
        size.width * .13,
        size.height * .47,
      ),
    ];
    for (var index = 0; index < buildings.length; index++) {
      final building = buildings[index];
      canvas.drawRRect(
        RRect.fromRectAndRadius(building, const Radius.circular(4)),
        index.isOdd ? primary : muted,
      );
      final windowPaint = index.isOdd ? ink : primary;
      for (var row = 0; row < 4; row++) {
        for (var column = 0; column < 2; column++) {
          final left = building.left + building.width * (.22 + column * .42);
          final top = building.top + building.height * (.15 + row * .18);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                left,
                top,
                building.width * .16,
                building.height * .07,
              ),
              const Radius.circular(2),
            ),
            windowPaint,
          );
        }
      }
    }

    if (artwork != OnboardingArtwork.cityRide) {
      final route = Paint()
        ..color = primary.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(size.width * .15, size.height * .82)
        ..cubicTo(
          size.width * .30,
          size.height * .60,
          size.width * .58,
          size.height * .92,
          size.width * .84,
          size.height * .68,
        );
      canvas.drawPath(path, route);
    }
  }

  @override
  bool shouldRepaint(covariant _CityArtworkPainter oldDelegate) =>
      oldDelegate.artwork != artwork || oldDelegate.isDark != isDark;
}
