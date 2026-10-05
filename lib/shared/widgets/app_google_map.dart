import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme/app_map_styles.dart';
import '../../core/config/app_environment.dart';
import 'map_backdrop.dart';

class AppGoogleMap extends StatefulWidget {
  const AppGoogleMap({
    this.width,
    this.height,
    this.initialTarget = const LatLng(15.3694, 44.1910),
    this.initialZoom = 14,
    this.followTarget,
    this.focusTarget,
    this.focusTargetZoom = 15.5,
    this.focusBounds,
    this.focusBoundsPadding = 72,
    this.mapPadding = EdgeInsets.zero,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.circles = const <Circle>{},
    this.polygons = const <Polygon>{},
    this.radarOverlay,
    this.myLocationEnabled = false,
    this.zoomControlsEnabled = false,
    this.compassEnabled = true,
    this.mapType = MapType.normal,
    this.useModernMapStyle = false,
    this.onMapCreated,
    this.onCameraMove,
    this.onCameraIdle,
    this.onTap,
    this.lightStyle,
    this.darkStyle,
    this.showDemoMarker = true,
    this.showDemoRoute = false,
    super.key,
  });

  final double? width;
  final double? height;
  final LatLng initialTarget;
  final double initialZoom;
  final LatLng? followTarget;
  final LatLng? focusTarget;
  final double focusTargetZoom;

  /// Optional bounds used to frame a selected trip route after the native map
  /// has a real size. This is intentionally separate from [followTarget]:
  /// tracking may follow a moving driver after the initial route focus.
  final LatLngBounds? focusBounds;
  final double focusBoundsPadding;
  final EdgeInsets mapPadding;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;
  final Set<Polygon> polygons;
  final MapRadarOverlay? radarOverlay;
  final bool myLocationEnabled;
  final bool zoomControlsEnabled;
  final bool compassEnabled;
  final MapType mapType;
  final bool useModernMapStyle;
  final MapCreatedCallback? onMapCreated;
  final CameraPositionCallback? onCameraMove;
  final VoidCallback? onCameraIdle;
  final ArgumentCallback<LatLng>? onTap;
  final String? lightStyle;
  final String? darkStyle;
  final bool showDemoMarker;
  final bool showDemoRoute;

  @override
  State<AppGoogleMap> createState() => _AppGoogleMapState();
}

/// Configuration for a lightweight, Flutter-painted sweep over a map.
///
/// Unlike map polygons, its animation never sends per-frame updates to the
/// native Google Maps view.
@immutable
class MapRadarOverlay {
  const MapRadarOverlay({
    required this.center,
    required this.radiusMeters,
    required this.color,
    this.cycleDuration = const Duration(milliseconds: 3500),
  });

  final LatLng center;
  final double radiusMeters;
  final Color color;
  final Duration cycleDuration;
}

@immutable
class _RadarProjection {
  const _RadarProjection({required this.center, required this.radius});

  final Offset center;
  final double radius;
}

class _AppGoogleMapState extends State<AppGoogleMap> {
  bool _isLoading = true;
  GoogleMapController? _controller;
  LatLngBounds? _lastFocusedBounds;
  LatLng? _lastFocusedTarget;
  int _cameraRevision = 0;
  final ValueNotifier<_RadarProjection?> _radarProjection =
      ValueNotifier<_RadarProjection?>(null);

