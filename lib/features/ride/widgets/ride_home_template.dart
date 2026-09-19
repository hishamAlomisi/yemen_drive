import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_google_map.dart';
import '../../../shared/widgets/directional_arrow.dart';
import '../../account/account_routes.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import '../controllers/ride_controller.dart';
import '../models/ride_models.dart';
import '../models/service_kind_models.dart';
import '../ride_routes.dart';
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
      map: const NearbyDriversMap(),
      panelMaxHeightFactor: .53,
      fitPanelToContent: true,
      panelHorizontalMargin: 16,
      panelBottomMargin: 14,
      panelColor: Colors.transparent,
      panelElevation: 0,
      top: const RideHomeHeader(),
      processStep: 0,
      floatingAction: Obx(
        () => _HomeStartButton(
          enabled: controller.homeServiceIndex.value >= 0,
          onPressed: controller.startHomeService,
        ),
      ),
      bottomNavigationBar: showBottomNavigation
          ? Obx(
              () => AppBottomNav(
                currentIndex: controller.bottomNavigationIndex.value,
                onTap: controller.updateBottomNavigation,
              ),
            )
          : null,
      panel: _ServiceCarousel(initialType: type),
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
            followTarget:
                widget.followTarget ?? _locationController.pickup.value,
            markers: <Marker>{
              ...widget.additionalMarkers,
              ..._rideController.nearbyDriverMarkersFor(
                onTap: _selectDriverFromThisMap,
              ),
            },
            polylines: widget.polylines,
            showDemoMarker: false,
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
              : Image.network(
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
  const RideHomeHeader({super.key});

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          RideIconButton(
            icon: Icons.menu_rounded,
            tooltip: 'القائمة',
            onPressed: () => Get.toNamed<void>(AccountRoutes.menu),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 2,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: InkWell(
                onTap: Get.find<RideController>().startHomeService,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.my_location_rounded, size: 19),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'موقعي الحالي · صنعاء',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          RideIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'الإشعارات',
            badge: true,
            onPressed: () => Get.toNamed<void>(RideRoutes.notifications),
          ),
        ],
      );
}

class _ServiceCarousel extends StatefulWidget {
  const _ServiceCarousel({required this.initialType});

  final RideServiceType initialType;

  @override
  State<_ServiceCarousel> createState() => _ServiceCarouselState();
}

class _ServiceCarouselState extends State<_ServiceCarousel> {
  static const List<RideHomeService> _fallbackServices = <RideHomeService>[
    RideHomeService(
      code: 'transport',
      name: 'نقل',
      imageUrl: 'assets/images/services/transport.png',
      rideServiceType: 'transport',
    ),
    RideHomeService(
      code: 'delivery',
      name: 'توصيل',
      imageUrl: 'assets/images/services/delivery.png',
      rideServiceType: 'delivery',
    ),
    RideHomeService(
      code: 'rental',
      name: 'تأجير',
      imageUrl: 'assets/images/services/rental.png',
      rideServiceType: null,
    ),
    RideHomeService(
      code: 'scheduled',
      name: 'رحلات مجدولة',
      imageUrl: 'assets/images/services/scheduled.png',
      rideServiceType: null,
    ),
  ];

  late final PageController _pageController;
  late int _page;

  List<RideHomeService> get _services {
    final values = Get.find<RideController>().homeServices;
    if (values.isNotEmpty) return values;
    return AppEnvironment.useDemoData
        ? _fallbackServices
        : const <RideHomeService>[];
  }

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialType == RideServiceType.delivery ? 1 : 0;
    final length = _services.isEmpty ? 1 : _services.length;
    _page = 1000 - (1000 % length) + initialIndex;
    _pageController = PageController(
      initialPage: _page,
      viewportFraction: .32,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_services.isEmpty) {
      return const SizedBox(
        height: 164,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF555B80).withValues(alpha: .94)
        : Colors.white.withValues(alpha: .92);
    final cardBorderColor = isDark
        ? Colors.white.withValues(alpha: .09)
        : Colors.black.withValues(alpha: .07);
    return SizedBox(
      height: 164,
      child: Stack(
        children: <Widget>[
          Positioned(
            top: 28,
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cardBorderColor),
              ),
            ),
          ),
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (value) {
                setState(() {
                  _page = value;
                });
                Get.find<RideController>().selectHomeService(
                  value % _services.length,
                );
              },
              itemBuilder: (context, index) {
                final service = _services[index % _services.length];
                return _ServiceLensItem(
                  service: service,
                  selected: index == _page,
                  onTap: () {
                    setState(() {
                      _page = index;
                    });
                    Get.find<RideController>().selectHomeService(
                      index % _services.length,
                    );
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeStartButton extends StatelessWidget {
  const _HomeStartButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: enabled
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface.withValues(alpha: .88),
        elevation: 8,
        shape: const CircleBorder(),
        child: IconButton(
          onPressed: onPressed,
          tooltip: 'بدء الرحلة',
          icon: const DirectionalArrowIcon(forward: true),
          color: enabled
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).disabledColor,
        ),
      );
}

class _ServiceLensItem extends StatelessWidget {
  const _ServiceLensItem({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final RideHomeService service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.only(top: selected ? 0 : 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: selected ? 116 : 84,
                height: selected ? 116 : 84,
                child: _ServiceImage(
                  service.imageUrl,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                service.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: selected ? 13 : 11,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .78),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ServiceImage extends StatelessWidget {
  const _ServiceImage(this.url);
  final String? url;
  @override
  Widget build(BuildContext context) {
    final value = url ?? '';
    final remote = value.startsWith('http://') || value.startsWith('https://');
    return remote
        ? Image.network(value,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.image_not_supported_outlined))
        : Image.asset(value,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.image_not_supported_outlined));
  }
}
