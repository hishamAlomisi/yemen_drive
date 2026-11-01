import 'package:flutter/material.dart';

import '../../models/auth_models.dart';

/// Scalable artwork stays sharp on every phone and loads without a network.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration(
      {required this.artwork, required this.height, super.key});

  final OnboardingArtwork artwork;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _IllustrationPainter(artwork)));
}

class _IllustrationPainter extends CustomPainter {
  const _IllustrationPainter(this.artwork);
  final OnboardingArtwork artwork;

  static const emerald = Color(0xFF087F6B);
  static const navy = Color(0xFF173E54);
  static const gold = Color(0xFFFFC34A);
  static const coral = Color(0xFFF4776B);

  Paint _fill(Color color) => Paint()..color = color;
  Paint _gradient(Rect rect, List<Color> colors) => Paint()
    ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors)
        .createShader(rect);

  void _card(Canvas canvas, Rect rect, double radius, {List<Color>? colors}) {
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawShadow(
        Path()..addRRect(shape), navy.withValues(alpha: .14), 10, false);
    canvas.drawRRect(
        shape, colors == null ? _fill(Colors.white) : _gradient(rect, colors));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / 360).clamp(0.0, size.height / 280);
    canvas.save();
    canvas.translate(
        (size.width - 360 * scale) / 2, (size.height - 280 * scale) / 2);
    canvas.scale(scale);
    final backdrop = Rect.fromLTWH(42, 18, 276, 242);
    canvas.drawOval(
        backdrop,
        _gradient(
            backdrop, [const Color(0xFFE1F5EC), const Color(0xFFEAF4FF)]));
    _sparkle(canvas, const Offset(33, 87), coral);
    _sparkle(canvas, const Offset(315, 210), gold);
    canvas.drawCircle(const Offset(320, 59), 6, _fill(gold));
    canvas.drawCircle(const Offset(46, 216), 4, _fill(emerald));
    switch (artwork) {
      case OnboardingArtwork.cityRide:
        _cityRide(canvas);
      case OnboardingArtwork.fastPickup:
        _pickup(canvas);
      case OnboardingArtwork.liveTracking:
        _tracking(canvas);
    }
    canvas.restore();
  }

  void _sparkle(Canvas canvas, Offset point, Color color) {
    final path = Path()
      ..moveTo(point.dx, point.dy - 8)
      ..quadraticBezierTo(point.dx + 2, point.dy - 2, point.dx + 8, point.dy)
      ..quadraticBezierTo(point.dx + 2, point.dy + 2, point.dx, point.dy + 8)
      ..quadraticBezierTo(point.dx - 2, point.dy + 2, point.dx - 8, point.dy)
      ..quadraticBezierTo(point.dx - 2, point.dy - 2, point.dx, point.dy - 8);
    canvas.drawPath(path, _fill(color));
  }

  void _cityRide(Canvas canvas) {
    for (final (x, y, width, height, color) in [
      (60.0, 93.0, 43.0, 116.0, const Color(0xFF9ACEC7)),
      (107.0, 64.0, 46.0, 145.0, const Color(0xFF70ACC0)),
      (214.0, 86.0, 38.0, 123.0, const Color(0xFFFFBC9A)),
      (258.0, 116.0, 40.0, 93.0, const Color(0xFFB8D9C8)),
    ]) {
      final rect = Rect.fromLTWH(x, y, width, height);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(9)),
          _gradient(rect, [color, Color.lerp(color, Colors.white, .35)!]));
      for (var row = 0; row < 4; row++) {
        for (var col = 0; col < 2; col++) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(x + 9 + col * 17, y + 17 + row * 22, 7, 11),
                  const Radius.circular(2)),
              _fill(Colors.white.withValues(alpha: .68)));
        }
      }
    }
    canvas.drawOval(const Rect.fromLTWH(63, 229, 238, 18),
        _fill(navy.withValues(alpha: .10)));
    _car(canvas, const Offset(71, 128), 1);
    _card(canvas, const Rect.fromLTWH(230, 30, 69, 72), 20);
    _shield(canvas, const Offset(264, 62), 22);
    _sparkle(canvas, const Offset(177, 45), gold);
  }

  void _pickup(Canvas canvas) {
    canvas.save();
    canvas.translate(180, 137);
    canvas.rotate(-.06);
    canvas.translate(-180, -137);
    _card(canvas, const Rect.fromLTWH(48, 58, 262, 172), 24);
    final mapBounds = RRect.fromRectAndRadius(
        const Rect.fromLTWH(58, 68, 242, 152), const Radius.circular(18));
    canvas.save();
    canvas.clipRRect(mapBounds);
    canvas.drawRRect(mapBounds, _fill(const Color(0xFFEAF5F0)));
    for (var x = 75.0; x < 300; x += 62) {
      canvas.drawLine(
          Offset(x, 68),
          Offset(x - 30, 220),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 14);
    }
    for (var y = 100.0; y < 220; y += 60) {
      canvas.drawLine(
          Offset(58, y),
          Offset(300, y + 22),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 14);
    }
    final route = Path()
      ..moveTo(98, 187)
      ..lineTo(153, 187)
      ..quadraticBezierTo(170, 187, 170, 170)
      ..lineTo(170, 134)
      ..quadraticBezierTo(170, 119, 187, 119)
      ..lineTo(260, 119);
    canvas.drawPath(
        route,
        Paint()
          ..color = emerald
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(const Offset(98, 187), 9, _fill(emerald));
    canvas.drawCircle(const Offset(98, 187), 4, _fill(Colors.white));
    canvas.restore();
    _pin(canvas, const Offset(260, 92), coral, 22);
    canvas.restore();
    _car(canvas, const Offset(40, 166), .62);
    _card(canvas, const Rect.fromLTWH(65, 29, 75, 55), 18);
    _clock(canvas, const Offset(102, 55), 17);
    _sparkle(canvas, const Offset(280, 38), gold);
  }

  void _tracking(Canvas canvas) {
    _card(canvas, const Rect.fromLTWH(104, 28, 143, 230), 28,
        colors: [navy, const Color(0xFF0D283B)]);
    _card(canvas, const Rect.fromLTWH(114, 41, 123, 201), 20);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(150, 47, 50, 6), const Radius.circular(4)),
        _fill(navy));
    final mapBounds = RRect.fromRectAndRadius(
        const Rect.fromLTWH(120, 65, 111, 128), const Radius.circular(12));
    canvas.save();
    canvas.clipRRect(mapBounds);
    canvas.drawRRect(mapBounds, _fill(const Color(0xFFE9F6F0)));
    for (var y = 86.0; y < 195; y += 39) {
      canvas.drawLine(
          Offset(120, y),
          Offset(231, y + 11),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 10);
    }
    canvas.drawLine(
        const Offset(159, 65),
        const Offset(145, 194),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 12);
    final route = Path()
      ..moveTo(144, 164)
      ..lineTo(191, 164)
      ..lineTo(191, 97);
    canvas.drawPath(
        route,
        Paint()
          ..color = emerald
          ..strokeWidth = 6
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(const Offset(144, 164), 7, _fill(emerald));
    canvas.restore();
    _pin(canvas, const Offset(191, 97), coral, 15);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(128, 207, 94, 23), const Radius.circular(10)),
        _gradient(const Rect.fromLTWH(128, 207, 94, 23),
            [emerald, const Color(0xFF40B69B)]));
    _check(canvas, const Offset(173, 218), Colors.white, 7);
    _card(canvas, const Rect.fromLTWH(40, 94, 82, 66), 19);
    _shield(canvas, const Offset(80, 126), 21);
    _car(canvas, const Offset(184, 164), .66);
    _sparkle(canvas, const Offset(281, 92), gold);
  }

  void _car(Canvas canvas, Offset offset, double scale) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    final body = Path()
      ..moveTo(12, 57)
      ..quadraticBezierTo(15, 42, 42, 39)
      ..lineTo(60, 13)
      ..quadraticBezierTo(68, 5, 87, 5)
      ..lineTo(133, 5)
      ..quadraticBezierTo(147, 8, 159, 37)
      ..lineTo(184, 44)
      ..quadraticBezierTo(204, 51, 203, 73)
      ..lineTo(201, 88)
      ..quadraticBezierTo(193, 96, 177, 94)
      ..lineTo(27, 94)
      ..quadraticBezierTo(8, 94, 8, 77)
      ..close();
    canvas.drawShadow(body, navy.withValues(alpha: .28), 8, false);
    canvas.drawPath(
        body,
        _gradient(const Rect.fromLTWH(8, 5, 198, 90),
            [const Color(0xFFFFDE7E), gold, const Color(0xFFF2A623)]));
    final window = Path()
      ..moveTo(57, 39)
      ..lineTo(70, 18)
      ..quadraticBezierTo(73, 14, 85, 14)
      ..lineTo(131, 14)
      ..quadraticBezierTo(137, 17, 147, 39)
      ..close();
    canvas.drawPath(
        window,
        _gradient(const Rect.fromLTWH(57, 14, 91, 26),
            [const Color(0xFFBCE6EE), const Color(0xFF538DA5)]));
    canvas.drawLine(
        const Offset(104, 14),
        const Offset(104, 40),
        Paint()
          ..color = navy
          ..strokeWidth = 4);
    canvas.drawLine(
        const Offset(40, 55),
        const Offset(169, 55),
        Paint()
          ..color = Colors.white.withValues(alpha: .45)
          ..strokeWidth = 3);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(76, -3, 39, 11), const Radius.circular(4)),
        _fill(navy));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(181, 58, 18, 10), const Radius.circular(4)),
        _fill(const Color(0xFFFFF8DB)));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(11, 60, 10, 11), const Radius.circular(3)),
        _fill(coral));
    for (final x in [48.0, 163.0]) {
      canvas.drawCircle(Offset(x, 91), 19, _fill(navy));
      canvas.drawCircle(
          Offset(x, 91),
          11,
          _gradient(Rect.fromCircle(center: Offset(x, 91), radius: 11),
              [Colors.white, const Color(0xFFA0BCC6)]));
      canvas.drawCircle(Offset(x, 91), 5, _fill(navy));
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(116, 48, 13, 4), const Radius.circular(2)),
        _fill(navy.withValues(alpha: .55)));
    canvas.restore();
  }

  void _shield(Canvas canvas, Offset center, double radius) {
    final shape = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * .8, center.dy - radius * .6)
      ..lineTo(center.dx + radius * .7, center.dy + radius * .35)
      ..quadraticBezierTo(center.dx + radius * .45, center.dy + radius * .8,
          center.dx, center.dy + radius)
      ..quadraticBezierTo(center.dx - radius * .45, center.dy + radius * .8,
          center.dx - radius * .7, center.dy + radius * .35)
      ..lineTo(center.dx - radius * .8, center.dy - radius * .6)
      ..close();
    canvas.drawPath(
        shape,
        _gradient(Rect.fromCircle(center: center, radius: radius),
            [const Color(0xFF45C2A0), emerald]));
    _check(canvas, center, Colors.white, radius * .45);
  }

  void _check(Canvas canvas, Offset center, Color color, double radius) {
    canvas.drawPath(
        Path()
          ..moveTo(center.dx - radius, center.dy)
          ..lineTo(center.dx - radius * .2, center.dy + radius * .7)
          ..lineTo(center.dx + radius, center.dy - radius * .7),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  void _pin(Canvas canvas, Offset center, Color color, double radius) {
    final path = Path()
      ..moveTo(center.dx, center.dy + radius * 1.4)
      ..cubicTo(center.dx - radius * 1.7, center.dy, center.dx - radius,
          center.dy - radius, center.dx, center.dy - radius)
      ..cubicTo(
          center.dx + radius,
          center.dy - radius,
          center.dx + radius * 1.7,
          center.dy,
          center.dx,
          center.dy + radius * 1.4);
    canvas.drawShadow(path, color.withValues(alpha: .3), 5, false);
    canvas.drawPath(
        path,
        _gradient(Rect.fromCircle(center: center, radius: radius),
            [Color.lerp(color, Colors.white, .22)!, color]));
    canvas.drawCircle(center, radius * .38, _fill(Colors.white));
  }

  void _clock(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(center, radius, _fill(const Color(0xFFFFEBC1)));
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy - 9)
          ..lineTo(center.dx, center.dy)
          ..lineTo(center.dx + 7, center.dy + 4),
        Paint()
          ..color = navy
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_IllustrationPainter oldDelegate) =>
      oldDelegate.artwork != artwork;
}