  @override
  void didUpdateWidget(covariant AppGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameRadarOverlay(oldWidget.radarOverlay, widget.radarOverlay)) {
      _radarProjection.value = null;
      if (widget.radarOverlay != null && _controller != null) {
        unawaited(_refreshRadarProjection());
      }
    }
    final target = widget.followTarget;
    if (target != null && target != oldWidget.followTarget) {
      unawaited(_animateTo(target));
    }
    if (widget.focusTarget != oldWidget.focusTarget ||
        widget.focusTargetZoom != oldWidget.focusTargetZoom) {
      if (widget.focusTarget == null) {
        _lastFocusedTarget = null;
      } else {
        unawaited(_focusTarget());
      }
    }
    if (!_sameBounds(widget.focusBounds, oldWidget.focusBounds)) {
      if (widget.focusTarget == null) {
        unawaited(_focusBounds());
      } else {
        _lastFocusedBounds = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The backdrop is an explicit demo-mode fallback only. Development builds
    // with a configured Android Maps key must exercise the real native map.
    final useDevelopmentBackdrop = !kIsWeb && AppEnvironment.useDemoData;
    if (useDevelopmentBackdrop) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.onTap == null
                ? null
                : (details) => widget.onTap!(
                      _developmentTargetForTap(
                        details.localPosition,
                        constraints.biggest,
                      ),
                    ),
            child: MapBackdrop(
              showMarker: widget.showDemoMarker,
              showRoute: widget.showDemoRoute,
            ),
          ),
        ),
      );
    }
    // Android and iOS receive the key through their native configuration.
    // Web needs its JavaScript API key during web bootstrap.
    if (kIsWeb && AppEnvironment.googleMapsApiKey.isEmpty) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: MapBackdrop(
          showMarker: widget.showDemoMarker,
          showRoute: widget.showDemoRoute,
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mapStyle = isDark ? widget.darkStyle : widget.lightStyle;
    final resolvedMapStyle = mapStyle ??
        (widget.useModernMapStyle
            ? isDark
                ? AppMapStyles.modernDark
                : AppMapStyles.modernLight
            : null);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GoogleMap(
            style: resolvedMapStyle,
            padding: widget.mapPadding,
            mapType: widget.mapType,
            initialCameraPosition: CameraPosition(
              target: widget.initialTarget,
              zoom: widget.initialZoom,
            ),
            markers: widget.markers,
            polylines: widget.polylines,
            circles: widget.circles,
            polygons: widget.polygons,
            myLocationEnabled: widget.myLocationEnabled,
            myLocationButtonEnabled: widget.myLocationEnabled,
            zoomControlsEnabled: widget.zoomControlsEnabled,
            compassEnabled: widget.compassEnabled,
            onMapCreated: (controller) {
              _controller = controller;
              _lastFocusedBounds = null;
              _lastFocusedTarget = null;
              widget.onMapCreated?.call(controller);
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!mounted) return;
                if (widget.focusTarget != null) {
                  await _focusTarget();
                } else {
                  await _focusBounds();
                }
                if (widget.radarOverlay != null) {
                  await _refreshRadarProjection();
                }
              });
              if (mounted) setState(() => _isLoading = false);
            },
            onCameraMove: _handleCameraMove,
            onCameraIdle: _handleCameraIdle,
            onTap: widget.onTap,
          ),
          if (widget.radarOverlay != null)
            ValueListenableBuilder<_RadarProjection?>(
              valueListenable: _radarProjection,
              builder: (context, projection, child) {
                final radar = widget.radarOverlay;
                if (projection == null || radar == null) {
                  return const SizedBox.shrink();
                }
                const paintPadding = 2.0;
                final paintDiameter = projection.radius * 2 + paintPadding * 2;
                return Positioned(
                  left: projection.center.dx - projection.radius - paintPadding,
                  top: projection.center.dy - projection.radius - paintPadding,
                  width: paintDiameter,
                  height: paintDiameter,
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: _RadarSweepAnimation(
                        center: Offset(
                          projection.radius + paintPadding,
                          projection.radius + paintPadding,
                        ),
                        radius: projection.radius,
                        color: radar.color,
                        cycleDuration: radar.cycleDuration,
                        animate: !MediaQuery.disableAnimationsOf(context),
                      ),
                    ),
                  ),
                );
              },
            ),
          if (_isLoading)
            IgnorePointer(
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor.withValues(
                      alpha: .82,
                    ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 10),
                      Text('map_loading'.tr),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleCameraMove(CameraPosition position) {
    _cameraRevision++;
    if (widget.radarOverlay != null && _radarProjection.value != null) {
      _radarProjection.value = null;
    }
    widget.onCameraMove?.call(position);
  }

  void _handleCameraIdle() {
    if (widget.radarOverlay != null) {
      unawaited(_refreshRadarProjection());
    }
    widget.onCameraIdle?.call();
  }

  Future<void> _refreshRadarProjection() async {
    final controller = _controller;
    final radar = widget.radarOverlay;
    if (!mounted || controller == null || radar == null) return;
    final cameraRevision = _cameraRevision;

    try {
      final edge = _destinationPoint(radar.center, radar.radiusMeters, 90);
      final coordinates =
          await Future.wait<ScreenCoordinate>(<Future<ScreenCoordinate>>[
        controller.getScreenCoordinate(radar.center),
        controller.getScreenCoordinate(edge),
      ]);
      if (!mounted ||
          cameraRevision != _cameraRevision ||
          !_sameRadarOverlay(widget.radarOverlay, radar)) {
        return;
      }

      // Google Maps reports native screen pixels; Flutter's overlay uses
      // logical pixels.
      final pixelRatio = View.of(context).devicePixelRatio;
      final center = coordinates[0];
      final edgeCoordinate = coordinates[1];
      final radius = math.sqrt(
            math.pow(edgeCoordinate.x - center.x, 2) +
                math.pow(edgeCoordinate.y - center.y, 2),
          ) /
          pixelRatio;
      if (radius <= 0) return;
      _radarProjection.value = _RadarProjection(
        center: Offset(center.x / pixelRatio, center.y / pixelRatio),
        radius: radius,
      );
    } catch (_) {
      // Projection can fail briefly while the native map is being laid out.
      // The next camera-idle event will try again.
    }
  }

  LatLng _destinationPoint(
    LatLng origin,
    double distanceMeters,
    double bearingDegrees,
  ) {
    const earthRadiusMeters = 6371000.0;
    final latitude = origin.latitude * math.pi / 180;
    final longitude = origin.longitude * math.pi / 180;
    final bearing = bearingDegrees * math.pi / 180;
    final angularDistance = distanceMeters / earthRadiusMeters;
    final destinationLatitude = math.asin(
      math.sin(latitude) * math.cos(angularDistance) +
          math.cos(latitude) * math.sin(angularDistance) * math.cos(bearing),
    );
    final destinationLongitude = longitude +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(latitude),
          math.cos(angularDistance) -
              math.sin(latitude) * math.sin(destinationLatitude),
        );
    return LatLng(
      destinationLatitude * 180 / math.pi,
      destinationLongitude * 180 / math.pi,
    );
  }

  bool _sameRadarOverlay(MapRadarOverlay? first, MapRadarOverlay? second) {
    if (identical(first, second)) return true;
    if (first == null || second == null) return false;
    return first.center == second.center &&
        first.radiusMeters == second.radiusMeters &&
        first.color == second.color &&
        first.cycleDuration == second.cycleDuration;
  }

  Future<void> _focusBounds() async {
    if (!mounted) return;
    final controller = _controller;
    final bounds = widget.focusBounds;
    if (controller == null ||
        bounds == null ||
        _sameBounds(bounds, _lastFocusedBounds)) {
      return;
    }
    _lastFocusedBounds = bounds;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, widget.focusBoundsPadding),
      );
    } catch (_) {
      // Native maps can reject a bounds update during their first layout
      // frame. The next widget update or an explicit recenter will retry it.
      _lastFocusedBounds = null;
    }
  }

  Future<void> _focusTarget() async {
    if (!mounted) return;
    final controller = _controller;
    final target = widget.focusTarget;
    if (controller == null ||
        target == null ||
        (target == _lastFocusedTarget && _lastFocusedBounds == null)) {
      return;
    }
    _lastFocusedTarget = target;
    _lastFocusedBounds = null;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(target, widget.focusTargetZoom),
      );
    } catch (_) {
      _lastFocusedTarget = null;
    }
  }

  Future<void> _animateTo(LatLng target) async {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.animateCamera(CameraUpdate.newLatLng(target));
    } catch (_) {
      // The native map can be recreated while a tracking update is in flight.
      // It is safe to skip this one update and use the next driver location.
    }
  }

  bool _sameBounds(LatLngBounds? first, LatLngBounds? second) {
    if (identical(first, second)) return true;
    if (first == null || second == null) return false;
    return first.southwest.latitude == second.southwest.latitude &&
        first.southwest.longitude == second.southwest.longitude &&
        first.northeast.latitude == second.northeast.latitude &&
        first.northeast.longitude == second.northeast.longitude;
  }

  LatLng _developmentTargetForTap(Offset position, Size size) {
    final safeWidth = size.width <= 0 ? 1 : size.width;
    final safeHeight = size.height <= 0 ? 1 : size.height;
    // A small bounded offset is sufficient to make pickup/destination
    // selection testable while clearly remaining a development simulation.
    final latitude =
        widget.initialTarget.latitude + ((.5 - position.dy / safeHeight) * .02);
    final longitude =
        widget.initialTarget.longitude + ((position.dx / safeWidth - .5) * .02);
    return LatLng(latitude, longitude);
  }

  @override
  void dispose() {
    _radarProjection.dispose();
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }
}

