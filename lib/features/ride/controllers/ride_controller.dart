import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

class RideController extends GetxController {
  RideController(this._repository, this._session,
      [this._catalogRepository, ServiceKindRepository? serviceKinds])
      : _serviceKinds = serviceKinds;

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
  final Rxn<DriverTrackingSnapshot> trackedDriver =
      Rxn<DriverTrackingSnapshot>();
  final Rxn<RideCoordinate> trackedPassenger = Rxn<RideCoordinate>();
  StreamSubscription<DriverOffer>? _offersSubscription;
  Timer? _trackingTimer;
  Timer? _recipientTimer;
  StreamSubscription<Position>? _passengerPositionSubscription;
  String? _requestId;
  bool _isResumingRequest = false;
  bool _hasCheckedForOpenRide = false;
  int _catalogRequestId = 0;
  int _quoteRequestId = 0;
  DateTime? _lastPassengerLocationPublished;
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
      if (status <= 2) {
        negotiationStatus.value = NegotiationStatus.searching;
        isSearchingForDriver.value = true;
        offersExhausted.value = false;
        offersStreamDone.value = false;
        await _watchOffers(rideId);
        if (!isClosed) Get.offAllNamed<void>(RideRoutes.negotiationQuote);
        return;
      }

      negotiationStatus.value = NegotiationStatus.accepted;
      isDriverAssigned.value = true;
      await refreshActiveRide();
      startRealTracking();
      if (!isClosed) Get.offAllNamed<void>(RideRoutes.driverLocation);
    } catch (_) {
      // Opening the home screen remains available when the network is offline.
    }
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
      pickup: '${ride['pickupAddress'] ?? 'نقطة الانطلاق'}',
      destination: '${ride['destinationAddress'] ?? 'الوجهة'}',
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
        '${ride['pickupAddress'] ?? 'نقطة الانطلاق'}';
    location.toController.text = '${ride['destinationAddress'] ?? 'الوجهة'}';
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
              onTap: () => onTap(driver),
              icon: _nearbyDriverIcon.value ??
                  BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  ),
            ),
          )
          .toSet();

  Set<Marker> get trackingMarkers => <Marker>{
        if (trackedDriver.value != null)
          Marker(
            markerId: const MarkerId('tracked-driver'),
            position: LatLng(
              trackedDriver.value!.location.latitude,
              trackedDriver.value!.location.longitude,
            ),
            rotation: trackedDriver.value!.heading ?? 0,
            flat: true,
            infoWindow: const InfoWindow(title: 'السائق'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
          ),
        if (trackedPassenger.value != null)
          Marker(
            markerId: const MarkerId('tracked-passenger'),
            position: LatLng(
              trackedPassenger.value!.latitude,
              trackedPassenger.value!.longitude,
            ),
            infoWindow: const InfoWindow(title: 'موقعي الحالي'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
          ),
      };

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
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(),
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
        _nearbyDriverIcon.value = BitmapDescriptor.bytes(
          Uint8List.sublistView(data),
          imagePixelRatio: _driverMarkerPixelRatio,
        );
      }
    } catch (_) {}
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
      final routeDistance =
          _routeDistanceKm(location.routePoints, pickupPoint, destinationPoint);
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
      pickup: 'موقعي الحالي',
      destination: 'الوجهة المحددة',
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
      destinationAddress: destinationAddress.isEmpty
          ? 'الوجهة المحددة'
          : destinationAddress,
      destinationAddressName: location.addressNameController.text.trim(),
      destinationStreet: location.streetController.text.trim(),
      destinationDetails: location.detailsController.text.trim(),
      routeDistanceMeters: (routeDistanceKm.value * 1000).round(),
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
    if (requestId != null) await _repository.cancelRequest(requestId);
    offersExhausted.value = false;
    driverOffers.clear();
    requestRecipients.clear();
    _recipientTimer?.cancel();
    isSearchingForDriver.value = false;
    cancelRide('ألغى المستخدم البحث عن سائق');
  }

  Future<void> cancelActiveRide(String reason) async {
    final requestId = _requestId;
    if (requestId != null) await _repository.cancelRequest(requestId);
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
      final driver = detail['driver'];
      if (driver is Map) {
        assignedDriverName.value = '${driver['name'] ?? ''}'.trim();
        assignedDriverPhone.value = '${driver['phoneNumber'] ?? ''}'.trim();
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
        }
      }
    } catch (_) {
      // Keep the last confirmed marker visible during a transient network failure.
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
    activeRideStatus.value = '';
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
