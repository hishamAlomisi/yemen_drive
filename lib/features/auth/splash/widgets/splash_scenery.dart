import 'dart:math' as math;

import 'package:flutter/material.dart';

const _gold = Color(0xFFFFD46B);

/// Vector scenery inspired by the reference: Sana'a facades, mountains,
/// route lines and light. It stays independent of the rider logo bitmap.
class SplashSceneryPainter extends CustomPainter {
  const SplashSceneryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 390, size.height / 693);
    const bounds = Rect.fromLTWH(0, 0, 390, 693);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF003A2E), Color(0xFF002B23), Color(0xFF00392D)],
          stops: [0, .7, 1],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(.1, -.44),
          radius: .78,
          colors: [Color(0xFF17634C), Color(0x000F5946)],
        ).createShader(bounds),
    );
    _routeGrid(canvas);
    _mountains(canvas);
    _city(canvas);
    _road(canvas);
    _foregroundRays(canvas);
    // Mist merges the illustrated skyline into the darker text area.
    canvas.drawRect(
      const Rect.fromLTWH(0, 250, 390, 443),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x0000261E),
            Color(0x2200261E),
            Color(0xB300261E),
            Color(0x1800261E),
          ],
          stops: [0, .28, .6, 1],
        ).createShader(const Rect.fromLTWH(0, 250, 390, 443)),
    );
    canvas.restore();
  }

  void _routeGrid(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF0C5745).withValues(alpha: .45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final routes = <Path>[
      Path()
        ..moveTo(-30, 2)
        ..cubicTo(125, 33, 320, 84, 419, 172),
      Path()
        ..moveTo(-40, 110)
        ..cubicTo(125, 48, 286, 72, 410, 104),
      Path()
        ..moveTo(-20, 140)
        ..cubicTo(144, 96, 281, 100, 421, 159),
      Path()
        ..moveTo(-26, 42)
        ..cubicTo(61, 56, 149, 105, 170, 179),
      Path()
        ..moveTo(42, 26)
        ..cubicTo(121, 42, 178, 102, 210, 173),
      Path()
        ..moveTo(-22, 77)
        ..cubicTo(33, 121, 40, 141, 47, 186),
      Path()
        ..moveTo(-12, 626)
        ..cubicTo(104, 666, 265, 686, 410, 693),
      Path()
        ..moveTo(-26, 660)
        ..cubicTo(114, 653, 284, 724, 410, 634),
      Path()
        ..moveTo(121, 696)
        ..cubicTo(213, 675, 317, 650, 417, 633),
      Path()
        ..moveTo(256, 667)
        ..cubicTo(332, 617, 373, 562, 409, 509),
      Path()
        ..moveTo(290, 590)
        ..cubicTo(315, 555, 345, 515, 418, 481),
      Path()
        ..moveTo(270, 553)
        ..cubicTo(311, 571, 352, 606, 406, 586),
      Path()
        ..moveTo(316, 510)
        ..cubicTo(332, 553, 373, 561, 413, 579),
      Path()
        ..moveTo(347, 455)
        ..cubicTo(351, 489, 378, 507, 410, 523),
    ];
    for (final route in routes) {
      canvas.drawPath(route, paint);
    }
  }

  void _mountains(Canvas canvas) {
    const ridges = <List<Offset>>[
      [
        Offset(0, 170),
        Offset(80, 155),
        Offset(137, 131),
        Offset(170, 124),
        Offset(188, 132),
        Offset(215, 99),
        Offset(230, 104),
        Offset(247, 87),
        Offset(262, 93),
        Offset(281, 109),
        Offset(311, 117),
        Offset(340, 96),
        Offset(360, 91),
        Offset(380, 106),
        Offset(390, 112),
      ],
      [
        Offset(0, 194),
        Offset(62, 175),
        Offset(124, 176),
        Offset(195, 142),
        Offset(227, 131),
        Offset(263, 135),
        Offset(286, 113),
        Offset(301, 120),
        Offset(324, 105),
        Offset(344, 98),
        Offset(361, 90),
        Offset(373, 115),
        Offset(390, 123),
      ],
    ];
    for (var layer = 0; layer < ridges.length; layer++) {
      final ridge = ridges[layer];
      final path = Path()..moveTo(ridge.first.dx, ridge.first.dy);
      for (var i = 1; i < ridge.length; i++) {
        final previous = ridge[i - 1];
        final next = ridge[i];
        path
          ..lineTo(
            (previous.dx + next.dx) / 2,
            (previous.dy + next.dy) / 2 - (i.isEven ? 3 : -2),
          )
          ..lineTo(next.dx, next.dy);
      }
      path
        ..lineTo(390, 268)
        ..lineTo(0, 268)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color =
              layer == 0 ? const Color(0xFF074A3B) : const Color(0xFF00362E),
      );
      final rock = Paint()
        ..color = const Color(0xFF3B6650).withValues(alpha: .13)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8;
      for (var i = 6; i < ridge.length - 1; i++) {
        final peak = ridge[i];
        canvas.drawPath(
          Path()
            ..moveTo(peak.dx, peak.dy + 3)
            ..lineTo(peak.dx - 6, peak.dy + 22)
            ..lineTo(peak.dx + 5, peak.dy + 40)
            ..lineTo(peak.dx + 17, peak.dy + 47),
          rock,
        );
      }
    }
  }

  void _city(Canvas canvas) {
    final random = math.Random(37);
    // Small, distant facades add depth behind the larger edge buildings.
    for (var i = 0; i < 32; i++) {
      final x = i * 13.0 - 8;
      final height = 21 + random.nextDouble() * 30;
      _building(
        canvas,
        x,
        242 + random.nextDouble() * 18,
        12,
        height,
        random,
        distant: true,
      );
    }
    const houses = <(double, double, double, double)>[
      (-9, 270, 25, 70),
      (15, 271, 25, 91),
      (37, 275, 22, 69),
      (5, 213, 18, 46),
      (22, 216, 29, 51),
      (52, 260, 22, 54),
      (268, 252, 19, 55),
      (287, 257, 23, 69),
      (310, 252, 22, 73),
      (333, 249, 38, 105),
      (372, 247, 30, 79),
      (315, 240, 16, 41),
      (-10, 281, 26, 43),
      (22, 288, 27, 38),
      (359, 282, 38, 63),
    ];
    for (final (x, bottom, width, height) in houses) {
      _building(canvas, x, bottom, width, height, random);
    }
    final foliage = Paint()..color = const Color(0xFF063B2D);
    for (var i = 0; i < 98; i++) {
      final x = random.nextDouble() * 390;
      final y = 268 + random.nextDouble() * 25;
      canvas.drawCircle(Offset(x, y), 2 + random.nextDouble() * 5, foliage);
    }
  }

  void _building(
    Canvas canvas,
    double x,
    double bottom,
    double width,
    double height,
    math.Random random, {
    bool distant = false,
  }) {
    final top = bottom - height;
    final rect = Rect.fromLTWH(x, top, width, height);
    final facade = Paint()
      ..shader = LinearGradient(
        colors: distant
            ? const [Color(0xFF155243), Color(0xFF083A2E)]
            : const [Color(0xFF164C39), Color(0xFF06362B)],
      ).createShader(rect);
    canvas.drawRect(rect, facade);
    final trim = Paint()
      ..color = Color(distant ? 0xFF467557 : 0xFF7B8050)
          .withValues(alpha: distant ? .2 : .48)
      ..strokeWidth = .65
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, trim);
    canvas.drawLine(
      Offset(x - 1, top + 4),
      Offset(x + width + 1, top + 4),
      trim,
    );
    for (var i = 0; i < 4; i++) {
      final dx = x + width * i / 3;
      canvas.drawLine(Offset(dx, top - 3), Offset(dx, top), trim);
    }
    final columns = math.max(2, (width / 8).floor());
    final floors = math.max(2, (height / 15).floor());
    final cellWidth = width / columns;
    final cellHeight = (height - 6) / floors;
    for (var row = 0; row < floors; row++) {
      final y = top + 7 + row * cellHeight;
      canvas.drawLine(
        Offset(x, y + cellHeight - 3),
        Offset(x + width, y + cellHeight - 3),
        trim,
      );
      for (var col = 0; col < columns; col++) {
        final cx = x + cellWidth * (col + .5);
        final windowWidth = cellWidth * .42;
        final windowHeight = cellHeight * .57;
        final window = Path()
          ..moveTo(cx - windowWidth / 2, y + windowHeight)
          ..lineTo(cx - windowWidth / 2, y + windowWidth / 2)
          ..quadraticBezierTo(cx - windowWidth / 2, y + 1, cx, y)
          ..quadraticBezierTo(
            cx + windowWidth / 2,
            y + 1,
            cx + windowWidth / 2,
            y + windowWidth / 2,
          )
          ..lineTo(cx + windowWidth / 2, y + windowHeight)
          ..close();
        final lit = random.nextDouble() > (distant ? .7 : .35);
        if (lit) {
          canvas.drawPath(
            window,
            Paint()
              ..color =
                  const Color(0xFFFFCC60).withValues(alpha: distant ? .2 : .5)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
          );
        }
        canvas.drawPath(
          window,
          Paint()
            ..color = lit
                ? const Color(0xFFE2BB59).withValues(alpha: distant ? .45 : .85)
                : const Color(0xFF002C23),
        );
        canvas.drawPath(window, trim);
        canvas.drawLine(Offset(cx, y + 1), Offset(cx, y + windowHeight), trim);
        if (!distant) {
          canvas.drawCircle(Offset(cx, y - 2), .7, trim);
          canvas.drawLine(
            Offset(cx - 2, y + windowHeight + 2),
            Offset(cx + 2, y + windowHeight + 2),
            trim,
          );
        }
      }
    }
  }

  void _road(Canvas canvas) {
    final route = Path()
      ..moveTo(-30, 353)
      ..cubicTo(48, 302, 129, 288, 206, 284)
      ..cubicTo(320, 279, 401, 263, 329, 245)
      ..cubicTo(310, 240, 282, 234, 266, 230);
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFF0A5140)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 32,
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFFFFDD75).withValues(alpha: .24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawPath(
      route,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFDA76), Color(0xFFFFE391), Color(0xFFB8BA5C)],
        ).createShader(const Rect.fromLTWH(0, 230, 390, 110))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-24, 375)
        ..cubicTo(76, 305, 165, 304, 241, 286),
      Paint()
        ..color = const Color(0xFF267653).withValues(alpha: .4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _foregroundRays(Canvas canvas) {
    for (var i = 0; i < 7; i++) {
      final ray = Path()
        ..moveTo(107 + i * 9.0, 348)
        ..lineTo(-110 + i * 64.0, 600)
        ..lineTo(-77 + i * 65.0, 600)
        ..close();
      canvas.drawPath(
        ray,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x331E7151), Color(0x000C5745)],
          ).createShader(const Rect.fromLTWH(0, 345, 390, 255)),
      );
    }
  }

  @override
  bool shouldRepaint(SplashSceneryPainter oldDelegate) => false;
}

