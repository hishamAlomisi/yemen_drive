import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/cache/persistent_network_image.dart';
import '../../../shared/widgets/app_google_map.dart';
import '../../account/account_routes.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import '../controllers/ride_controller.dart';
import '../models/ride_models.dart';
import 'ride_common_widgets.dart';
import 'ride_map_shell.dart';

class RideHomeTemplate extends GetView<RideController> {
  const RideHomeTemplate({
    required this.type,
    this.showBottomNavigation = true,
    this.embedded = false,
    super.key,
  });

  final RideServiceType type;
  final bool showBottomNavigation;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (controller.nearbyDrivers.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) async {
          final location = Get.find<LocationController>();
          await location.ensureInitialPickupLocation();
          if (location.pickup.value != null &&
              controller.nearbyDrivers.isEmpty) {
            await controller.loadNearbyDrivers(center: location.pickup.value);
          }
        },
      );
    }
    return RideMapShell(
      map: Obx(
        () => NearbyDriversMap(
          mapType: Get.find<LocationController>().mapType.value,
          useModernMapStyle: true,
        ),
      ),
      panelMaxHeightFactor: .58,
      fitPanelToContent: true,
      top: const RideHomeHeader(),
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RidePanelHandle(),
          Text('booking_services'.tr,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          RideServiceTiles(onSelected: (index) {
            controller.selectHomeService(index);
            controller.startHomeService();
          }),
        ],
      ),
      embedded: embedded,
    );
  }
}

class NearbyDriversMap extends StatefulWidget {
  const NearbyDriversMap({
    this.additionalMarkers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.initialTarget = const LatLng(15.3694, 44.1910),
    this.followTarget,
    this.initialZoom = 13.5,
    this.onMapCreated,
    this.onTap,
    this.minimumCardTop = 112,
    this.mapType = MapType.normal,
    this.useModernMapStyle = false,
    this.mapPadding = EdgeInsets.zero,
    this.focusBounds,
    this.focusBoundsRevision = 0,
    super.key,
  });

  final Set<Marker> additionalMarkers;
  final Set<Polyline> polylines;
  final LatLng initialTarget;
  final LatLng? followTarget;
  final double initialZoom;
  final MapCreatedCallback? onMapCreated;
  final ArgumentCallback<LatLng>? onTap;
  final double minimumCardTop;
  final MapType mapType;
  final bool useModernMapStyle;
  final EdgeInsets mapPadding;
  final LatLngBounds? focusBounds;
  final int focusBoundsRevision;

  @override
  State<NearbyDriversMap> createState() => _NearbyDriversMapState();
}

class _NearbyDriversMapState extends State<NearbyDriversMap> {
  static const double _cardHeight = 176;
  static const double _markerVisualHeight = 32;
  static _NearbyDriversMapState? _activeCardOwner;

  final RideController _rideController = Get.find<RideController>();
  final LocationController _locationController = Get.find<LocationController>();
  final GlobalKey _mapKey = GlobalKey();
  GoogleMapController? _mapController;
  OverlayEntry? _driverCardOverlay;
  Offset? _markerPosition;
  DateTime? _lastDriverMarkerTapAt;

  @override
  void didUpdateWidget(covariant NearbyDriversMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final updatedPickup = widget.followTarget;
    if (updatedPickup != null && updatedPickup != oldWidget.followTarget) {
      unawaited(_rideController.loadNearbyDrivers(center: updatedPickup));
    }
  }

  void _selectDriverFromThisMap(NearbyDriver driver) {
    _lastDriverMarkerTapAt = DateTime.now();
    if (_activeCardOwner != this) {
      _activeCardOwner?._dismissDriverCard(clearSelection: false);
      _activeCardOwner = this;
    }
    _markerPosition = null;
    _removeDriverCardOverlay();
    _rideController.selectNearbyDriver(driver);
    _updateCardPosition();
  }

  void _handleMapTap(LatLng point) {
    // Some Android map renderers can still forward a marker press as a map
    // press. Protect both event orders: consume a recent marker press, and
    // treat a coordinate over a driver marker as that driver's interaction.
    final markerTapAt = _lastDriverMarkerTapAt;
    if (markerTapAt != null &&
        DateTime.now().difference(markerTapAt) <
            const Duration(milliseconds: 750)) {
      return;
    }
    final selectedDriver = _driverAt(point);
    if (selectedDriver != null) {
      _selectDriverFromThisMap(selectedDriver);
      return;
    }
    _dismissDriverCard();
    widget.onTap?.call(point);
  }