class _RadarSweepAnimation extends StatefulWidget {
  const _RadarSweepAnimation({
    required this.center,
    required this.radius,
    required this.color,
    required this.cycleDuration,
    required this.animate,
  });

  final Offset center;
  final double radius;
  final Color color;
  final Duration cycleDuration;
  final bool animate;

  @override
  State<_RadarSweepAnimation> createState() => _RadarSweepAnimationState();
}

class _RadarSweepAnimationState extends State<_RadarSweepAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final _FrameLimitedRepaint _repaint;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.cycleDuration);
    _repaint = _FrameLimitedRepaint(_controller);
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RadarSweepAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cycleDuration != widget.cycleDuration) {
      _controller.duration = widget.cycleDuration;
    }
    if (oldWidget.animate != widget.animate) {
      if (widget.animate) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _RadarSweepPainter(
          center: widget.center,
          radius: widget.radius,
          color: widget.color,
          animation: _controller,
          repaint: _repaint,
        ),
      );

  @override
  void dispose() {
    _repaint.dispose();
    _controller.dispose();
    super.dispose();
  }
}

/// Limits expensive canvas paints to about 30 frames per second while the
/// animation controller itself remains synchronized with display vsync.
class _FrameLimitedRepaint extends ChangeNotifier {
  _FrameLimitedRepaint(this._animation) {
    _animation.addListener(_onTick);
  }

