import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/theme/app_map_styles.dart';
import '../../core/realtime/ride_map_route_observer.dart';
import '../../features/ride/controllers/ride_controller.dart';
import '../../features/ride/models/ride_models.dart';
import 'nearby_driver_card.dart';

class AppGoogleMap extends StatefulWidget {
  const AppGoogleMap({
    this.width,
    this.height,
    this.initialTarget = const LatLng(15.3694, 44.1910),
    this.initialZoom = 14,
    this.followTarget,
    this.focusTarget,
    this.focusTargetZoom = 15.5,
    this.continuousFocusTarget = false,
    this.pauseOnUserInteraction = false,
    this.followRequestId = 0,
    this.onUserInteraction,
    this.nativeFrameInterval = Duration.zero,
    this.focusBounds,
    this.focusBoundsPadding = 72,
    this.focusBoundsRevision = 0,
    this.focusBoundsUpdateInterval,
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
    this.showNearbyDrivers = true,
    this.onNearbyDriverTap,
    this.onNearbyVisibilityChanged,
    super.key,
  });

  final double? width;
  final double? height;
  final LatLng initialTarget;
  final double initialZoom;
  final LatLng? followTarget;
  final LatLng? focusTarget;
  final double focusTargetZoom;

  /// Follow an already-interpolated location without queuing native animations.
  final bool continuousFocusTarget;

  /// A pan or pinch keeps the viewport under the user's control until an
  /// explicit [followRequestId] change. Marker updates continue normally.
  final bool pauseOnUserInteraction;
  final int followRequestId;
  final VoidCallback? onUserInteraction;

  /// Coalesces interpolated map frames before the plugin submits native object
  /// updates. Zero keeps ordinary booking and selection maps immediate.
  final Duration nativeFrameInterval;

  /// Optional bounds used to frame a selected trip route after the native map
  /// has a real size. This is intentionally separate from [followTarget]:
  /// tracking may follow a moving driver after the initial route focus.
  final LatLngBounds? focusBounds;
  final double focusBoundsPadding;

  /// Increments when the caller explicitly wants the current bounds framed
  /// again, even if the coordinates themselves have not changed.
  final int focusBoundsRevision;