enum SplashBenefitIcon { request, trusted, safety }

class SplashBenefitPainter extends CustomPainter {
  const SplashBenefitPainter(this.icon);

  final SplashBenefitIcon icon;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = _gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (icon) {
      case SplashBenefitIcon.request:
        canvas.drawPath(
          Path()
            ..moveTo(12, 23)
            ..cubicTo(9, 18, 3, 13, 3, 9)
            ..cubicTo(3, -2, 21, -2, 21, 9)
            ..cubicTo(21, 13, 15, 18, 12, 23)
            ..close(),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 8), 3, stroke);
      case SplashBenefitIcon.trusted:
        final fill = Paint()..color = _gold;
        canvas.drawCircle(const Offset(12, 6), 3.3, fill);
        canvas.drawCircle(const Offset(4, 8), 2.5, fill);
        canvas.drawCircle(const Offset(20, 8), 2.5, fill);
        canvas.drawPath(
          Path()
            ..moveTo(6, 22)
            ..lineTo(6, 17)
            ..cubicTo(6, 10, 18, 10, 18, 17)
            ..lineTo(18, 22)
            ..moveTo(1, 20)
            ..lineTo(1, 16)
            ..quadraticBezierTo(1, 12, 5, 12)
            ..moveTo(23, 20)
            ..lineTo(23, 16)
            ..quadraticBezierTo(23, 12, 19, 12),
          stroke,
        );
      case SplashBenefitIcon.safety:
        canvas.drawPath(
          Path()
            ..moveTo(12, 1)
            ..quadraticBezierTo(17, 4, 21, 4)
            ..lineTo(21, 11)
            ..quadraticBezierTo(21, 18, 12, 23)
            ..quadraticBezierTo(3, 18, 3, 11)
            ..lineTo(3, 4)
            ..quadraticBezierTo(7, 4, 12, 1)
            ..close(),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(8, 12)
            ..lineTo(11, 15)
            ..lineTo(17, 9),
          stroke,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SplashBenefitPainter oldDelegate) =>
      oldDelegate.icon != icon;
}

class SplashRouteMarkPainter extends CustomPainter {
  const SplashRouteMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = _gold
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(12, 22)
        ..lineTo(12, 14)
        ..quadraticBezierTo(19, 10, 19, 6)
        ..lineTo(19, 2)
        ..moveTo(12, 14)
        ..quadraticBezierTo(5, 10, 5, 6)
        ..lineTo(5, 2),
      stroke,
    );
    final fill = Paint()..color = _gold;
    for (final x in [5.0, 19.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x - 4, 5)
          ..lineTo(x + 4, 5)
          ..close(),
        fill,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(5, 8)
        ..lineTo(3, 10)
        ..lineTo(5, 12)
        ..lineTo(7, 10)
        ..close(),
      fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SplashRouteMarkPainter oldDelegate) => false;
}
