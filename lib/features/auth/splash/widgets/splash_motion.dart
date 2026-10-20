import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'splash_logo_outline.dart';

/// All entrances share one finite timeline. The child is built only when its
/// configuration changes; animation frames update transforms and opacity only.
class SplashEntrance extends StatelessWidget {
  const SplashEntrance({
    required this.timeline,
    required this.begin,
    required this.end,
    required this.child,
    this.rise = .18,
    this.scaleFrom = 1,
    super.key,
  });

  final Animation<double> timeline;
  final double begin;
  final double end;
  final double rise;
  final double scaleFrom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final progress = timeline.drive(
      CurveTween(curve: Interval(begin, end, curve: Curves.easeOutCubic)),
    );
    return FadeTransition(
      opacity: progress,
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset(0, rise), end: Offset.zero)
            .animate(progress),
        child: ScaleTransition(
          scale: Tween<double>(begin: scaleFrom, end: 1).animate(progress),
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

enum SplashTraceShape { logo, benefit }

/// A gold line draws the actual logo silhouette or an icon's border per sweep.
/// Metrics are cached per size. Layered thin strokes provide the glow without
/// blur filters, shaders, saveLayer, particles or another animation controller.
class SplashTracePainter extends CustomPainter {
  SplashTracePainter({required this.progress, required this.shape})
      : super(repaint: progress);

  final Animation<double> progress;
  final SplashTraceShape shape;
  Size? _size;
  List<PathMetric> _metrics = const [];
  double _length = 0;

  void _prepare(Size size) {
    if (_size == size) return;
    _size = size;
    final Path path;
    if (shape == SplashTraceShape.logo) {
      // Matches the 744 x 691 asset with BoxFit.contain/bottomCenter.
      final scale = math.min(size.width / 744, size.height / 691);
      final width = 744 * scale;
      final height = 691 * scale;
      path = createSplashLogoOutline()
          .transform(
            Matrix4.diagonal3Values(width, height, 1).storage,
          )
          .shift(Offset((size.width - width) / 2, size.height - height));
    } else {
      path = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            (Offset.zero & size).deflate(.8),
            Radius.circular(size.shortestSide * .28),
          ),
        );
    }
    _metrics = path.computeMetrics().toList(growable: false);
    _length = _metrics.fold(0, (total, metric) => total + metric.length);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    _prepare(size);
    final reveal = Curves.easeInOutCubic.transform((t / .82).clamp(0, 1));
    final opacity =
        (t / .08).clamp(0.0, 1.0) * (1 - ((t - .78) / .22).clamp(0.0, 1.0));
    final head = _length * reveal;
    final line = _segment(0, head);
    final trail = _segment(math.max(0, head - _length * .12), head);
    final thickness = shape == SplashTraceShape.logo
        ? (size.width / 390).clamp(.5, 2.0)
        : (size.width / 35).clamp(.5, 2.0);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      line,
      stroke
        ..color = const Color(0xFFFFD46B).withValues(alpha: opacity * .55)
        ..strokeWidth = thickness,
    );
    for (final (width, alpha) in [(7.0, .09), (3.5, .3), (1.4, .98)]) {
      canvas.drawPath(
        trail,
        stroke
          ..color = const Color(0xFFFFE5A1).withValues(alpha: opacity * alpha)
          ..strokeWidth = width * thickness,
      );
    }
  }

  Path _segment(double start, double end) {
    final path = Path();
    var offset = 0.0;
    for (final metric in _metrics) {
      final from = (start - offset).clamp(0.0, metric.length);
      final to = (end - offset).clamp(0.0, metric.length);
      if (to > from) {
        path.addPath(metric.extractPath(from, to), Offset.zero);
      }
      offset += metric.length;
    }
    return path;
  }

  @override
  bool shouldRepaint(SplashTracePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.shape != shape;
}
