import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show Icons, TextPainter, TextSpan, TextStyle;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/services/auth_session_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/ride_preferences.dart';
import '../../account/account_routes.dart';
import '../home/repositories/service_kind_repository.dart';
import '../negotiation/repositories/ride_negotiation_repository.dart';
import '../vehicle_selection/repositories/service_catalog_repository.dart';
import '../models/ride_models.dart';
import '../models/service_kind_models.dart';
import '../ride_routes.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import '../location_selection/repositories/route_repository.dart';

class RideController extends GetxController {
  RideController(this._repository, this._session,
      [this._catalogRepository,
      ServiceKindRepository? serviceKinds,
      RouteRepository? routeRepository])
      : _serviceKinds = serviceKinds,
        _routeRepository = routeRepository;

  // Render at 3x and display as a balanced 28x36 logical marker.
  static const int _driverMarkerWidth = 84;
  static const int _driverMarkerHeight = 108;
  static const double _driverMarkerBaseWidth = 56;
  static const double _driverMarkerBaseHeight = 72;
  static const double _driverMarkerPixelRatio = 3;

  final RideNegotiationRepository _repository;
  final AuthSessionService _session;
  final ServiceCatalogRepository? _catalogRepository;
  final ServiceKindRepository? _serviceKinds;
  final RouteRepository? _routeRepository;
  final Rx<RideServiceType> serviceType = RideServiceType.transport.obs;
  final RxnInt selectedServiceKindId = RxnInt();
  final Rx<RideVehicleType> selectedTransport = RideVehicleType.car.obs;
  final RxBool hasSelectedTransport = false.obs;
  final Rxn<RideVehicle> selectedVehicle = Rxn<RideVehicle>();
  final RxList<RideVehicle> catalogVehicles = <RideVehicle>[].obs;
  final RxBool isCatalogLoading = false.obs;
  final RxString catalogError = ''.obs;
  final RxBool isUsingCatalogFallback = true.obs;
  final RxInt bottomNavigationIndex = 0.obs;
  final RxInt homeServiceIndex = (-1).obs;
  final RxList<RideHomeService> homeServices =
      <RideHomeService>[...demoHomeServices].obs;
  final RxBool autoStartTransport = RidePreferences.autoStartTransport.obs;
  final RxBool isSearchingForDriver = false.obs;
  final RxBool isDriverAssigned = false.obs;
  final RxString activeRideStatus = ''.obs;
  final Rxn<Map<String, Object?>> cashCollectionApproval =
      Rxn<Map<String, Object?>>();
  final RxString cancellationReason = ''.obs;
  final Rx<NegotiationStatus> negotiationStatus = NegotiationStatus.idle.obs;
  final RxString quoteError = ''.obs;
  final Rxn<RideQuote> quote = Rxn<RideQuote>();
  final Rxn<RideRequestDraft> currentDraft = Rxn<RideRequestDraft>();
  final Rxn<DriverOffer> acceptedOffer = Rxn<DriverOffer>();
  final RxString assignedDriverName = ''.obs;
  final RxString assignedDriverPhone = ''.obs;
  final RxDouble offeredPrice = 0.0.obs;
  final RxDouble routeDistanceKm = 0.0.obs;
  final RxList<DriverOffer> driverOffers = <DriverOffer>[].obs;
  final RxSet<String> removingOfferIds = <String>{}.obs;
  final RxBool offersExhausted = false.obs;
  final RxBool offersStreamDone = false.obs;
  final RxInt receivedOffersCount = 0.obs;
  final RxList<NearbyDriver> nearbyDrivers = <NearbyDriver>[].obs;

  /// Drivers that have received the current request, ordered by arrival.
  final RxList<NearbyDriver> requestRecipients = <NearbyDriver>[].obs;
  final Rxn<NearbyDriver> selectedNearbyDriver = Rxn<NearbyDriver>();
  final Rxn<BitmapDescriptor> _nearbyDriverIcon = Rxn<BitmapDescriptor>();
  final RxMap<String, BitmapDescriptor> _nearbyDriverPhotoIcons =
      <String, BitmapDescriptor>{}.obs;
  final Rxn<BitmapDescriptor> _approachingCarIcon = Rxn<BitmapDescriptor>();
  final Rxn<BitmapDescriptor> _inTripDirectionIcon = Rxn<BitmapDescriptor>();
  final Rxn<DriverTrackingSnapshot> trackedDriver =
      Rxn<DriverTrackingSnapshot>();
  final Rxn<RideCoordinate> trackedPassenger = Rxn<RideCoordinate>();
  final RxList<LatLng> trackingRoutePoints = <LatLng>[].obs;
  StreamSubscription<DriverOffer>? _offersSubscription;
  Timer? _trackingTimer;
  Timer? _recipientTimer;
  StreamSubscription<Position>? _passengerPositionSubscription;
  String? _requestId;
  bool _isResumingRequest = false;
  bool _hasCheckedForOpenRide = false;
  int _catalogRequestId = 0;
  int _quoteRequestId = 0;
  int _nearbyDriversRequestId = 0;
  DateTime? _lastPassengerLocationPublished;
  RideCoordinate? _lastTrackingRouteOrigin;
  RideCoordinate? _lastTrackingRouteDestination;
  DateTime? _lastTrackingRouteRequestedAt;
  int _trackingRouteRequestId = 0;
  bool hasShownTripSharePrompt = false;

  String? get currentRideId => _requestId;

  @override
  void onInit() {
    super.onInit();
    if (!AppEnvironment.useDemoData) {
      homeServices.clear();
    }
    unawaited(loadServiceCatalog());
    unawaited(_loadHomeServices());
    unawaited(_loadTrackingIcons());
  }

  @override
  void onReady() {
    super.onReady();
    unawaited(restoreOpenRideOnLaunch());
  }

  /// Restores the server's latest non-final ride after an app restart. The
  /// server remains the source of truth; no local draft is used to recreate it.
  Future<void> restoreOpenRideOnLaunch() async {
    if (_hasCheckedForOpenRide || !_session.isAuthenticated.value) return;
    _hasCheckedForOpenRide = true;

    try {
      final ride = await _repository.findLatestOpenRide();
      if (ride == null) return;
      final rideId = ride['id']?.toString();
      final status = _asInt(ride['status']);
      if (rideId == null || rideId.isEmpty || status == null) return;

      _restoreRideSnapshot(rideId, ride);
      await _continueRestoredRide(rideId, status);
    } catch (_) {
      // Opening the home screen remains available when the network is offline.
    }
  }

  /// Opens a non-final server ride from the history screen. This keeps a
  /// customer from being stranded with a pending driver offer after leaving
  /// or restarting the application.
  Future<void> resumeOpenRide(String rideId) async {
    final detail = await _repository.getRideDetail(rideId);
    final rawRide = detail['ride'];
    if (rawRide is! Map) {
      throw const FormatException('تعذر استعادة بيانات الرحلة.');
    }
    final ride = Map<String, Object?>.from(rawRide);
    final status = _asInt(ride['status']);
    if (status == null || status >= 6) {
      throw const FormatException('هذه الرحلة لم تعد قابلة للاستئناف.');
    }
    _restoreRideSnapshot(rideId, ride);
    await _continueRestoredRide(rideId, status);
  }