  NearbyDriver? _driverAt(LatLng point) {
    for (final driver in _rideController.nearbyDrivers) {
      if (_distanceMeters(
            point.latitude,
            point.longitude,
            driver.location.latitude,
            driver.location.longitude,
          ) <=
          22) {
        return driver;
      }
    }
    return null;
  }

  double _distanceMeters(
    double firstLatitude,
    double firstLongitude,
    double secondLatitude,
    double secondLongitude,
  ) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(secondLatitude - firstLatitude);
    final longitudeDelta = _radians(secondLongitude - firstLongitude);
    final firstLatitudeRadians = _radians(firstLatitude);
    final secondLatitudeRadians = _radians(secondLatitude);
    final a = math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(firstLatitudeRadians) *
            math.cos(secondLatitudeRadians) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double value) => value * math.pi / 180;

  void _dismissDriverCard({bool clearSelection = true}) {
    _markerPosition = null;
    _removeDriverCardOverlay();
    if (_activeCardOwner == this) _activeCardOwner = null;
    if (clearSelection) _rideController.closeNearbyDriverCard();
  }

  void _showDriverCardOverlay() {
    if (!mounted || _markerPosition == null) return;
    if (_driverCardOverlay == null) {
      _driverCardOverlay = OverlayEntry(builder: _buildDriverCardOverlay);
      Overlay.of(context, rootOverlay: true).insert(_driverCardOverlay!);
    } else {
      _driverCardOverlay?.markNeedsBuild();
    }
  }

  void _removeDriverCardOverlay() {
    _driverCardOverlay?.remove();
    _driverCardOverlay?.dispose();
    _driverCardOverlay = null;
  }

  Widget _buildDriverCardOverlay(BuildContext context) {
    final driver = _rideController.selectedNearbyDriver.value;
    final marker = _markerPosition;
    final mapBox = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (driver == null || marker == null || mapBox == null) {
      return const SizedBox.shrink();
    }
    final mapOrigin = mapBox.localToGlobal(Offset.zero);
    final mapSize = mapBox.size;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = math.min(320.0, mapSize.width - 24);
    final markerGlobal = mapOrigin + marker;
    final left = (markerGlobal.dx - (cardWidth / 2))
        .clamp(12.0, math.max(12.0, screenWidth - cardWidth - 12))
        .toDouble();
    final localTop = (marker.dy - _markerVisualHeight - _cardHeight)
        .clamp(
          widget.minimumCardTop,
          math.max(
            widget.minimumCardTop,
            mapSize.height - _cardHeight - 12,
          ),
        )
        .toDouble();
    final pointerX =
        (markerGlobal.dx - left).clamp(22.0, cardWidth - 22).toDouble();
    return Positioned(
      left: left,
      top: mapOrigin.dy + localTop,
      width: cardWidth,
      height: _cardHeight,
      child: NearbyDriverCard(
        driver: driver,
        pointerX: pointerX,
        onClose: _dismissDriverCard,
      ),
    );
  }

  Future<void> _updateCardPosition() async {
    if (_activeCardOwner != this) {
      _removeDriverCardOverlay();
      return;
    }
    final mapController = _mapController;
    final driver = _rideController.selectedNearbyDriver.value;
    if (!mounted) return;
    if (mapController == null || driver == null) {
      setState(() => _markerPosition = null);
      return;
    }
    try {
      final coordinate = await mapController.getScreenCoordinate(
        LatLng(driver.location.latitude, driver.location.longitude),
      );
      if (!mounted ||
          driver.id != _rideController.selectedNearbyDriver.value?.id) {
        return;
      }
      final pixelRatio = defaultTargetPlatform == TargetPlatform.android
          ? MediaQuery.devicePixelRatioOf(context)
          : 1.0;
      _markerPosition = Offset(
        coordinate.x / pixelRatio,
        coordinate.y / pixelRatio,
      );
      _showDriverCardOverlay();
    } catch (_) {
      _markerPosition = null;
      _removeDriverCardOverlay();
    }
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        key: _mapKey,
        child: Obx(
          () => AppGoogleMap(
            initialTarget: widget.initialTarget,
            initialZoom: widget.initialZoom,
            followTarget: widget.focusBounds == null
                ? widget.followTarget ?? _locationController.pickup.value
                : null,
            focusBounds: widget.focusBounds,
            focusBoundsRevision: widget.focusBoundsRevision,
            focusBoundsPadding: 44,
            markers: <Marker>{
              ...widget.additionalMarkers,
              ..._rideController.nearbyDriverMarkersFor(
                onTap: _selectDriverFromThisMap,
              ),
            },
            polylines: widget.polylines,
            mapType: widget.mapType,
            useModernMapStyle: widget.useModernMapStyle,
            mapPadding: widget.mapPadding,
            onMapCreated: (controller) {
              _mapController = controller;
              widget.onMapCreated?.call(controller);
              _updateCardPosition();
            },
            onCameraIdle: _updateCardPosition,
            onTap: _handleMapTap,
          ),
        ),
      );

  @override
  void dispose() {
    _dismissDriverCard();
    super.dispose();
  }
}