  /// Limits camera work while a live marker is interpolated frequently. The
  /// marker still receives every update; only map camera movements are paced.
  final Duration? focusBoundsUpdateInterval;
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
  final bool showNearbyDrivers;
  final ValueChanged<NearbyDriver>? onNearbyDriverTap;
  final ValueChanged<bool>? onNearbyVisibilityChanged;

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

class _CameraRequest {
  const _CameraRequest(
      {this.target,
      this.zoom,
      this.bounds,
      this.padding = 72,
      this.continuous = false,
      this.force = false,
      this.interval = const Duration(milliseconds: 200)});
  final LatLng? target;
  final double? zoom;
  final LatLngBounds? bounds;
  final double padding;
  final bool continuous;
  final bool force;
  final Duration interval;
}

class _AppGoogleMapState extends State<AppGoogleMap>
    with RouteAware, WidgetsBindingObserver {
  RideController? _rideController;
  ModalRoute<void>? _observedRoute;
  bool _routeVisible = true;
  bool _tickerEnabled = true;
  bool _foreground = true;
  bool _nearbySyncScheduled = false;
  bool _lastMapWorkEnabled = false;
  bool get _mapWorkEnabled => _routeVisible && _tickerEnabled && _foreground;
  bool _nearbyLeaseActive = false;
  bool _isLoading = true;
  GoogleMapController? _controller;
  LatLngBounds? _lastFocusedBounds;
  LatLng? _lastFocusedTarget;
  int _cameraRevision = 0;
  double? _lastFocusedZoom;
  final _cameraClock = Stopwatch()..start();
  Duration? _lastCameraUpdateAt;
  Timer? _pendingCameraTimer;
  _CameraRequest? _pendingCameraRequest;
  bool _cameraUpdateInFlight = false;
  bool _cameraPausedByUser = false;
  final Map<int, Offset> _mapPointers = {};
  bool get _cameraWorkEnabled =>
      _mapWorkEnabled &&
      (!widget.pauseOnUserInteraction ||
          (!_cameraPausedByUser && _mapPointers.isEmpty));
  String? _cardDriverId;
  bool _cardIsAssigned = false;
  final ValueNotifier<Offset?> _cardMarkerPosition = ValueNotifier(null);
  NearbyDriver? _cachedDriverCardData;
  NearbyDriverCard? _cachedDriverCard;
  Timer? _cardProjectionTimer;
  bool _cardProjectionInFlight = false;
  bool _cardProjectionQueued = false;
  LatLng? _lastCardProjectionPoint;
  String? _lastCardProjectionDriverId;
  int _lastCardProjectionRevision = -1;
  bool _radarProjectionInFlight = false;
  DateTime? _lastDriverTapAt;
  final ValueNotifier<_RadarProjection?> _radarProjection =
      ValueNotifier<_RadarProjection?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_mapWorkEnabled) _cancelPendingMapWork();
    _syncNearbyAfterFrame();
  }

  void _cancelPendingMapWork() {
    _pendingCameraTimer?.cancel();
    _pendingCameraTimer = null;
    _pendingCameraRequest = null;
    _cardProjectionTimer?.cancel();
    _cardProjectionTimer = null;
    _cardProjectionQueued = false;
    _mapPointers.clear();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rideController =
        Get.isRegistered<RideController>() ? Get.find<RideController>() : null;
    _tickerEnabled = TickerMode.of(context);
    final route = ModalRoute.of<void>(context);
    if (route != _observedRoute) {
      rideMapRouteObserver.unsubscribe(this);
      _observedRoute = route;
      if (route != null) rideMapRouteObserver.subscribe(this, route);
    }
    _routeVisible = route?.isCurrent ?? true;
    if (!_mapWorkEnabled) _cancelPendingMapWork();
    _syncNearbyAfterFrame();
  }

  @override
  void didPush() => _setRouteVisible(true);
  @override
  void didPopNext() => _setRouteVisible(true);
  @override
  void didPushNext() => _setRouteVisible(false);
  @override
  void didPop() => _setRouteVisible(false);

  void _setRouteVisible(bool visible) {
    _routeVisible = visible;
    if (!_mapWorkEnabled) _cancelPendingMapWork();
    _syncNearbyAfterFrame();
  }

  void _syncNearbyAfterFrame() {
    if (_nearbySyncScheduled) return;
    _nearbySyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nearbySyncScheduled = false;
      if (!mounted) return;
      final visible = widget.showNearbyDrivers &&
          _mapWorkEnabled &&
          (_rideController?.showNearbyDriversOnMaps ?? true);
      final mapWorkChanged = _mapWorkEnabled != _lastMapWorkEnabled;
      if (_mapWorkEnabled && !_lastMapWorkEnabled) _requestCurrentCamera();
      _lastMapWorkEnabled = _mapWorkEnabled;
      if (!_mapWorkEnabled) _dismissMapDriverCard();
      if (visible == _nearbyLeaseActive) {
        if (mapWorkChanged) setState(() {});
        return;
      }
      _nearbyLeaseActive = visible;
      _rideController?.setNearbyMapVisible(this, visible);
      widget.onNearbyVisibilityChanged?.call(visible);
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant AppGoogleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final followRequested = widget.followRequestId != oldWidget.followRequestId;
    if (followRequested) {
      _cameraPausedByUser = false;
      _lastFocusedBounds = null;
      _lastFocusedTarget = null;
      _requestCurrentCamera(force: true);
    }
    if (oldWidget.showNearbyDrivers != widget.showNearbyDrivers) {
      _syncNearbyAfterFrame();
    }
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
        if (_pendingCameraRequest?.target != null) {
          _pendingCameraRequest = null;
          _pendingCameraTimer?.cancel();
          _pendingCameraTimer = null;
        }
      } else {
        unawaited(_focusTarget());
      }
    }
    final shouldRefocusBounds =
        widget.focusBoundsRevision != oldWidget.focusBoundsRevision;
    if (!_sameBounds(widget.focusBounds, oldWidget.focusBounds) ||
        shouldRefocusBounds) {
      if (widget.focusTarget == null) {
        unawaited(_requestFocusBounds(force: shouldRefocusBounds));
      } else {
        _lastFocusedBounds = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          if (_rideController != null && widget.showNearbyDrivers)
            Obx(() {
              final discoveryAllowed = _rideController!.showNearbyDriversOnMaps;
              _syncNearbyAfterFrame();
              return _nativeMap(resolvedMapStyle, {
                ..._markersWithDriverTaps(),
                if (_nearbyLeaseActive && discoveryAllowed)
                  ..._rideController!.nearbyDriverMarkersFor(
                      onTap: widget.onNearbyDriverTap ??
                          (driver) =>
                              _selectMapDriver(driver, assigned: false)),
              });
            })
          else
            _nativeMap(resolvedMapStyle, _markersWithDriverTaps()),
          if (_cardDriverId != null && _rideController != null)
            Obx(() {
              _requestCardProjection();
              final driver = _mapCardDriver;
              return ValueListenableBuilder<Offset?>(
                valueListenable: _cardMarkerPosition,
                builder: (_, position, __) =>
                    _buildMapDriverCard(driver, position),
              );
            }),
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

  Set<Marker> _markersWithDriverTaps() => {
        for (final marker in widget.markers)
          if (marker.markerId.value == 'tracked-driver' &&
              _rideController != null)
            marker.copyWith(onTapParam: () {
              final assigned = _rideController?.assignedDriverOnMap;
              if (assigned != null) _selectMapDriver(assigned, assigned: true);
            })
          else
            marker,
      };

  Widget _nativeMap(String? resolvedMapStyle, Set<Marker> markers) => Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      onPointerSignal: (_) => _pauseCameraForUser(),
      onPointerPanZoomStart: (_) => _pauseCameraForUser(),
      child: _PacedNativeMapFrame(
          interval: widget.nativeFrameInterval,
          active: _mapWorkEnabled,
          child: GoogleMap(
            style: resolvedMapStyle,
            padding: widget.mapPadding,
            mapType: widget.mapType,
            initialCameraPosition: CameraPosition(
              target: widget.initialTarget,
              zoom: widget.initialZoom,
            ),
            markers: markers,
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
                } else if (widget.focusBounds != null) {
                  await _focusBounds();
                } else if (widget.followTarget != null) {
                  await _animateTo(widget.followTarget!);
                }
                if (widget.radarOverlay != null) {
                  await _refreshRadarProjection();
                }
              });
              if (mounted) setState(() => _isLoading = false);
            },
            onCameraMove: _handleCameraMove,
            onCameraIdle: _handleCameraIdle,
            onTap: _handleMapTap,
          )));

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.pauseOnUserInteraction) return;
    _mapPointers[event.pointer] = event.localPosition;
    // A finger takes priority immediately, including while the native map is
    // deciding whether this sequence is a marker tap, a pan or a pinch.
    _pendingCameraTimer?.cancel();
    _pendingCameraTimer = null;
    _pendingCameraRequest = null;
    if (_mapPointers.length > 1) _pauseCameraForUser();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final origin = _mapPointers[event.pointer];
    if (origin != null && (event.localPosition - origin).distance > 8) {
      _pauseCameraForUser();
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (!widget.pauseOnUserInteraction) return;
    _mapPointers.remove(event.pointer);
    if (_mapPointers.isEmpty && !_cameraPausedByUser) _requestCurrentCamera();
  }

  void _pauseCameraForUser() {
    if (!widget.pauseOnUserInteraction || _cameraPausedByUser) return;
    _cameraPausedByUser = true;
    _pendingCameraTimer?.cancel();
    _pendingCameraTimer = null;
    _pendingCameraRequest = null;
    widget.onUserInteraction?.call();
  }

  void _requestCurrentCamera({bool force = false}) {
    if (widget.focusTarget != null) {
      unawaited(_focusTarget(force: force));
    } else if (widget.focusBounds != null) {
      unawaited(_focusBounds(force: force));
    } else if (widget.followTarget != null) {
      _queueCamera(_CameraRequest(target: widget.followTarget!, force: force));
    }
  }

  void _handleCameraMove(CameraPosition position) {
    _cameraRevision++;
    if (widget.radarOverlay != null && _radarProjection.value != null) {
      _radarProjection.value = null;
    }
    widget.onCameraMove?.call(position);
    _requestCardProjection();
  }

  void _handleCameraIdle() {
    _requestCardProjection();
    if (widget.radarOverlay != null) {
      unawaited(_refreshRadarProjection());
    }
    widget.onCameraIdle?.call();
  }

  Future<void> _refreshRadarProjection() async {
    final controller = _controller;
    final radar = widget.radarOverlay;
    if (!mounted ||
        !_mapWorkEnabled ||
        controller == null ||
        radar == null ||
        _radarProjectionInFlight) return;
    _radarProjectionInFlight = true;
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
    } finally {
      _radarProjectionInFlight = false;
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

  Future<void> _focusBounds({bool force = false}) async {
    final bounds = widget.focusBounds;
    if (bounds == null) return;
    _queueCamera(_CameraRequest(
        bounds: bounds,
        padding: widget.focusBoundsPadding,
        force: force,
        interval: widget.focusBoundsUpdateInterval ??
            const Duration(milliseconds: 200)));
  }

  Future<void> _requestFocusBounds({bool force = false}) async {
    if (widget.focusBounds == null && _pendingCameraRequest?.bounds != null) {
      _pendingCameraRequest = null;
      _pendingCameraTimer?.cancel();
      _pendingCameraTimer = null;
    }
    await _focusBounds(force: force);
  }

  Future<void> _focusTarget({bool force = false}) async {
    final target = widget.focusTarget;
    if (target == null) return;
    _queueCamera(_CameraRequest(
        target: target,
        force: force,
        zoom: widget.focusTargetZoom,
        continuous: widget.continuousFocusTarget));
  }

  Future<void> _animateTo(LatLng target) async {
    _queueCamera(_CameraRequest(target: target));
  }

  void _queueCamera(_CameraRequest request) {
    if (!mounted || !_cameraWorkEnabled || _controller == null) return;
    // Every camera mode shares one native operation and one latest pending
    // value. A slow platform channel cannot accumulate animations behind GPS.
    _pendingCameraRequest = request;
    _scheduleCamera();
  }

  void _scheduleCamera() {
    final request = _pendingCameraRequest;
    if (!mounted ||
        !_cameraWorkEnabled ||
        request == null ||
        _cameraUpdateInFlight ||
        _pendingCameraTimer != null) return;
    final interval = request.interval < const Duration(milliseconds: 200)
        ? const Duration(milliseconds: 200)
        : request.interval;
    final now = _cameraClock.elapsed;
    final elapsed =
        _lastCameraUpdateAt == null ? interval : now - _lastCameraUpdateAt!;
    if (elapsed >= interval) {
      unawaited(_drainCamera());
    } else {
      _pendingCameraTimer = Timer(interval - elapsed, () {
        _pendingCameraTimer = null;
        unawaited(_drainCamera());
      });
    }
  }

  Future<void> _drainCamera() async {
    final controller = _controller;
    final request = _pendingCameraRequest;
    if (!mounted ||
        !_cameraWorkEnabled ||
        controller == null ||
        request == null ||
        _cameraUpdateInFlight) return;
    _pendingCameraRequest = null;
    if (!request.force &&
        (request.bounds != null
            ? _sameBounds(request.bounds, _lastFocusedBounds)
            : request.target == _lastFocusedTarget &&
                request.zoom == _lastFocusedZoom &&
                _lastFocusedBounds == null)) return;
    final continuous = request.continuous && _lastFocusedTarget != null;
    _lastFocusedTarget = request.target;
    _lastFocusedZoom = request.zoom;
    _lastFocusedBounds = request.bounds;
    _lastCameraUpdateAt = _cameraClock.elapsed;
    _cameraUpdateInFlight = true;
    try {
      final update = request.bounds != null
          ? CameraUpdate.newLatLngBounds(request.bounds!, request.padding)
          : request.zoom != null
              ? CameraUpdate.newLatLngZoom(request.target!, request.zoom!)
              : CameraUpdate.newLatLng(request.target!);
      if (continuous) {
        await controller.moveCamera(update);
      } else {
        await controller.animateCamera(update);
      }
    } catch (_) {
      _lastFocusedTarget = null;
      _lastFocusedBounds = null;
    } finally {
      _cameraUpdateInFlight = false;
      _scheduleCamera();
    }
  }

  NearbyDriver? get _mapCardDriver {
    if (_cardDriverId == null || _rideController == null) return null;
    if (_cardIsAssigned) {
      final driver = _rideController!.assignedDriverOnMap;
      return driver?.id == _cardDriverId ? driver : null;
    }
    if (!_rideController!.showNearbyDriversOnMaps) return null;
    return _rideController!.nearbyDrivers
        .firstWhereOrNull((driver) => driver.id == _cardDriverId);
  }

  void _selectMapDriver(NearbyDriver driver, {required bool assigned}) {
    _lastDriverTapAt = DateTime.now();
    setState(() {
      _cardDriverId = driver.id;
      _cardIsAssigned = assigned;
      _cardMarkerPosition.value = null;
      _lastCardProjectionPoint = null;
      _lastCardProjectionDriverId = null;
    });
    _requestCardProjection();
  }

  void _dismissMapDriverCard() {
    if (_cardDriverId == null || !mounted) return;
    setState(() {
      _cardDriverId = null;
      _cardMarkerPosition.value = null;
    });
  }

  void _handleMapTap(LatLng point) {
    if (_lastDriverTapAt != null &&
        DateTime.now().difference(_lastDriverTapAt!) <
            const Duration(milliseconds: 750)) return;
    _dismissMapDriverCard();
    widget.onTap?.call(point);
  }

  void _requestCardProjection() {
    if (_cardDriverId == null || !mounted || !_mapWorkEnabled) return;
    final driver = _mapCardDriver;
    final point = driver == null
        ? null
        : LatLng(driver.location.latitude, driver.location.longitude);
    if (driver?.id == _lastCardProjectionDriverId &&
        point == _lastCardProjectionPoint &&
        _cameraRevision == _lastCardProjectionRevision) return;
    if (_cardProjectionInFlight) {
      _cardProjectionQueued = true;
      return;
    }
    if (_cardProjectionTimer != null) return;
    _cardProjectionTimer = Timer(const Duration(milliseconds: 60), () {
      _cardProjectionTimer = null;
      unawaited(_projectMapCard());
    });
  }

  Future<void> _projectMapCard() async {
    if (_cardProjectionInFlight || !mounted || !_mapWorkEnabled) return;
    final driver = _mapCardDriver;
    final controller = _controller;
    if (driver == null || controller == null) {
      _dismissMapDriverCard();
      return;
    }
    final point = LatLng(driver.location.latitude, driver.location.longitude);
    final revision = _cameraRevision;
    _lastCardProjectionPoint = point;
    _lastCardProjectionDriverId = driver.id;
    _lastCardProjectionRevision = revision;
    _cardProjectionInFlight = true;
    try {
      final screen = await controller.getScreenCoordinate(point);
      if (!mounted ||
          !_mapWorkEnabled ||
          _cardDriverId != driver.id ||
          revision != _cameraRevision) return;
      final ratio = defaultTargetPlatform == TargetPlatform.android
          ? MediaQuery.devicePixelRatioOf(context)
          : 1.0;
      final position = Offset(screen.x / ratio, screen.y / ratio);
      _cardMarkerPosition.value = position;
    } catch (_) {
      // Native projection is retried after the next camera/location update.
    } finally {
      _cardProjectionInFlight = false;
      if (_cardProjectionQueued) {
        _cardProjectionQueued = false;
        _requestCardProjection();
      }
    }
  }

  Widget _buildMapDriverCard(NearbyDriver? driver, Offset? marker) {
    if (driver == null || marker == null) return const SizedBox.shrink();
    final size = Size(widget.width ?? MediaQuery.sizeOf(context).width,
        widget.height ?? MediaQuery.sizeOf(context).height);
    final width = math.min(320.0, math.max(100.0, size.width - 24));
    final left = (marker.dx - width / 2)
        .clamp(12.0, math.max(12.0, size.width - width - 12))
        .toDouble();
    final top = (marker.dy - 200)
        .clamp(12.0, math.max(12.0, size.height - 188))
        .toDouble();
    final pointer = (marker.dx - left).clamp(22.0, width - 22).toDouble();
    if (!_sameDriverCardContents(driver, _cachedDriverCardData) ||
        _cachedDriverCard?.pointerX != pointer) {
      _cachedDriverCardData = driver;
      _cachedDriverCard = NearbyDriverCard(
        driver: driver,
        pointerX: pointer,
        onClose: _dismissMapDriverCard,
      );
    }
    return Positioned(
        left: left,
        top: top,
        width: width,
        height: 176,
        child: RepaintBoundary(child: _cachedDriverCard!));
  }

  bool _sameDriverCardContents(NearbyDriver first, NearbyDriver? second) =>
      second != null &&
      first.id == second.id &&
      first.name == second.name &&
      first.photoUrl == second.photoUrl &&
      first.vehicleType == second.vehicleType &&
      first.rating == second.rating &&
      first.vehicleModel == second.vehicleModel &&
      first.plateNumber == second.plateNumber &&
      first.completedTrips == second.completedTrips;

  bool _sameBounds(LatLngBounds? first, LatLngBounds? second) {
    if (identical(first, second)) return true;
    if (first == null || second == null) return false;
    return first.southwest.latitude == second.southwest.latitude &&
        first.southwest.longitude == second.southwest.longitude &&
        first.northeast.latitude == second.northeast.latitude &&
        first.northeast.longitude == second.northeast.longitude;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cardProjectionTimer?.cancel();
    _cardMarkerPosition.dispose();
    rideMapRouteObserver.unsubscribe(this);
    final ride = _rideController;
    // A navigator can dispose this map while the widget tree is locked.
    // Releasing the last lease clears reactive markers on other mounted maps.
    scheduleMicrotask(() => ride?.setNearbyMapVisible(this, false));
    _cancelPendingMapWork();
    _radarProjection.dispose();
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }
}