  Future<void> _continueRestoredRide(String rideId, int status) async {
    if (status <= 2) {
      negotiationStatus.value = NegotiationStatus.searching;
      isSearchingForDriver.value = true;
      offersExhausted.value = false;
      offersStreamDone.value = false;
      driverOffers.clear();
      receivedOffersCount.value = 0;
      await _watchOffers(rideId);
      if (!isClosed) Get.offAllNamed<void>(RideRoutes.negotiationQuote);
      return;
    }

    negotiationStatus.value = NegotiationStatus.accepted;
    isDriverAssigned.value = true;
    await refreshActiveRide();
    startRealTracking();
    if (!isClosed) Get.offAllNamed<void>(RideRoutes.driverLocation);
  }

  void _restoreRideSnapshot(String rideId, Map<String, Object?> ride) {
    _requestId = rideId;
    activeRideStatus.value = '${ride['status'] ?? ''}';
    final pickupLatitude = _asDouble(ride['pickupLatitude']) ?? 0;
    final pickupLongitude = _asDouble(ride['pickupLongitude']) ?? 0;
    final destinationLatitude = _asDouble(ride['destinationLatitude']) ?? 0;
    final destinationLongitude = _asDouble(ride['destinationLongitude']) ?? 0;
    final price = _asDouble(ride['customerPrice']) ?? 0;
    final pickup =
        RideCoordinate(latitude: pickupLatitude, longitude: pickupLongitude);
    final destination = RideCoordinate(
      latitude: destinationLatitude,
      longitude: destinationLongitude,
    );
    currentDraft.value = RideRequestDraft(
      customerId: _session.currentUserId.value,
      pickup:
          '${ride['pickupDisplayName'] ?? ride['pickupAddress'] ?? 'نقطة الانطلاق'}',
      destination:
          '${ride['destinationDisplayName'] ?? ride['destinationAddress'] ?? 'الوجهة'}',
      pickupCoordinate: pickup,
      destinationCoordinate: destination,
      serviceKindId: _asInt(ride['serviceKindId']) ?? 0,
      serviceCatalogItemId: _asInt(ride['serviceCatalogItemId']) ?? 0,
      offeredPrice: price,
      pickupAddress: '${ride['pickupAddress'] ?? ''}',
      destinationAddress: '${ride['destinationAddress'] ?? ''}',
    );
    final location = Get.find<LocationController>();
    final pickupPoint = LatLng(pickupLatitude, pickupLongitude);
    final destinationPoint = LatLng(destinationLatitude, destinationLongitude);
    location.pickup.value = pickupPoint;
    location.destination.value = destinationPoint;
    location.routePoints.assignAll(<LatLng>[pickupPoint, destinationPoint]);
    location.fromController.text =
        '${ride['pickupDisplayName'] ?? ride['pickupAddress'] ?? 'نقطة الانطلاق'}';
    location.toController.text =
        '${ride['destinationDisplayName'] ?? ride['destinationAddress'] ?? 'الوجهة'}';
    quote.value = RideQuote(
      suggestedPrice: price,
      minPrice: price,
      maxPrice: price,
      priceStep: 1,
      currency: 'YER',
    );
    offeredPrice.value = price;
  }

  Future<void> _loadHomeServices() async {
    final serviceKinds = _serviceKinds;
    if (serviceKinds == null || AppEnvironment.useDemoData) return;
    try {
      final values = await serviceKinds.getServices();
      homeServices.assignAll(values);
      applyAdminDefaultServiceKind();
    } catch (_) {}
  }

  void applyAdminDefaultServiceKind() {
    if (!autoStartTransport.value) return;
    // The catalog and the user's carousel interaction load asynchronously.
    // Never let a late default-service response overwrite a manual choice.
    if (selectedServiceKindId.value != null) return;
    final index =
        homeServices.indexWhere((item) => item.isDefault && item.id != null);
    if (index < 0) return;
    selectHomeService(index);
  }

  /// Commits the home-carousel choice immediately. The route picker can be
  /// opened and revisited before the start button is pressed, so delaying this
  /// state change would otherwise let the previous type's catalog leak into
  /// the vehicle-selection screen.
  void selectHomeService(int index) {
    if (index < 0 || index >= homeServices.length) return;
    final selected = homeServices[index];
    final newKindId = selected.id;
    final kindChanged = selectedServiceKindId.value != newKindId;
    homeServiceIndex.value = index;
    selectedServiceKindId.value = newKindId;
    serviceType.value = selected.code.toLowerCase() == 'delivery'
        ? RideServiceType.delivery
        : RideServiceType.transport;

    if (!kindChanged) return;
    selectedVehicle.value = null;
    hasSelectedTransport.value = false;
    catalogVehicles.clear();
    catalogError.value = '';
    if (newKindId == null) {
      _catalogRequestId++;
      isCatalogLoading.value = false;
      isUsingCatalogFallback.value = AppEnvironment.useDemoData;
      return;
    }
    unawaited(loadServiceCatalog(requestedKindId: newKindId));
  }

  Future<void> setAutoStartTransport(bool value) async {
    autoStartTransport.value = value;
    await RidePreferences.setAutoStartTransport(value);
  }

  List<RideVehicle> get vehicles =>
      isUsingCatalogFallback.value ? _fallbackVehicles : catalogVehicles;

  List<RideVehicleType> get availableVehicleTypes {
    final types = <RideVehicleType>{
      for (final vehicle in vehicles) vehicle.type,
    };
    return RideVehicleType.values.where(types.contains).toList(growable: false);
  }

  List<RideVehicle> get _fallbackVehicles {
    if (serviceType.value != RideServiceType.delivery) {
      return demoRideVehicles;
    }
    final deliveryVehicles = demoRideVehicles
        .where(
          (vehicle) =>
              vehicle.type == RideVehicleType.bike ||
              vehicle.type == RideVehicleType.cycle,
        )
        .toList(growable: false);
    return deliveryVehicles.isEmpty ? demoRideVehicles : deliveryVehicles;
  }

  Future<void> loadServiceCatalog({int? requestedKindId}) async {
    final targetKindId = requestedKindId ?? selectedServiceKindId.value;
    final requestId = ++_catalogRequestId;
    catalogError.value = '';

    if (!_canUseCatalogApi || targetKindId == null) {
      catalogVehicles.clear();
      isUsingCatalogFallback.value = AppEnvironment.useDemoData;
      return;
    }

    isUsingCatalogFallback.value = false;
    isCatalogLoading.value = true;
    try {
      final services = await _catalogRepository!.getServices(
        serviceKindId: targetKindId,
      );
      if (requestId != _catalogRequestId ||
          targetKindId != selectedServiceKindId.value) {
        return;
      }
      // The API already filters by serviceKindId. Keep this additional client
      // guard so a stale or malformed response can never display services
      // belonging to the previously selected kind.
      final matchingServices = services
          .where((service) => service.serviceKindId == targetKindId)
          .toList(growable: false);
      if (matchingServices.isEmpty) {
        catalogVehicles.clear();
        isUsingCatalogFallback.value = false;
        catalogError.value = 'لا توجد خدمات متاحة لهذا النوع حاليًا.';
      } else {
        catalogVehicles.assignAll(matchingServices);
        isUsingCatalogFallback.value = false;
      }
    } catch (_) {
      if (requestId != _catalogRequestId ||
          targetKindId != selectedServiceKindId.value) {
        return;
      }
      catalogVehicles.clear();
      isUsingCatalogFallback.value = AppEnvironment.useDemoData;
      catalogError.value = 'تعذّر تحميل الخدمات، تم عرض الخيارات المحفوظة.';
    } finally {
      if (requestId == _catalogRequestId) {
        isCatalogLoading.value = false;
      }
    }
  }