class NearbyDriverCard extends StatelessWidget {
  const NearbyDriverCard({
    required this.driver,
    required this.pointerX,
    required this.onClose,
    super.key,
  });

  final NearbyDriver driver;
  final double pointerX;
  final VoidCallback onClose;

  String get _vehicleTypeKey => switch (driver.vehicleType) {
        RideVehicleType.car => 'vehicle_car',
        RideVehicleType.taxi => 'vehicle_taxi',
        RideVehicleType.bike => 'vehicle_bike',
        RideVehicleType.cycle => 'vehicle_cycle',
      };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final surface = colors.surface.withValues(alpha: .96);
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          bottom: 10,
          child: Material(
            color: surface,
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: .28),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: colors.primary.withValues(alpha: .42),
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _DriverPhoto(driver: driver),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                driver.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.star_rounded,
                                    size: 17,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    driver.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      '${driver.completedTrips} ${'completed_trips'.tr}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: onClose,
                          tooltip: 'close_driver_details'.tr,
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 19),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                    const SizedBox(height: 9),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _DriverDetail(
                            icon: Icons.directions_car_filled_rounded,
                            label: 'vehicle_model'.tr,
                            value: driver.vehicleModel.isEmpty
                                ? _vehicleTypeKey.tr
                                : '${_vehicleTypeKey.tr} · ${driver.vehicleModel}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DriverDetail(
                            icon: Icons.pin_outlined,
                            label: 'plate_number'.tr,
                            value: driver.plateNumber,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: pointerX - 8,
          bottom: 3,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: surface,
                border: Border(
                  right: BorderSide(
                    color: colors.primary.withValues(alpha: .42),
                  ),
                  bottom: BorderSide(
                    color: colors.primary.withValues(alpha: .42),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DriverPhoto extends StatelessWidget {
  const _DriverPhoto({required this.driver});

  final NearbyDriver driver;

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
        child: ClipOval(
          child: driver.photoUrl.isEmpty
              ? Image.asset(
                  'assets/images/branding/yemen_drive_logo.png',
                  fit: BoxFit.cover,
                )
              : PersistentNetworkImage(
                  driver.photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.person_rounded,
                  ),
                ),
        ),
      );
}

class _DriverDetail extends StatelessWidget {
  const _DriverDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            icon,
            size: 17,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 9,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class RideHomeHeader extends StatelessWidget {
  const RideHomeHeader({this.routePicker = false, super.key});
  final bool routePicker;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          RideIconButton(
            icon: Icons.menu,
            tooltip: 'القائمة',
            onPressed: () => Get.toNamed<void>(AccountRoutes.menu),
          ),
          const Spacer(),
          Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text('يمن درايف',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
        ],
      );
}

class RideServiceTiles extends GetView<RideController> {
  const RideServiceTiles({required this.onSelected, super.key});
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Obx(() {
        final services = controller.homeServices;
        final colors = Theme.of(context).colorScheme;
        if (services.isEmpty) {
          return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()));
        }
        return LayoutBuilder(
            builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (var index = 0; index < services.length; index++)
                      SizedBox(
                        width: (constraints.maxWidth - 8) / 2,
                        child: Material(
                          color: colors.surfaceContainer,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: controller.homeServiceIndex.value == index
                                  ? colors.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => onSelected(index),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(services[index].name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium),
                                  const SizedBox(height: 4),
                                  Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: SizedBox(
                                          height: 54,
                                          width: 92,
                                          child: _ServiceImage(
                                              services[index].imageUrl))),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ));
      });
}

class _ServiceImage extends StatelessWidget {
  const _ServiceImage(this.url);
  final String? url;
  @override
  Widget build(BuildContext context) {
    final value = url ?? '';
    final fallback = Icon(Icons.local_taxi_outlined,
        size: 48, color: Theme.of(context).colorScheme.onSurface);
    if (value.isEmpty) return fallback;
    return value.startsWith('http')
        ? PersistentNetworkImage(value,
            fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback)
        : Image.asset(value,
            fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
  }
}