/// The plugin dispatches its object updates asynchronously for every widget
/// rebuild. Keep one latest frame while interpolation runs faster than the
/// desired submission rate; no queue of old map frames is retained.
class _PacedNativeMapFrame extends StatefulWidget {
  const _PacedNativeMapFrame({
    required this.child,
    required this.interval,
    required this.active,
  });

  final Widget child;
  final Duration interval;
  final bool active;

  @override
  State<_PacedNativeMapFrame> createState() => _PacedNativeMapFrameState();
}

class _PacedNativeMapFrameState extends State<_PacedNativeMapFrame>
    with WidgetsBindingObserver {
  late Widget _displayed;
  Timer? _timer;
  bool _foreground = true;
  bool _tickerEnabled = true;
  bool get _active => widget.active && _foreground && _tickerEnabled;

  @override
  void initState() {
    super.initState();
    _displayed = widget.child;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.of(context);
    _queueLatest();
  }

  @override
  void didUpdateWidget(covariant _PacedNativeMapFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && _active) {
      _timer?.cancel();
      _timer = null;
      _displayed = widget.child;
      return;
    }
    _queueLatest();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _queueLatest();
    if (_foreground && mounted) setState(() {});
  }

  void _queueLatest() {
    if (!_active) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (widget.interval <= Duration.zero) {
      _timer?.cancel();
      _timer = null;
      _displayed = widget.child;
      return;
    }
    if (identical(_displayed, widget.child) || _timer != null) return;
    _timer = Timer(widget.interval, () {
      _timer = null;
      if (!mounted || !_active) return;
      setState(() => _displayed = widget.child);
    });
  }

  @override
  Widget build(BuildContext context) => _displayed;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
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