  bool get _canUseCatalogApi =>
      _catalogRepository != null &&
      AppEnvironment.isConfigured &&
      !AppEnvironment.useDemoData &&
      !AppEnvironment.baseUrl.contains('example.com');

  Set<Marker> nearbyDriverMarkersFor({
    required ValueChanged<NearbyDriver> onTap,
  }) =>
      nearbyDrivers
          .map(
            (driver) => Marker(
              markerId: MarkerId('nearby-${driver.id}'),
              position: LatLng(
                driver.location.latitude,
                driver.location.longitude,
              ),
              anchor: const Offset(.5, 1),
              // A driver marker is an interactive object, not a map point
              // that may be used as the customer's pickup/destination.
              consumeTapEvents: true,
              onTap: () => onTap(driver),
              icon: _nearbyDriverPhotoIcons[driver.id] ??
                  _nearbyDriverIcon.value ??
                  BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  ),
            ),
          )
          .toSet();

  bool get _isTripInProgress =>
      activeRideStatus.value == 'InProgress' || activeRideStatus.value == '5';

  double _carRotationForHeading(double? heading) =>
      ((heading ?? 0) - 90 + 360) % 360;

  Set<Marker> get trackingMarkers => <Marker>{
        if (trackedDriver.value != null)
          Marker(
            markerId: const MarkerId('tracked-driver'),
            position: LatLng(
              trackedDriver.value!.location.latitude,
              trackedDriver.value!.location.longitude,
            ),
            // Material's car glyph faces east at zero rotation. Compensate
            // once here so a GPS heading of 0° (north) renders upright, then
            // keep the vehicle aligned with every real-world bearing.
            rotation: _isTripInProgress
                ? (trackedDriver.value!.heading ?? 0)
                : _carRotationForHeading(trackedDriver.value!.heading),
            flat: true,
            anchor: const Offset(.5, .5),
            infoWindow: InfoWindow(
              title:
                  _isTripInProgress ? 'الرحلة في الطريق' : 'السائق في الطريق',
            ),
            // An approaching car and an active-trip direction marker are
            // intentionally distinct. A profile pin is useful when choosing
            // a driver, but is less clear than a directional vehicle while
            // following a live route.
            icon: (_isTripInProgress
                    ? _inTripDirectionIcon.value
                    : _approachingCarIcon.value) ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
          ),
      };

  /// Removes the already travelled part of the server route. The current
  /// driver position is always the first point, so a delayed route refresh
  /// never makes the blue line appear behind the moving vehicle.
  List<LatLng> get remainingTrackingRoutePoints {
    final driver = trackedDriver.value;
    if (driver == null || trackingRoutePoints.length < 2) {
      return trackingRoutePoints.toList(growable: false);
    }
    final current = LatLng(driver.location.latitude, driver.location.longitude);
    var nearestIndex = 0;
    var nearestMeters = double.infinity;
    for (var index = 0; index < trackingRoutePoints.length; index++) {
      final point = trackingRoutePoints[index];
      final meters = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        point.latitude,
        point.longitude,
      );
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = index;
      }
    }
    // Keep at least one route point in front of the driver. Its final point
    // remains the pickup before the trip and the destination during it.
    final nextIndex =
        math.min(nearestIndex + 1, trackingRoutePoints.length - 1);
    return <LatLng>[current, ...trackingRoutePoints.skip(nextIndex)];
  }

  /// Frames the current live route rather than the customer trip route. While
  /// the driver is on the way this means driver -> pickup; after the trip
  /// starts it becomes driver -> destination. The driver and target are both
  /// included even when the route provider has not returned its polyline yet.
  LatLngBounds? get trackingFocusBounds {
    final driver = trackedDriver.value;
    if (driver == null) return null;
    final location = Get.find<LocationController>();
    final target =
        _isTripInProgress ? location.destination.value : location.pickup.value;
    if (target == null) return null;

    final points = <LatLng>[
      LatLng(driver.location.latitude, driver.location.longitude),
      ...remainingTrackingRoutePoints,
      target,
    ];
    var south = points.first.latitude;
    var north = south;
    var west = points.first.longitude;
    var east = west;
    for (final point in points.skip(1)) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }

    // Google Maps rejects bounds whose two corners are identical. A tiny
    // padding keeps the camera stable when the driver is already at pickup.
    if ((north - south).abs() < .00001) {
      south -= .00001;
      north += .00001;
    }
    if ((east - west).abs() < .00001) {
      west -= .00001;
      east += .00001;
    }
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  Set<Polyline> get trackingPolylines {
    final points = remainingTrackingRoutePoints;
    if (points.length < 2) return const <Polyline>{};
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('assigned-driver-route'),
        points: points,
        width: 6,
        color: const ui.Color(0xFF1A73E8),
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  Future<void> loadNearbyDrivers({LatLng? center}) async {
    final location = Get.find<LocationController>();
    final origin = center ?? location.pickup.value;
    if (origin == null) {
      nearbyDrivers.clear();
      return;
    }
    if (AppEnvironment.useDemoData) {
      loadDemoNearbyDrivers(center: origin);
      return;
    }
    final requestId = ++_nearbyDriversRequestId;
    try {
      final selected = selectedVehicle.value;
      final drivers = await _repository.getNearbyDrivers(
        pickup: RideCoordinate(
          latitude: origin.latitude,
          longitude: origin.longitude,
        ),
        serviceKindId: selected?.serviceKindId ?? selectedServiceKindId.value,
        serviceCatalogItemId: selected?.serviceCatalogItemId,
      );
      if (requestId != _nearbyDriversRequestId) return;
      nearbyDrivers.assignAll(drivers);
      unawaited(_loadDemoDriverIcon());
      for (final driver in drivers) {
        unawaited(_loadDriverPhotoMarker(driver));
      }
    } catch (_) {
      // Do not retain markers belonging to an old pickup after the server
      // query fails. A later pickup change or return to this screen retries.
      if (requestId == _nearbyDriversRequestId) nearbyDrivers.clear();
    }
  }

  void loadDemoNearbyDrivers({LatLng? center}) {
    _loadDemoDriverIcon();
    final location = Get.find<LocationController>();
    final origin = center ?? location.pickup.value;
    if (origin == null) {
      nearbyDrivers.clear();
      return;
    }
    // Keep demo drivers deterministic and close enough to fit in one map view.
    final distancesKm = <double>[.18, .32, .48, .65, .82, 1.0, 1.18, 1.4];
    final bearings = <double>[0, 45, 90, 135, 180, 225, 270, 315];
    LatLng nearbyPoint(int index) {
      final distanceMeters = distancesKm[index] * 1000;
      final bearing = bearings[index] * math.pi / 180;
      final latitudeDelta = distanceMeters * math.cos(bearing) / 111320.0;
      final longitudeScale = 111320.0 *
          math.cos(origin.latitude * math.pi / 180).abs().clamp(.2, 1.0);
      final longitudeDelta =
          distanceMeters * math.sin(bearing) / longitudeScale;
      return LatLng(
        origin.latitude + latitudeDelta,
        origin.longitude + longitudeDelta,
      );
    }

    nearbyDrivers.assignAll(<NearbyDriver>[
      NearbyDriver(
        id: 'nearby-1',
        name: 'محمد علي',
        location: RideCoordinate(
          latitude: nearbyPoint(0).latitude,
          longitude: nearbyPoint(0).longitude,
        ),
        photoUrl: '',
        vehicleType: RideVehicleType.car,
        rating: 4.9,
        vehicleModel: 'Toyota Yaris 2023',
        plateNumber: '01 - 45872',
        completedTrips: 1248,
      ),
      NearbyDriver(
        id: 'nearby-2',
        name: 'أحمد صالح',
        location: RideCoordinate(
          latitude: nearbyPoint(1).latitude,
          longitude: nearbyPoint(1).longitude,
        ),
        photoUrl: '',
        vehicleType: RideVehicleType.taxi,
        rating: 4.8,
        vehicleModel: 'Hyundai Accent 2022',
        plateNumber: '01 - 79314',
        completedTrips: 936,
      ),
      NearbyDriver(
        id: 'nearby-3',
        name: 'عبدالله حسن',
        location: RideCoordinate(
          latitude: nearbyPoint(2).latitude,
          longitude: nearbyPoint(2).longitude,
        ),
        photoUrl: '',
        vehicleType: RideVehicleType.car,
        rating: 4.7,
        vehicleModel: 'Kia Rio 2021',
        plateNumber: '01 - 32689',
        completedTrips: 711,
      ),
      NearbyDriver(
        id: 'nearby-4',
        name: 'خالد محمد',
        location: RideCoordinate(
          latitude: nearbyPoint(3).latitude,
          longitude: nearbyPoint(3).longitude,
        ),
        photoUrl: '',
        vehicleType: RideVehicleType.taxi,
        rating: 4.6,
        vehicleModel: 'Toyota Corolla 2022',
        plateNumber: '01 - 61428',
        completedTrips: 602,
      ),
      NearbyDriver(
        id: 'nearby-5',
        name: 'سامر أحمد',
        location: RideCoordinate(
          latitude: nearbyPoint(4).latitude,
          longitude: nearbyPoint(4).longitude,
        ),
        photoUrl: '',
        vehicleType: RideVehicleType.car,
        rating: 4.5,
        vehicleModel: 'Hyundai Elantra 2021',
        plateNumber: '01 - 78215',
        completedTrips: 488,
      ),
      NearbyDriver(
        id: 'nearby-6',
        name: 'مازن علي',
        location: RideCoordinate(
          latitude: nearbyPoint(5).latitude,
          longitude: nearbyPoint(5).longitude,
        ),
        photoUrl: '',
        vehicleType: RideVehicleType.car,
        rating: 4.4,
        vehicleModel: 'Kia Cerato 2020',
        plateNumber: '01 - 29541',
        completedTrips: 371,
      ),
      NearbyDriver(
        id: 'nearby-7',
        name: 'ياسر عبدالله',
        location: RideCoordinate(
          latitude: nearbyPoint(6).latitude,
          longitude: nearbyPoint(6).longitude,
        ),
        photoUrl: '',
        vehicleType: RideVehicleType.taxi,
        rating: 4.3,
        vehicleModel: 'Suzuki Dzire 2022',
        plateNumber: '01 - 83672',
        completedTrips: 295,
      ),
      NearbyDriver(
        id: 'nearby-8',
        name: 'فارس حسن',
        location: RideCoordinate(
          latitude: nearbyPoint(7).latitude,
          longitude: nearbyPoint(7).longitude,
        ),
        photoUrl: '',
        vehicleType: RideVehicleType.car,
        rating: 4.2,
        vehicleModel: 'Toyota Vitz 2020',
        plateNumber: '01 - 94713',
        completedTrips: 214,
      ),
    ]);
  }

  void closeNearbyDriverCard() => selectedNearbyDriver.value = null;

  void selectNearbyDriver(NearbyDriver driver) {
    if (selectedNearbyDriver.value?.id == driver.id) return;
    selectedNearbyDriver.value = driver;
  }

  Future<void> _loadDemoDriverIcon() async {
    try {
      final bytes = await rootBundle.load(
        'assets/images/branding/yemen_drive_logo.png',
      );
      final icon = await _buildDriverMarkerIcon(bytes.buffer.asUint8List());
      if (icon != null) _nearbyDriverIcon.value = icon;
    } catch (_) {}
  }

  Future<void> _loadDriverPhotoMarker(NearbyDriver driver) async {
    await _loadDriverPhotoMarkerById(driver.id, driver.photoUrl);
  }

  Future<void> _loadTrackingIcons() async {
    _approachingCarIcon.value =
        await _buildTrackingMarkerIcon(isTripInProgress: false);
    _inTripDirectionIcon.value =
        await _buildTrackingMarkerIcon(isTripInProgress: true);
  }

  /// Both icons point north in their source canvas. Google Maps applies the
  /// driver's live heading through [Marker.rotation], so the same icon is
  /// correctly oriented in every direction without a new bitmap per update.
  Future<BitmapDescriptor?> _buildTrackingMarkerIcon({
    required bool isTripInProgress,
  }) async {
    try {
      const logicalSize = 52.0;
      const pixelRatio = 3.0;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()..isAntiAlias = true;
      canvas.scale(pixelRatio, pixelRatio);
      const center = ui.Offset(logicalSize / 2, logicalSize / 2);

      if (isTripInProgress) {
        // Layered glow, shadow and a crisp Material navigation glyph make
        // this visually close to a modern turn-by-turn navigation marker.
        canvas.drawCircle(
          center,
          25,
          paint..color = const ui.Color(0x241A73E8),
        );
        canvas.drawCircle(
          center.translate(0, 2.5),
          20.5,
          paint..color = const ui.Color(0x38000000),
        );
        canvas.drawCircle(
          center,
          20,
          paint
            ..shader = ui.Gradient.radial(
              center.translate(-5, -6),
              30,
              const <ui.Color>[
                ui.Color(0xFF79C7FF),
                ui.Color(0xFF1A73E8),
                ui.Color(0xFF0B4FA4),
              ],
              const <double>[0, .62, 1],
            ),
        );
        paint.shader = null;
        canvas.drawCircle(
          center,
          15.2,
          paint..color = const ui.Color(0xFFFFFFFF),
        );
        _paintMaterialIcon(
          canvas,
          iconCodePoint: Icons.navigation_rounded.codePoint,
          fontFamily: Icons.navigation_rounded.fontFamily,
          fontPackage: Icons.navigation_rounded.fontPackage,
          center: center.translate(.5, .5),
          size: 25,
          color: const ui.Color(0xFF1478E9),
        );
      } else {
        // The Material car is compact and recognisable even at map scale.
        // A soft cyan halo and a white circular plate separate it clearly
        // from the route without becoming another oversized pin.
        canvas.drawCircle(
          center,
          24,
          paint..color = const ui.Color(0x1E00B8FF),
        );
        canvas.drawCircle(
          center.translate(0, 2),
          18.5,
          paint..color = const ui.Color(0x35000000),
        );
        canvas.drawCircle(
          center,
          18,
          paint..color = const ui.Color(0xFFFFFFFF),
        );
        canvas.drawCircle(
          center,
          16.2,
          paint
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const ui.Color(0xFF32A9F4),
        );
        paint.style = ui.PaintingStyle.fill;
        // The car glyph faces east by design. Its GPS-bearing compensation is
        // applied at Marker.rotation, where it remains correct while moving.
        _paintMaterialIcon(
          canvas,
          iconCodePoint: Icons.directions_car_filled_rounded.codePoint,
          fontFamily: Icons.directions_car_filled_rounded.fontFamily,
          fontPackage: Icons.directions_car_filled_rounded.fontPackage,
          center: center,
          size: 25,
          color: const ui.Color(0xFF126EBD),
        );
      }
      final image = await recorder.endRecording().toImage(
            (logicalSize * pixelRatio).round(),
            (logicalSize * pixelRatio).round(),
          );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return BitmapDescriptor.bytes(
        Uint8List.sublistView(data),
        imagePixelRatio: pixelRatio,
      );
    } catch (_) {
      return null;
    }
  }

  void _paintMaterialIcon(
    ui.Canvas canvas, {
    required int iconCodePoint,
    required String? fontFamily,
    required String? fontPackage,
    required ui.Offset center,
    required double size,
    required ui.Color color,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconCodePoint),
        style: TextStyle(
          fontFamily: fontFamily,
          package: fontPackage,
          fontSize: size,
          foreground: ui.Paint()
            ..isAntiAlias = true
            ..color = color,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      ui.Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  Future<void> _loadDriverPhotoMarkerById(
    String driverId,
    String photoUrl,
  ) async {
    final normalizedId = driverId.trim();
    final normalizedPhotoUrl = photoUrl.trim();
    if (normalizedId.isEmpty ||
        normalizedPhotoUrl.isEmpty ||
        _nearbyDriverPhotoIcons.containsKey(normalizedId)) return;
    try {
      final uri = Uri.tryParse(normalizedPhotoUrl);
      if (uri == null || !uri.hasScheme) return;
      final bytes = await NetworkAssetBundle(uri).load('');
      final icon = await _buildDriverMarkerIcon(bytes.buffer.asUint8List());
      if (icon != null) _nearbyDriverPhotoIcons[normalizedId] = icon;
    } catch (_) {
      // A missing profile image must not hide the driver marker.
    }
  }

  Future<BitmapDescriptor?> _buildDriverMarkerIcon(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 48,
        targetHeight: 48,
      );
      final frame = await codec.getNextFrame();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()..isAntiAlias = true;
      canvas.scale(
        _driverMarkerWidth / _driverMarkerBaseWidth,
        _driverMarkerHeight / _driverMarkerBaseHeight,
      );

      final shadowPath = _driverMarkerPath(const ui.Offset(0, 3));
      canvas.drawPath(
        shadowPath,
        ui.Paint()
          ..isAntiAlias = true
          ..color = const ui.Color(0x45000000),
      );

      final markerPath = _driverMarkerPath(ui.Offset.zero);
      canvas.drawPath(
        markerPath,
        paint..color = const ui.Color(0xFFFFA000),
      );
      canvas.drawPath(
        markerPath,
        ui.Paint()
          ..isAntiAlias = true
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const ui.Color(0xFFFFFFFF),
      );

      const photoBounds = ui.Rect.fromLTWH(7, 6, 42, 42);
      canvas.drawOval(
        photoBounds.inflate(3),
        ui.Paint()
          ..isAntiAlias = true
          ..color = const ui.Color(0xFFFFFFFF),
      );
      canvas.save();
      canvas.clipPath(ui.Path()..addOval(photoBounds));
      canvas.drawImageRect(
        frame.image,
        ui.Rect.fromLTWH(
          0,
          0,
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        ),
        photoBounds,
        paint,
      );
      canvas.restore();
      final image = await recorder.endRecording().toImage(
            _driverMarkerWidth,
            _driverMarkerHeight,
          );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) {
        return BitmapDescriptor.bytes(
          Uint8List.sublistView(data),
          imagePixelRatio: _driverMarkerPixelRatio,
        );
      }
    } catch (_) {}
    return null;
  }

  ui.Path _driverMarkerPath(ui.Offset offset) => ui.Path()
    ..moveTo(28 + offset.dx, 68 + offset.dy)
    ..cubicTo(
      24 + offset.dx,
      62 + offset.dy,
      2 + offset.dx,
      52 + offset.dy,
      2 + offset.dx,
      30 + offset.dy,
    )
    ..cubicTo(
      2 + offset.dx,
      14 + offset.dy,
      13 + offset.dx,
      3 + offset.dy,
      28 + offset.dx,
      3 + offset.dy,
    )
    ..cubicTo(
      43 + offset.dx,
      3 + offset.dy,
      54 + offset.dx,
      14 + offset.dy,
      54 + offset.dx,
      30 + offset.dy,
    )
    ..cubicTo(
      54 + offset.dx,
      52 + offset.dy,
      32 + offset.dx,
      62 + offset.dy,
      28 + offset.dx,
      68 + offset.dy,
    )
    ..close();

  void startDemoTracking() {
    _trackingTimer?.cancel();
    final location = Get.find<LocationController>();
    final points = location.routePoints.isNotEmpty
        ? location.routePoints.toList(growable: false)
        : <LatLng>[
            location.pickup.value ?? const LatLng(15.3694, 44.1910),
            location.destination.value ?? const LatLng(15.3567, 44.2066),
          ];
    var index = 0;
    trackedPassenger.value = RideCoordinate(
      latitude: points.first.latitude,
      longitude: points.first.longitude,
    );
    _startPassengerPositionTracking();
    _trackingTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (points.isEmpty) return;
      final point = points[index.clamp(0, points.length - 1)];
      trackedDriver.value = DriverTrackingSnapshot(
        driverId: 'demo-driver',
        location: RideCoordinate(
          latitude: point.latitude,
          longitude: point.longitude,
        ),
        heading:
            index + 1 < points.length ? _bearing(point, points[index + 1]) : 0,
        updatedAt: DateTime.now(),
      );
      trackedPassenger.value = RideCoordinate(
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (index < points.length - 1) index++;
    });
  }

  Future<void> _startPassengerPositionTracking() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      await _passengerPositionSubscription?.cancel();
      _passengerPositionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      ).listen((position) {
        final current = RideCoordinate(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        trackedPassenger.value = current;
        final rideId = _requestId;
        final now = DateTime.now();
        if (!AppEnvironment.useDemoData &&
            rideId != null &&
            (_lastPassengerLocationPublished == null ||
                now.difference(_lastPassengerLocationPublished!) >=
                    const Duration(seconds: 8))) {
          _lastPassengerLocationPublished = now;
          unawaited(_repository.publishPassengerLocation(
            rideId,
            current,
            bearing: position.heading,
            speed: position.speed,
          ));
        }
      });
    } catch (_) {
      // Demo tracking remains active when a device does not provide location.
    }
  }

  double _bearing(LatLng from, LatLng to) {
    final deltaLongitude = to.longitude - from.longitude;
    return (deltaLongitude >= 0 ? 90 : 270).toDouble();
  }

  void selectService(RideServiceType value) {
    // The catalog is loaded once during controller initialization and again
    // only when the selected service type actually changes. Views consume the
    // cached [catalogVehicles] through [vehicles] and never call the API.
    if (serviceType.value == value) return;
    serviceType.value = value;
    catalogVehicles.clear();
    selectedVehicle.value = null;
    hasSelectedTransport.value = false;
    unawaited(loadServiceCatalog());
  }

  Future<void> startHomeService() async {
    // A controller may remain alive after a cancellation or while an open
    // ride is being restored. Do not let a new booking screen reuse that
    // ride's id and make the customer believe the new quote was sent.
    if (_requestId != null) {
      Get.snackbar(
        'لديك رحلة مفتوحة',
        'أكمل الرحلة الحالية أو ألغها قبل إنشاء طلب جديد.',
      );
      if (isDriverAssigned.value) {
        Get.toNamed<void>(RideRoutes.driverLocation);
      } else {
        Get.toNamed<void>(RideRoutes.negotiationQuote);
      }
      return;
    }
    final connectivity = Get.find<ConnectivityService>();
    if (!await connectivity.refresh()) {
      Get.snackbar(
        'لا يوجد اتصال بالإنترنت',
        'اتصل بالإنترنت ثم حاول اختيار الخدمة مرة أخرى.',
      );
      return;
    }
    if (AppEnvironment.useDemoData) loadDemoNearbyDrivers();
    hasSelectedTransport.value = false;
    final selected = homeServiceIndex.value >= 0 &&
            homeServiceIndex.value < homeServices.length
        ? homeServices[homeServiceIndex.value]
        : null;
    if (selected?.id != null) {
      selectHomeService(homeServiceIndex.value);
      Get.toNamed<void>(RideRoutes.locationPicker);
    } else if (selected != null) {
      Get.snackbar(selected.name, 'هذا النوع سيُتاح قريبًا.');
    } else {
      switch (homeServiceIndex.value) {
        case 0:
          selectService(RideServiceType.transport);
          Get.toNamed<void>(RideRoutes.locationPicker);
        case 1:
          selectService(RideServiceType.delivery);
          Get.toNamed<void>(RideRoutes.locationPicker);
        case 2:
          Get.toNamed<void>(RideRoutes.locationPicker);
        case 3:
          Get.toNamed<void>(RideRoutes.locationPicker);
        default:
          Get.snackbar('اختر الخدمة', 'حدد نوع الخدمة أولًا للمتابعة.');
      }
    }
  }

  void chooseTransport(RideVehicleType value) {
    selectedTransport.value = value;
    hasSelectedTransport.value = true;
  }

  /// Selects a catalog item returned by the API while keeping the existing
  /// vehicle-type contract used by quote/request endpoints.
  void chooseCatalogVehicle(RideVehicle vehicle) {
    selectedVehicle.value = vehicle;
    chooseTransport(vehicle.type);
  }

  Future<void> selectCatalogVehicle(RideVehicle vehicle) async {
    chooseCatalogVehicle(vehicle);
    await _quoteForSelection(vehicle);
  }

  Future<void> selectTransport(RideVehicleType value) async {
    RideVehicle? vehicle = selectedVehicle.value;
    if (vehicle == null) {
      for (final item in vehicles) {
        if (item.type == value) {
          vehicle = item;
          break;
        }
      }
    }
    if (vehicle == null) {
      Get.snackbar('الخدمة غير مكتملة', 'اختر خدمة من القائمة أولاً.');
      return;
    }
    await _quoteForSelection(vehicle);
  }

  Future<void> _quoteForSelection(RideVehicle vehicle) async {
    if (vehicle.serviceKindId == null || vehicle.serviceCatalogItemId == null) {
      Get.snackbar('الخدمة غير مكتملة', 'بيانات الخدمة غير متاحة من الخادم.');
      return;
    }
    final location = Get.find<LocationController>();
    final pickupPoint = location.pickup.value;
    final destinationPoint = location.destination.value;
    if (pickupPoint == null || destinationPoint == null) {
      Get.snackbar('المسار غير مكتمل', 'حدد نقطة الانطلاق والوجهة أولًا.');
      return;
    }
    chooseCatalogVehicle(vehicle);
    final requestId = ++_quoteRequestId;
    quote.value = null;
    quoteError.value = '';
    negotiationStatus.value = NegotiationStatus.quoting;
    Get.toNamed<void>(RideRoutes.negotiationQuote);

    try {
      final routeDistance = location.routeDistanceMeters.value > 0
          ? location.routeDistanceMeters.value / 1000
          : _routeDistanceKm(
              location.routePoints,
              pickupPoint,
              destinationPoint,
            );
      routeDistanceKm.value = routeDistance;
      final result = await _repository.getQuote(
        serviceKindId: vehicle.serviceKindId!,
        serviceCatalogItemId: vehicle.serviceCatalogItemId!,
        pickup: RideCoordinate(
          latitude: pickupPoint.latitude,
          longitude: pickupPoint.longitude,
        ),
        destination: RideCoordinate(
          latitude: destinationPoint.latitude,
          longitude: destinationPoint.longitude,
        ),
        distanceKm: routeDistance,
        durationMinutes: location.routeDurationSeconds.value > 0
            ? location.routeDurationSeconds.value / 60
            : 0,
      );
      if (requestId != _quoteRequestId) return;
      quote.value = result;
      offeredPrice.value = result.suggestedPrice;
      negotiationStatus.value = NegotiationStatus.ready;
    } on FormatException catch (error) {
      if (requestId != _quoteRequestId) return;
      quoteError.value = error.message.toString().isEmpty
          ? 'تعذر احتساب السعر لهذه الخدمة. تحقق من قاعدة التسعير.'
          : error.message.toString();
      negotiationStatus.value = NegotiationStatus.idle;
    } catch (_) {
      if (requestId != _quoteRequestId) return;
      quoteError.value = 'تعذر احتساب السعر الآن. حاول مرة أخرى.';
      negotiationStatus.value = NegotiationStatus.idle;
    }
  }

  /// Stops an unfinished quote when the customer leaves its screen. A delayed
  /// network result must never revive the spinner or change a previous page.
  void cancelPendingQuote() {
    _quoteRequestId++;
    if (negotiationStatus.value == NegotiationStatus.quoting) {
      negotiationStatus.value = NegotiationStatus.idle;
    }
  }

  void increasePrice() => _changePrice(1);
  void decreasePrice() => _changePrice(-1);

  void _changePrice(int direction) {
    final value = quote.value;
    if (value == null) return;
    offeredPrice.value = (offeredPrice.value + value.priceStep * direction)
        .clamp(value.minPrice, value.maxPrice)
        .toDouble();
  }

  Future<void> resumePendingRequestIfNeeded() async {
    final arguments = Get.arguments;
    final shouldResume = arguments is Map && arguments['resumeRequest'] == true;
    if (!shouldResume ||
        !_session.isAuthenticated.value ||
        _isResumingRequest) {
      return;
    }
    _isResumingRequest = true;
    if (quote.value == null) {
      final location = Get.find<LocationController>();
      final pickup = location.pickup.value;
      final destination = location.destination.value;
      if (pickup == null || destination == null) return;
      final vehicle = selectedVehicle.value;
      if (vehicle == null) return;
      await _quoteForSelection(vehicle);
    }
    await requestRide();
  }

  void selectVehicle(RideVehicle vehicle) {
    selectedVehicle.value = vehicle;
    Get.toNamed<void>(RideRoutes.vehicleDetails);
  }

  Future<void> requestRide({bool later = false}) async {
    if (!_session.requireAuthentication(
      returnRoute: RideRoutes.negotiationQuote,
      arguments: <String, Object?>{'resumeRequest': true},
    )) {
      return;
    }
    final location = Get.find<LocationController>();
    final pickupPoint = location.pickup.value;
    final destinationPoint = location.destination.value;
    if (pickupPoint == null || destinationPoint == null) {
      Get.snackbar('المسار غير مكتمل', 'حدد نقطة الانطلاق والوجهة أولًا.');
      return;
    }
    if (quote.value == null) {
      await selectTransport(selectedTransport.value);
      if (quote.value == null) return;
    }
    final pickupAddress = location.fromController.text.trim();
    final destinationAddress = location.toController.text.trim();
    final draft = RideRequestDraft(
      customerId: _session.currentUserId.value,
      pickup: location.pickupArea.value.trim().isEmpty
          ? 'منطقة الانطلاق المحددة'
          : location.pickupArea.value.trim(),
      destination: location.destinationArea.value.trim().isNotEmpty
          ? location.destinationArea.value.trim()
          : (location.addressNameController.text.trim().isEmpty
              ? 'منطقة الوجهة المحددة'
              : location.addressNameController.text.trim()),
      pickupCoordinate: RideCoordinate(
        latitude: pickupPoint.latitude,
        longitude: pickupPoint.longitude,
      ),
      destinationCoordinate: RideCoordinate(
        latitude: destinationPoint.latitude,
        longitude: destinationPoint.longitude,
      ),
      serviceKindId: selectedVehicle.value?.serviceKindId ??
          selectedServiceKindId.value ??
          0,
      serviceCatalogItemId: selectedVehicle.value?.serviceCatalogItemId ?? 0,
      offeredPrice: offeredPrice.value,
      // During development the map provider may supply coordinates before a
      // human-readable address. The API requires both address fields, so keep
      // the selected route usable without inventing a real address.
      pickupAddress:
          pickupAddress.isEmpty ? 'نقطة الانطلاق المحددة' : pickupAddress,
      destinationAddress:
          destinationAddress.isEmpty ? 'الوجهة المحددة' : destinationAddress,
      destinationAddressName: location.addressNameController.text.trim(),
      destinationStreet: location.streetController.text.trim(),
      destinationDetails: location.detailsController.text.trim(),
      routeDistanceMeters: (routeDistanceKm.value * 1000).round(),
      routeDurationSeconds: location.routeDurationSeconds.value > 0
          ? location.routeDurationSeconds.value
          : null,
      idempotencyKey: DateTime.now().microsecondsSinceEpoch.toString(),
    );
    currentDraft.value = draft;
    try {
      _requestId = await _repository.createRequest(draft);
    } on FormatException catch (error) {
      // Keep diagnostic output limited to non-sensitive matching identifiers.
      debugPrint(
        'Ride request rejected: kind=${draft.serviceKindId}, '
        'service=${draft.serviceCatalogItemId}, reason=${error.message}',
      );
      currentDraft.value = null;
      _requestId = null;
      Get.snackbar('تعذر إرسال الطلب', error.message);
      return;
    }

    isSearchingForDriver.value = true;
    hasShownTripSharePrompt = false;
    offersExhausted.value = false;
    offersStreamDone.value = false;
    receivedOffersCount.value = 0;
    requestRecipients.clear();
    _recipientTimer?.cancel();
    var recipientIndex = 0;
    _recipientTimer =
        Timer.periodic(const Duration(milliseconds: 1300), (timer) {
      if (!isSearchingForDriver.value ||
          recipientIndex >= nearbyDrivers.length) {
        timer.cancel();
        return;
      }
      requestRecipients.add(nearbyDrivers[recipientIndex++]);
    });
    removingOfferIds.clear();
    negotiationStatus.value = NegotiationStatus.searching;
    driverOffers.clear();
    await _watchOffers(_requestId!);
  }

  Future<void> _watchOffers(String requestId) async {
    await _offersSubscription?.cancel();
    _offersSubscription = _repository.watchOffers(requestId).listen(
      (offer) {
        offersExhausted.value = false;
        receivedOffersCount.value++;
        driverOffers.add(offer);
      },
      onError: (_) {
        _recipientTimer?.cancel();
        isSearchingForDriver.value = false;
        Get.snackbar('تعذر استلام العروض', 'حاول إرسال الطلب مرة أخرى.');
      },
      onDone: () {
        offersStreamDone.value = true;
        _updateOffersExhausted();
      },
    );
  }

  Future<void> acceptOffer(DriverOffer offer) async {
    final requestId = _requestId;
    if (requestId == null) return;
    try {
      await _repository.acceptOffer(requestId, offer.id);
    } on FormatException catch (error) {
      Get.snackbar('تعذر قبول العرض', error.message);
      return;
    }
    acceptedOffer.value = offer;
    driverOffers.assignAll(
      driverOffers.map(
        (item) => item.copyWith(
          status: item.id == offer.id
              ? DriverOfferStatus.accepted
              : DriverOfferStatus.rejected,
        ),
      ),
    );
    negotiationStatus.value = NegotiationStatus.accepted;
    activeRideStatus.value = 'DriverAssigned';
    driverFound();
  }

  Future<void> rejectOffer(DriverOffer offer) async {
    final requestId = _requestId;
    if (requestId == null) return;
    await _repository.rejectOffer(requestId, offer.id);
    _dismissOffer(offer.id);
  }

  void expireOffer(DriverOffer offer) {
    final index = driverOffers.indexWhere((item) => item.id == offer.id);
    if (index < 0 || driverOffers[index].status != DriverOfferStatus.pending) {
      return;
    }
    _dismissOffer(offer.id);
  }

  void _dismissOffer(String offerId) {
    if (!driverOffers.any((offer) => offer.id == offerId) ||
        removingOfferIds.contains(offerId)) {
      return;
    }
    removingOfferIds.add(offerId);
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      driverOffers.removeWhere((offer) => offer.id == offerId);
      removingOfferIds.remove(offerId);
      _updateOffersExhausted();
    });
  }

  void _updateOffersExhausted() {
    offersExhausted.value = offersStreamDone.value && driverOffers.isEmpty;
    if (offersExhausted.value) {
      _recipientTimer?.cancel();
      isSearchingForDriver.value = false;
    }
  }

  void acknowledgeOffersExhausted() => offersExhausted.value = false;

  Future<void> retryDriverSearch() async {
    offersExhausted.value = false;
    offersStreamDone.value = false;
    final requestId = _requestId;
    if (requestId == null) {
      await requestRide();
      return;
    }

    // Retry observes the same still-open ride. Creating a fresh request here
    // would duplicate a trip every time the offer polling window ends.
    isSearchingForDriver.value = true;
    receivedOffersCount.value = 0;
    removingOfferIds.clear();
    driverOffers.clear();
    await _watchOffers(requestId);
  }

  Future<void> cancelDriverSearch() async {
    final requestId = _requestId;
    const reason = 'ألغى المستخدم البحث عن سائق';
    if (requestId != null) await _repository.requestCancellation(requestId, reason);
    offersExhausted.value = false;
    driverOffers.clear();
    requestRecipients.clear();
    _recipientTimer?.cancel();
    isSearchingForDriver.value = false;
    cancelRide(reason);
  }

  Future<void> cancelActiveRide(String reason) async {
    final requestId = _requestId;
    if (requestId == null || reason.trim().length < 3) {
      Get.snackbar('سبب الإلغاء مطلوب', 'حدد سبباً واضحاً قبل إرسال طلب الإلغاء.');
      return;
    }
    try {
      await _repository.requestCancellation(requestId, reason.trim());
    } catch (_) {
      Get.snackbar('تعذر إرسال الطلب', 'لم يُرسل طلب الإلغاء. تحقق من الاتصال ثم حاول مرة أخرى.');
      return;
    }
    _trackingTimer?.cancel();
    await _passengerPositionSubscription?.cancel();
    trackedDriver.value = null;
    trackedPassenger.value = null;
    isDriverAssigned.value = false;
    acceptedOffer.value = null;
    cancelRide(reason);
  }

  void driverFound() {
    _recipientTimer?.cancel();
    isSearchingForDriver.value = false;
    isDriverAssigned.value = true;
    if (AppEnvironment.useDemoData) startDemoTracking();
    if (!AppEnvironment.useDemoData) startRealTracking();
    Get.offNamed<void>(RideRoutes.driverLocation);
  }

  void startRealTracking() {
    _trackingTimer?.cancel();
    unawaited(refreshActiveRide());
    unawaited(_startPassengerPositionTracking());
    _trackingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(refreshActiveRide());
    });
  }

  Future<void> refreshActiveRide() async {
    final rideId = _requestId;
    if (rideId == null) return;
    try {
      final detail = await _repository.getRideDetail(rideId);
      final ride = detail['ride'];
      if (ride is Map) {
        activeRideStatus.value = '${ride['status'] ?? ''}';
      }
      final approval = detail['cashCollectionApproval'];
      cashCollectionApproval.value =
          approval is Map ? Map<String, Object?>.from(approval) : null;
      final driver = detail['driver'];
      if (driver is Map) {
        final driverValues = Map<Object?, Object?>.from(driver);
        assignedDriverName.value = '${driverValues['name'] ?? ''}'.trim();
        assignedDriverPhone.value =
            '${driverValues['phoneNumber'] ?? ''}'.trim();
        final driverId =
            '${driverValues['id'] ?? driverValues['driverId'] ?? ''}'.trim();
        final photoUrl = '${driverValues['photoUrl'] ?? ''}'.trim();
        if (driverId.isNotEmpty && photoUrl.isNotEmpty) {
          unawaited(_loadDriverPhotoMarkerById(driverId, photoUrl));
        }
      }
      final location = detail['driverLocation'];
      if (location is Map) {
        final values = Map<Object?, Object?>.from(location);
        final latitude = _asDouble(values['latitude']);
        final longitude = _asDouble(values['longitude']);
        if (latitude != null && longitude != null) {
          trackedDriver.value = DriverTrackingSnapshot(
            driverId: '${values['driverId'] ?? ''}',
            location: RideCoordinate(latitude: latitude, longitude: longitude),
            heading: _asDouble(values['bearing']),
            updatedAt: DateTime.tryParse('${values['observedAtUtc'] ?? ''}') ??
                DateTime.now(),
          );
          unawaited(_refreshAssignedDriverRoute());
        }
      }
    } catch (_) {
      // Keep the last confirmed marker visible during a transient network failure.
    }
  }

  Future<void> _refreshAssignedDriverRoute() async {
    final routeRepository = _routeRepository;
    final driver = trackedDriver.value;
    final location = Get.find<LocationController>();
    if (routeRepository == null || driver == null) return;

    final status = activeRideStatus.value;
    final target = status == 'InProgress' || status == '5'
        ? location.destination.value
        : location.pickup.value;
    if (target == null) return;

    final origin = driver.location;
    final targetCoordinate = RideCoordinate(
      latitude: target.latitude,
      longitude: target.longitude,
    );
    final requestedRecently = _lastTrackingRouteRequestedAt != null &&
        DateTime.now().difference(_lastTrackingRouteRequestedAt!) <
            const Duration(seconds: 45);
    final originChanged = _lastTrackingRouteOrigin == null ||
        Geolocator.distanceBetween(
              _lastTrackingRouteOrigin!.latitude,
              _lastTrackingRouteOrigin!.longitude,
              origin.latitude,
              origin.longitude,
            ) >=
            30;
    final targetChanged = _lastTrackingRouteDestination == null ||
        Geolocator.distanceBetween(
              _lastTrackingRouteDestination!.latitude,
              _lastTrackingRouteDestination!.longitude,
              targetCoordinate.latitude,
              targetCoordinate.longitude,
            ) >=
            10;
    if (!originChanged && !targetChanged && requestedRecently) return;

    _lastTrackingRouteOrigin = origin;
    _lastTrackingRouteDestination = targetCoordinate;
    _lastTrackingRouteRequestedAt = DateTime.now();
    final requestId = ++_trackingRouteRequestId;
    try {
      final route = await routeRepository.getDrivingRoute(
        origin: LatLng(origin.latitude, origin.longitude),
        destination: target,
      );
      if (requestId == _trackingRouteRequestId) {
        trackingRoutePoints.assignAll(route.points);
      }
    } catch (_) {
      // Retain the last confirmed route during a temporary maps failure.
    }
  }

  double? _asDouble(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('${value ?? ''}');

  int? _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? ''}');

  double _routeDistanceKm(
    List<LatLng> routePoints,
    LatLng pickup,
    LatLng destination,
  ) {
    final points =
        routePoints.length >= 2 ? routePoints : <LatLng>[pickup, destination];
    var meters = 0.0;
    for (var index = 1; index < points.length; index++) {
      meters += Geolocator.distanceBetween(
        points[index - 1].latitude,
        points[index - 1].longitude,
        points[index].latitude,
        points[index].longitude,
      );
    }
    return meters / 1000;
  }

  void cancelRide(String reason) {
    _recipientTimer?.cancel();
    _offersSubscription?.cancel();
    _requestId = null;
    currentDraft.value = null;
    quote.value = null;
    driverOffers.clear();
    requestRecipients.clear();
    acceptedOffer.value = null;
    isDriverAssigned.value = false;
    trackingRoutePoints.clear();
    _lastTrackingRouteOrigin = null;
    _lastTrackingRouteDestination = null;
    _lastTrackingRouteRequestedAt = null;
    _trackingRouteRequestId++;
    activeRideStatus.value = '';
    cashCollectionApproval.value = null;
    cancellationReason.value = reason;
    isSearchingForDriver.value = false;
    Get.offNamed<void>(RideRoutes.requestThanks);
  }

  void updateBottomNavigation(int index) {
    if (bottomNavigationIndex.value == index) return;
    final route = switch (index) {
      0 => RideRoutes.homeTransport,
      1 => autoStartTransport.value
          ? RideRoutes.homeTransport
          : AccountRoutes.favourites,
      2 => AccountRoutes.wallet,
      3 => AccountRoutes.offers,
      _ => AccountRoutes.profile,
    };
    if (index != 0 && !_session.requireAuthentication(returnRoute: route)) {
      return;
    }
    bottomNavigationIndex.value = index;
  }

  @override
  void onClose() {
    _offersSubscription?.cancel();
    _trackingTimer?.cancel();
    _recipientTimer?.cancel();
    _passengerPositionSubscription?.cancel();
    super.onClose();
  }
}
