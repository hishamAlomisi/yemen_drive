import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config/app_environment.dart';
import 'map_backdrop.dart';

class AppGoogleMap extends StatefulWidget {
  const AppGoogleMap({
    this.width,
    this.height,
    this.initialTarget = const LatLng(15.3694, 44.1910),
    this.initialZoom = 14,
    this.followTarget,
    this.focusBounds,
    this.focusBoundsPadding = 72,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.circles = const <Circle>{},
    this.myLocationEnabled = false,
    this.zoomControlsEnabled = false,
    this.compassEnabled = true,
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

  /// Optional bounds used to frame a selected trip route after the native map
  /// has a real size. This is intentionally separate from [followTarget]:
  /// tracking may follow a moving driver after the initial route focus.
  final LatLngBounds? focusBounds;
  final double focusBoundsPadding;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;
  final bool myLocationEnabled;
  final bool zoomControlsEnabled;
  final bool compassEnabled;
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

class _AppGoogleMapState extends State<AppGoogleMap> {
  bool _isLoading = true;
  GoogleMapController? _controller;
  LatLngBounds? _lastFocusedBounds;

  @override
  void didUpdateWidget(covariant AppGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.followTarget;
    if (target != null && target != oldWidget.followTarget) {
      unawaited(_animateTo(target));
    }
    if (!_sameBounds(widget.focusBounds, oldWidget.focusBounds)) {
      unawaited(_focusBounds());
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
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialTarget,
              zoom: widget.initialZoom,
            ),
            markers: widget.markers,
            polylines: widget.polylines,
            circles: widget.circles,
            myLocationEnabled: widget.myLocationEnabled,
            myLocationButtonEnabled: widget.myLocationEnabled,
            zoomControlsEnabled: widget.zoomControlsEnabled,
            compassEnabled: widget.compassEnabled,
            onMapCreated: (controller) {
              _controller = controller;
              final style = isDark ? widget.darkStyle : widget.lightStyle;
              if (style != null && style.isNotEmpty) {
                controller.setMapStyle(style);
              }
              widget.onMapCreated?.call(controller);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) unawaited(_focusBounds());
              });
              if (mounted) setState(() => _isLoading = false);
            },
            onCameraMove: widget.onCameraMove,
            onCameraIdle: widget.onCameraIdle,
            onTap: widget.onTap,
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
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }
}