  final AnimationController _animation;
  final Stopwatch _clock = Stopwatch()..start();
  Duration _lastPaint = Duration.zero;

  void _onTick() {
    final elapsed = _clock.elapsed;
    if (elapsed - _lastPaint < const Duration(milliseconds: 33)) return;
    _lastPaint = elapsed;
    notifyListeners();
  }

  @override
  void dispose() {
    _animation.removeListener(_onTick);
    _clock.stop();
    super.dispose();
  }
}

class _RadarSweepPainter extends CustomPainter {
  _RadarSweepPainter({
    required this.center,
    required this.radius,
    required this.color,
    required this.animation,
    required Listenable repaint,
  })  : _trailShader = SweepGradient(
          startAngle: -_trailAngle,
          endAngle: 0,
          colors: <Color>[
            color.withValues(alpha: .03),
            color.withValues(alpha: .21),
          ],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
        super(repaint: repaint);

  static const int _ringCount = 5;
  static const double _trailAngle = 80 * math.pi / 180;
  static const double _beamHalfAngle = 1.25 * math.pi / 180;

  final Offset center;
  final double radius;
  final Color color;
  final Animation<double> animation;
  final Shader _trailShader;

  @override
  void paint(Canvas canvas, Size size) {
    final ringsPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: .22);
    final trailPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = _trailShader;
    final beamPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: .72);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(animation.value * 2 * math.pi - math.pi / 2);

    for (var index = 1; index <= _ringCount; index++) {
      canvas.drawCircle(Offset.zero, radius * index / _ringCount, ringsPaint);
    }

    final circle = Rect.fromCircle(center: Offset.zero, radius: radius);
    final trail = Path()
      ..moveTo(0, 0)
      ..lineTo(radius * math.cos(-_trailAngle), radius * math.sin(-_trailAngle))
      ..arcTo(circle, -_trailAngle, _trailAngle, false)
      ..close();
    canvas.drawPath(trail, trailPaint);

    final beam = Path()
      ..moveTo(0, 0)
      ..lineTo(
        radius * math.cos(-_beamHalfAngle),
        radius * math.sin(-_beamHalfAngle),
      )
      ..arcTo(circle, -_beamHalfAngle, _beamHalfAngle * 2, false)
      ..close();
    canvas.drawPath(beam, beamPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) =>
      center != oldDelegate.center ||
      radius != oldDelegate.radius ||
      color != oldDelegate.color;
}
