import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show Icons, TextEditingController, TextPainter, TextSpan, TextStyle;
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/cache/persistent_network_image.dart';
import '../../../core/network/api_client.dart';
import '../../../core/realtime/tracking_hub_service.dart';
import '../../../core/services/auth_session_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/ride_preferences.dart';
import '../../account/account_routes.dart';
import '../home/repositories/service_kind_repository.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import '../location_selection/repositories/route_repository.dart';
import '../models/ride_models.dart';
import '../models/service_kind_models.dart';
import '../negotiation/repositories/ride_negotiation_repository.dart';
import '../ride_routes.dart';
import '../vehicle_selection/repositories/service_catalog_repository.dart';

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
  final RxInt bottomNavigationIndex = 0.obs;
  final RxInt homeServiceIndex = (-1).obs;
  final RxList<RideHomeService> homeServices = <RideHomeService>[].obs;
  final RxBool isHomeServicesLoading = false.obs;
  final RxString homeServicesError = ''.obs;
  final RxBool autoStartTransport = RidePreferences.autoStartTransport.obs;
  final RxBool isSearchingForDriver = false.obs;
  final RxBool isSubmittingRequest = false.obs;
  final RxBool isRespondingToOffer = false.obs;
  final RxBool isDriverAssigned = false.obs;
  final RxString activeRideStatus = ''.obs;
  final RxString preferredPaymentMethod = 'cash'.obs;
  final RxBool activeRidePaymentCompleted = false.obs;
  final RxBool customerPaymentEnabled = false.obs;
  final Rxn<Map<String, Object?>> cashCollectionApproval =
      Rxn<Map<String, Object?>>();
  final RxnInt cashShortfallApprovalToOpen = RxnInt();
  final RxString cancellationReason = ''.obs;
  final RxBool isCancellingRide = false.obs;
  final cancellationReasonController = TextEditingController();
  final Rx<NegotiationStatus> negotiationStatus = NegotiationStatus.idle.obs;
  final RxString quoteError = ''.obs;
  final Rxn<RideQuote> quote = Rxn<RideQuote>();
  final Rxn<RideRequestDraft> currentDraft = Rxn<RideRequestDraft>();
  final Rxn<DriverOffer> acceptedOffer = Rxn<DriverOffer>();
  final RxString assignedDriverName = ''.obs;
  final RxString assignedDriverPhone = ''.obs;
  final RxDouble offeredPrice = 0.0.obs;
  final RxBool autoAcceptMatchingPrice = false.obs;
  final RxBool moreThanFourPassengers = false.obs;
  final RxString passengerNotes = ''.obs;
  final Set<String> _autoAcceptAttempts = <String>{};
  final RxDouble routeDistanceKm = 0.0.obs;
  final RxList<DriverOffer> driverOffers = <DriverOffer>[].obs;
  final RxSet<String> removingOfferIds = <String>{}.obs;
  final RxBool offersExhausted = false.obs;
  final RxBool offersStreamDone = false.obs;
  final RxInt receivedOffersCount = 0.obs;
  final RxList<NearbyDriver> nearbyDrivers = <NearbyDriver>[].obs;

  /// Confirmed views from the API; nearby drivers are never counted as viewers.
  final RxList<RideRequestViewer> requestViewers = <RideRequestViewer>[].obs;
  final RxInt searchRemainingSeconds = 60.obs;
  final RxDouble pendingSearchPrice = 0.0.obs;
  final RxBool isUpdatingSearchPrice = false.obs;
  DateTime? _searchDeadline;
  final Rxn<NearbyDriver> selectedNearbyDriver = Rxn<NearbyDriver>();
  final RxMap<String, BitmapDescriptor> _nearbyDriverPhotoIcons =
      <String, BitmapDescriptor>{}.obs;
  final Rxn<BitmapDescriptor> _approachingCarIcon = Rxn<BitmapDescriptor>();
  final Rxn<BitmapDescriptor> _inTripDirectionIcon = Rxn<BitmapDescriptor>();
  final Rxn<DriverTrackingSnapshot> trackedDriver =
      Rxn<DriverTrackingSnapshot>();
  DriverTrackingSnapshot? get latestDriverGpsSample =>
      _driverAnimationTarget ?? trackedDriver.value;
  final Rxn<RideCoordinate> trackedPassenger = Rxn<RideCoordinate>();
  final RxList<LatLng> trackingRoutePoints = <LatLng>[].obs;
  final RxInt trackingRouteDistanceMeters = 0.obs;
  final RxInt trackingRouteDurationSeconds = 0.obs;
  final RxString trackingNextStepInstruction = ''.obs;
  final RxString trackingNextManeuver = ''.obs;
  final RxInt trackingNextStepDistanceMeters = 0.obs;
  StreamSubscription<TrackingHubEvent>? _hubEventSubscription;
  StreamSubscription<void>? _hubConnectionSubscription;
  Timer? _offersDeadlineTimer;
  StreamSubscription<Position>? _passengerPositionSubscription;
  bool _passengerLocationPermissionNoticeShown = false;
  Timer? _driverMarkerAnimationTimer;
  DriverTrackingSnapshot? _driverAnimationStart;
  DriverTrackingSnapshot? _driverAnimationTarget;
  DateTime? _driverAnimationStartedAt;
  Duration _driverAnimationDuration = const Duration(milliseconds: 1500);
  String? _requestId;
  bool _isResumingRequest = false;
  bool _searchMutationInProgress = false;
  int _offersWatchGeneration = 0;
  bool _hasCheckedForOpenRide = false;
  int _catalogRequestId = 0;
  int _quoteRequestId = 0;
  int _nearbyDriversRequestId = 0;
  DateTime? _lastPassengerLocationPublished;
  RideCoordinate? _lastTrackingRouteOrigin;
  RideCoordinate? _lastTrackingRouteDestination;
  DateTime? _lastTrackingRouteRequestedAt;
  int _trackingRouteRequestId = 0;
  int _confirmedRouteVersion = 0;
  bool hasShownTripSharePrompt = false;

  String? get currentRideId => _requestId;
  DateTime get searchTime => DateTime.now();

  bool get bookingLocked => _requestId != null || isSubmittingRequest.value;

  @override
  void onInit() {
    super.onInit();
    unawaited(loadServiceCatalog());
    unawaited(_loadHomeServices());
    unawaited(_loadTrackingIcons());
    if (Get.isRegistered<TrackingHubService>()) {
      final hub = Get.find<TrackingHubService>();
      _hubEventSubscription = hub.events.listen(_handleHubEvent);
      _hubConnectionSubscription = hub.connectionRestored.listen((_) {
        final rideId = _requestId;
        if (rideId != null && isSearchingForDriver.value) {
          unawaited(
            _refreshSearchSnapshotSafely(rideId, _offersWatchGeneration),
          );
        } else if (rideId != null) {
          unawaited(refreshActiveRide());
        }
      });
    }
  }

  @override
  void onReady() {
    super.onReady();
    final arguments = Get.arguments;
    if (arguments is Map && arguments['pushNotification'] is Map) return;
    unawaited(restoreOpenRideOnLaunch());
  }

  /// Handles only the fixed notification actions defined by the application.
  /// The server supplies identifiers, never Flutter route names.
  Future<void> openNotificationPayload(Map<String, String> payload) async {
    final notificationId = payload['notificationId'];
    final action = payload['action']?.trim().toLowerCase();
    final rideId = payload['rideId']?.trim();
    try {
      if (action == 'open_notifications') {
        await _markNotificationRead(notificationId);
        Get.offAllNamed<void>(RideRoutes.notifications, arguments: payload);
        return;
      }
      if (_opensWallet(action, payload)) {
        await _markNotificationRead(notificationId);
        Get.offAllNamed<void>(AccountRoutes.wallet, arguments: payload);
        return;
      }

      if (rideId != null && rideId.isNotEmpty) {
        await resumeOpenRide(rideId);
        await _markNotificationRead(notificationId);
        if (action == 'open_ride_chat') {
          Get.toNamed<void>(RideRoutes.chat, arguments: payload);
        } else if (action == 'open_ride_payment') {
          Get.toNamed<void>(RideRoutes.payment, arguments: payload);
        } else if (action == 'approve_cash_shortfall') {
          requestCashShortfallApproval(
            int.tryParse(payload['cashCollectionApprovalId'] ?? ''),
          );
        }
        return;
      }
    } on Object {
      // A stale or finalized ride must not prevent access to the notification
      // center, where the user can still read the server's final message.
    }

    await _markNotificationRead(notificationId);
    Get.offAllNamed<void>(RideRoutes.notifications, arguments: payload);
  }

  bool _opensWallet(String? action, Map<String, String> payload) =>
      action == 'open_wallet' ||
      action == 'open_wallet_transaction' ||
      payload['walletTransactionId']?.isNotEmpty == true ||
      payload['driverSettlementPaymentId']?.isNotEmpty == true;

  Future<void> _markNotificationRead(String? notificationId) async {
    if (notificationId == null || notificationId.isEmpty) return;
    try {
      await Get.find<ApiClient>().execute<Object?>(
        model: 'NotificationModel',
        operation: 'update',
        data: <String, Object?>{'id': notificationId, 'isRead': true},
      );
    } on Object {
      // The selected screen is still valid if the read marker is retried later.
    }
  }

  void requestCashShortfallApproval(int? approvalId) {
    if (approvalId == null) return;
    cashShortfallApprovalToOpen.value = approvalId;
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
      _beginSearchCycle();
      receivedOffersCount.value = 0;
      driverOffers.clear();
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
    _confirmedRouteVersion = _asInt(ride['routeVersion']) ?? 0;
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
      suggestedPrice: _asDouble(ride['quotedPrice']) ?? price,
      minPrice: _asDouble(ride['minCustomerPrice']) ?? price,
      maxPrice: _asDouble(ride['maxCustomerPrice']) ?? price,
      priceStep: 1,
      currency: 'YER',
    );
    offeredPrice.value = price;
  }

  Future<void> _loadHomeServices() => loadHomeServices();

  Future<void> loadHomeServices() async {
    final serviceKinds = _serviceKinds;
    if (serviceKinds == null || isHomeServicesLoading.value) return;
    isHomeServicesLoading.value = true;
    homeServicesError.value = '';
    try {
      final values = await serviceKinds.getServices();
      homeServices.assignAll(values);
      applyAdminDefaultServiceKind();
    } catch (_) {
      homeServicesError.value = 'تعذر تحميل أنواع الرحلات. حاول مرة أخرى.';
    } finally {
      isHomeServicesLoading.value = false;
    }
  }

  void applyAdminDefaultServiceKind() {
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
  Future<void> selectHomeService(int index) async {
    if (bookingLocked) return;
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
      return;
    }
    await loadServiceCatalog(requestedKindId: newKindId);
  }

  Future<void> setAutoStartTransport(bool value) async {
    autoStartTransport.value = value;
    await RidePreferences.setAutoStartTransport(value);
  }

  List<RideVehicle> get vehicles => catalogVehicles;

  List<RideVehicleType> get availableVehicleTypes {
    final types = <RideVehicleType>{
      for (final vehicle in vehicles) vehicle.type,
    };
    return RideVehicleType.values.where(types.contains).toList(growable: false);
  }

  Future<void> loadServiceCatalog({int? requestedKindId}) async {
    final targetKindId = requestedKindId ?? selectedServiceKindId.value;
    final requestId = ++_catalogRequestId;
    catalogError.value = '';

    if (!_canUseCatalogApi || targetKindId == null) {
      catalogVehicles.clear();
      catalogError.value = 'تعذر تحديد الخدمة المطلوبة.';
      return;
    }
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
        catalogError.value = 'لا توجد خدمات متاحة لهذا النوع حاليًا.';
      } else {
        catalogVehicles.assignAll(matchingServices);
        if (!matchingServices.any((item) =>
            item.serviceCatalogItemId ==
            selectedVehicle.value?.serviceCatalogItemId)) {
          selectedVehicle.value = null;
          hasSelectedTransport.value = false;
        }
      }
    } catch (_) {
      if (requestId != _catalogRequestId ||
          targetKindId != selectedServiceKindId.value) {
        return;
      }
      catalogVehicles.clear();
      catalogError.value = 'تعذّر تحميل الخدمات، حاول مرة أخرى.';
    } finally {
      if (requestId == _catalogRequestId) {
        isCatalogLoading.value = false;
      }
    }
  }

  bool get _canUseCatalogApi =>
      _catalogRepository != null &&
      AppEnvironment.isConfigured &&
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
              anchor: const ui.Offset(.5, 1),
              // A driver marker is an interactive object, not a map point
              // that may be used as the customer's pickup/destination.
              consumeTapEvents: true,
              onTap: () => onTap(driver),
              icon: _nearbyDriverPhotoIcons[driver.id] ??
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
            anchor: const ui.Offset(.5, .5),
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
      if (Get.isRegistered<TrackingHubService>()) {
        final serviceKindId =
            selected?.serviceKindId ?? selectedServiceKindId.value;
        await Get.find<TrackingHubService>().setNearbyDriverSubscription(
          serviceKindId: serviceKindId,
          serviceCatalogItemId: selected?.serviceCatalogItemId,
          pickupLatitude: origin.latitude,
          pickupLongitude: origin.longitude,
          radiusMeters: 3000,
          initialDriverIds:
              drivers.map((driver) => int.tryParse(driver.id)).whereType<int>(),
        );
      }
      for (final driver in drivers) {
        unawaited(_loadDriverPhotoMarker(driver));
      }
    } catch (_) {
      // Do not retain markers belonging to an old pickup after the server
      // query fails. A later pickup change or return to this screen retries.
      if (requestId == _nearbyDriversRequestId) {
        nearbyDrivers.clear();
        if (Get.isRegistered<TrackingHubService>()) {
          unawaited(
              Get.find<TrackingHubService>().clearNearbyDriverSubscription());
        }
      }
    }
  }

  void closeNearbyDriverCard() => selectedNearbyDriver.value = null;

  void selectNearbyDriver(NearbyDriver driver) {
    if (selectedNearbyDriver.value?.id == driver.id) return;
    selectedNearbyDriver.value = driver;
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
      final imageFile =
          await PersistentNetworkImageCache.fileFor(normalizedPhotoUrl);
      final bytes = await imageFile.readAsBytes();
      final icon = await _buildDriverMarkerIcon(bytes);
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
        paint..color = const ui.Color(0xFF087AC1),
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

  Future<void> _startPassengerPositionTracking() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showPassengerLocationPermissionNotice(permission);
        return;
      }
      await _passengerPositionSubscription?.cancel();
      _passengerPositionSubscription = Geolocator.getPositionStream(
        locationSettings: _passengerLocationStreamSettings(),
      ).listen((position) {
        final current = RideCoordinate(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        trackedPassenger.value = current;
        final rideId = int.tryParse(_requestId ?? '');
        final now = DateTime.now();
        final accuracy = position.accuracy;
        if (rideId != null &&
            accuracy.isFinite &&
            accuracy > 0 &&
            accuracy <= 75 &&
            (_lastPassengerLocationPublished == null ||
                now.difference(_lastPassengerLocationPublished!) >=
                    const Duration(seconds: 8)) &&
            Get.isRegistered<TrackingHubService>()) {
          _lastPassengerLocationPublished = now;
          final heading = position.heading;
          final speed = position.speed;
          unawaited(Get.find<TrackingHubService>().publishPassengerLocation(
            <String, Object?>{
              'rideId': rideId,
              'latitude': current.latitude,
              'longitude': current.longitude,
              'accuracy': accuracy,
              'observedAtUtc': position.timestamp.toUtc().toIso8601String(),
              if (heading.isFinite && heading >= 0 && heading < 360)
                'bearing': heading,
              if (speed.isFinite && speed >= 0 && speed <= 75) 'speed': speed,
            },
          ));
        }
      });
    } catch (_) {
      // Location tracking resumes when location services become available.
    }
  }

  LocationSettings _passengerLocationStreamSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'يمن درايف يتتبع الرحلة',
          notificationText: 'يستمر تحديث موقعك أثناء الرحلة النشطة.',
          notificationChannelName: 'تتبع الرحلة',
          notificationIcon: AndroidResource(name: 'ic_stat_yemendrive'),
          setOngoing: true,
        ),
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
  }

  void _showPassengerLocationPermissionNotice(LocationPermission permission) {
    if (_passengerLocationPermissionNoticeShown || isClosed) return;
    _passengerLocationPermissionNoticeShown = true;
    final message = permission == LocationPermission.deniedForever
        ? 'لن يتم تحديث موقعك أثناء الرحلة لأن صلاحية الموقع غير متاحة.'
        : 'لم تُمنح صلاحية الموقع، لذلك لن يتم تحديث موقعك أثناء الرحلة.';
    Get.snackbar('تتبع الرحلة غير مفعل', message);
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
      Get.snackbar('لا توجد خدمات متاحة',
          'انتظر تحميل الخدمات من الخادم ثم حاول مرة أخرى.');
    }
  }

  void chooseTransport(RideVehicleType value) {
    selectedTransport.value = value;
    hasSelectedTransport.value = true;
  }

  /// Selects a catalog item returned by the API while keeping the existing
  /// vehicle-type contract used by quote/request endpoints.
  void chooseCatalogVehicle(RideVehicle vehicle) {
    if (bookingLocked) return;
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

  void invalidateBookingQuote() {
    if (bookingLocked) return;
    cancelPendingQuote();
    quote.value = null;
    quoteError.value = '';
    offeredPrice.value = 0;
    negotiationStatus.value = NegotiationStatus.idle;
  }

  Future<void> refreshBookingQuote() async {
    final vehicle = selectedVehicle.value;
    if (bookingLocked || vehicle == null) return;
    await _quoteForSelection(vehicle, openPage: false);
  }

  Future<RideQuote> fetchCatalogQuote({
    required RideVehicle vehicle,
    required RideCoordinate pickup,
    required RideCoordinate destination,
    required double distanceKm,
    required double durationMinutes,
  }) =>
      _repository.getQuote(
        serviceKindId: vehicle.serviceKindId!,
        serviceCatalogItemId: vehicle.serviceCatalogItemId!,
        pickup: pickup,
        destination: destination,
        distanceKm: distanceKm,
        durationMinutes: durationMinutes,
      );

  void applyBookingQuote(RideQuote value, {required double distanceKm}) {
    if (bookingLocked || selectedVehicle.value == null) return;
    cancelPendingQuote();
    quoteError.value = '';
    quote.value = value;
    routeDistanceKm.value = distanceKm;
    offeredPrice.value = value.suggestedPrice;
    negotiationStatus.value = NegotiationStatus.ready;
  }

  /// Negotiation is bounded by the server quote retained for this ride.
  static const int maxBookingPrice = 999999999;
  double get minimumBookingPrice => quote.value?.minPrice ?? 1;
  double get maximumBookingPrice =>
      quote.value?.maxPrice ?? maxBookingPrice.toDouble();
  bool isPriceAllowed(double price) =>
      price.isFinite &&
      price >= minimumBookingPrice &&
      price <= maximumBookingPrice &&
      price > 0;

  bool setBookingPrice(String input) {
    if (bookingLocked || quote.value == null) return false;
    var normalized = input.trim();
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var digit = 0; digit < 10; digit++) {
      normalized = normalized
          .replaceAll(arabic[digit], '$digit')
          .replaceAll(persian[digit], '$digit');
    }
    final price = int.tryParse(normalized);
    if (price == null || !isPriceAllowed(price.toDouble())) return false;
    offeredPrice.value = price.toDouble();
    return true;
  }

  Future<void> _quoteForSelection(RideVehicle vehicle,
      {bool openPage = true}) async {
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
    if (selectedVehicle.value != vehicle) chooseCatalogVehicle(vehicle);
    final requestId = ++_quoteRequestId;
    quote.value = null;
    quoteError.value = '';
    negotiationStatus.value = NegotiationStatus.quoting;
    if (openPage && Get.currentRoute != RideRoutes.negotiationQuote) {
      Get.toNamed<void>(RideRoutes.negotiationQuote);
    }

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
    if (value == null || bookingLocked) return;
    final step = value.priceStep.isFinite && value.priceStep >= 1
        ? value.priceStep.round()
        : 1;
    setBookingPrice((offeredPrice.value + step * direction)
        .round()
        .clamp(minimumBookingPrice, maximumBookingPrice)
        .toStringAsFixed(0));
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

  Future<void> requestRide(
      {bool later = false, bool openSearchPage = false}) async {
    if (_searchMutationInProgress) return;
    if (!_session.requireAuthentication(
      returnRoute: RideRoutes.negotiationQuote,
      arguments: <String, Object?>{'resumeRequest': true},
    )) {
      return;
    }
    // A stopped or exhausted search is resumed on the same server ride.
    if (_requestId != null &&
        !isSearchingForDriver.value &&
        negotiationStatus.value == NegotiationStatus.searching) {
      await retryDriverSearch();
      return;
    }
    if (_requestId != null) return;
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
    if (!isPriceAllowed(offeredPrice.value)) {
      Get.snackbar('الأجرة خارج الحد المسموح',
          'اختر مبلغًا من ${minimumBookingPrice.toStringAsFixed(0)} إلى ${maximumBookingPrice.toStringAsFixed(0)} ر.ي.');
      return;
    }
    final pickupAddress = location.fromController.text.trim();
    final destinationAddress = location.toController.text.trim();
    final draft = RideRequestDraft(
      customerId: _session.currentUserId.value,
      pickup: location.pickupIsCurrentLocation.value
          ? 'موقعي الحالي'
          : (pickupAddress.isNotEmpty
              ? pickupAddress
              : location.pickupArea.value.trim().isEmpty
                  ? 'منطقة الانطلاق المحددة'
                  : location.pickupArea.value.trim()),
      destination: location.addressNameController.text.trim().isNotEmpty
          ? location.addressNameController.text.trim()
          : (location.streetController.text.trim().isNotEmpty
              ? location.streetController.text.trim()
              : location.destinationArea.value.trim().isEmpty
                  ? (destinationAddress.isNotEmpty
                      ? destinationAddress
                      : 'منطقة الوجهة المحددة')
                  : location.destinationArea.value.trim()),
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
      pricingQuoteToken: quote.value?.pricingQuoteToken,
      // During development the map provider may supply coordinates before a
      // human-readable address. The API requires both address fields, so keep
      // the selected route usable without inventing a real address.
      pickupAddress:
          pickupAddress.isEmpty ? 'نقطة الانطلاق المحددة' : pickupAddress,
      destinationAddress: <String>[
        destinationAddress.isEmpty
            ? (location.streetController.text.trim().isEmpty
                ? 'الوجهة المحددة'
                : location.streetController.text.trim())
            : destinationAddress,
        // The current contract has one destination address. Keep meeting
        // details there so the driver and dashboard receive the same text.
        if (location.detailsController.text.trim().isNotEmpty &&
            location.detailsController.text.trim() != destinationAddress)
          location.detailsController.text.trim(),
      ].join(' — '),
      destinationAddressName: location.addressNameController.text.trim(),
      destinationStreet: location.streetController.text.trim(),
      destinationDetails: location.detailsController.text.trim(),
      moreThanFourPassengers: moreThanFourPassengers.value,
      passengerNotes: passengerNotes.value.trim(),
      routeDistanceMeters: (routeDistanceKm.value * 1000).round(),
      routeDurationSeconds: location.routeDurationSeconds.value > 0
          ? location.routeDurationSeconds.value
          : null,
      idempotencyKey: DateTime.now().microsecondsSinceEpoch.toString(),
    );
    currentDraft.value = draft;
    _searchMutationInProgress = true;
    isSubmittingRequest.value = true;
    try {
      final started = await _repository.createRequest(draft);
      _requestId = started.rideId;
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
    } catch (_) {
      currentDraft.value = null;
      Get.snackbar('تعذر إرسال الطلب', 'تحقق من الاتصال ثم حاول مرة أخرى.');
      return;
    } finally {
      _searchMutationInProgress = false;
      isSubmittingRequest.value = false;
    }

    _beginSearchCycle();
    if (openSearchPage && Get.currentRoute != RideRoutes.negotiationQuote) {
      Get.toNamed<void>(RideRoutes.negotiationQuote);
    }
    await _watchOffers(_requestId!);
    _updateOffersExhausted();
  }

  Future<void> _watchOffers(String requestId) async {
    final generation = ++_offersWatchGeneration;
    final rideId = int.tryParse(requestId);
    if (rideId == null || !Get.isRegistered<TrackingHubService>()) return;
    try {
      await Get.find<TrackingHubService>().clearNearbyDriverSubscription();
      // Join first, then fetch one snapshot. This closes the gap where an
      // offer could arrive between the initial read and Hub subscription.
      await Get.find<TrackingHubService>().setRideSubscriptions(<int>{rideId});
      await _refreshSearchSnapshot(requestId, generation);
    } catch (_) {
      if (generation == _offersWatchGeneration) {
        Get.snackbar(
            'تعذر تحديث حالة البحث', 'تحقق من الاتصال ثم أعد المحاولة.');
      }
    }
  }

  Future<void> _refreshSearchSnapshot(String requestId, int generation) async {
    final detail = await _repository.getRideDetail(requestId);
    if (generation != _offersWatchGeneration ||
        requestId != _requestId ||
        !isSearchingForDriver.value) return;

    final rawRide = detail['ride'];
    final ride = rawRide is Map
        ? Map<Object?, Object?>.from(rawRide)
        : const <Object?, Object?>{};
    final status = _asInt(ride['status']);
    final rawOffers = detail['offers'];
    final allOffers = rawOffers is List
        ? rawOffers
            .whereType<Map<Object?, Object?>>()
            .map((item) => Map<String, Object?>.from(item))
            .map(_repository.mapRealtimeOffer)
            .whereType<DriverOffer>()
            .toList(growable: false)
        : const <DriverOffer>[];
    if (status != null && <int>{3, 4, 5, 8}.contains(status)) {
      activeRideStatus.value = '${ride['status']}';
      acceptedOffer.value = allOffers
          .where((offer) => offer.status == DriverOfferStatus.accepted)
          .firstOrNull;
      driverFound();
      return;
    }
    if (status == 6 || status == 7) {
      isSearchingForDriver.value = false;
      _offersDeadlineTimer?.cancel();
      unawaited(
          Get.find<TrackingHubService>().setRideSubscriptions(const <int>{}));
      return;
    }

    final snapshot = allOffers
        .where((offer) => offer.status == DriverOfferStatus.pending)
        .where((offer) =>
            offer.expiresAt == null || offer.expiresAt!.isAfter(DateTime.now()))
        .toList(growable: false);
    driverOffers.assignAll(snapshot);
    _tryAutoAcceptMatchingOffer();
    receivedOffersCount.value = snapshot.length;
    _updateOffersExhausted();
    try {
      final viewers = await _repository.getRequestViewers(requestId);
      if (generation == _offersWatchGeneration &&
          requestId == _requestId &&
          isSearchingForDriver.value) {
        // Preserve views arriving over SignalR while the snapshot was in flight.
        for (final viewer in viewers) {
          _upsertRequestViewer(viewer);
        }
      }
    } catch (_) {
      // A missing snapshot never fabricates viewers; reconnect can recover it.
    }
  }

  Future<void> _refreshSearchSnapshotSafely(
      String requestId, int generation) async {
    try {
      await _refreshSearchSnapshot(requestId, generation);
    } catch (_) {
      // The next reconnect or explicit retry can restore the current snapshot.
    }
  }

  void _handleHubEvent(TrackingHubEvent event) {
    final payload = event.payload;
    if (event.name == 'nearbyDriverAvailabilityChanged' &&
        payload['isAvailable'] == false) {
      final driverId = '${payload['driverId'] ?? ''}';
      nearbyDrivers.removeWhere((driver) => driver.id == driverId);
      return;
    }
    if (event.name == 'nearbyDriverLocationUpdated') {
      final driver = _repository.mapRealtimeNearbyDriver(payload);
      if (driver == null) return;
      final index = nearbyDrivers.indexWhere((item) => item.id == driver.id);
      if (index < 0) {
        nearbyDrivers.add(driver);
      } else {
        nearbyDrivers[index] = driver;
      }
      unawaited(_loadDriverPhotoMarker(driver));
      return;
    }
    final rideId =
        payload['rideId']?.toString() ?? payload['rideID']?.toString();
    if (rideId != _requestId) return;

    if (event.name == 'rideRequestViewed' && isSearchingForDriver.value) {
      final id = payload['driverId']?.toString();
      if (id != null && id.isNotEmpty) {
        _upsertRequestViewer(RideRequestViewer(
            driverId: id,
            name: '${payload['name'] ?? ''}',
            photoUrl: payload['photoUrl']?.toString()));
      }
      return;
    }

    if (event.name == 'paymentUpdated' || event.name == 'cashApprovalUpdated') {
      unawaited(refreshActiveRide());
      return;
    }

    if (event.name == 'rideUnavailable') {
      if (!isSearchingForDriver.value) return;
      isSearchingForDriver.value = false;
      offersExhausted.value = true;
      _offersDeadlineTimer?.cancel();
      driverOffers.clear();
      unawaited(
          Get.find<TrackingHubService>().setRideSubscriptions(const <int>{}));
      return;
    }
    if (event.name == 'rideStatusUpdated') {
      final status = _asInt(payload['rideStatus']);
      if (status == null) return;
      activeRideStatus.value = '$status';
      customerPaymentEnabled.value = payload['customerPaymentEnabled'] == true;
      if (status == 6 || status == 7) {
        _stopRealTracking();
      } else if (status == 3 || status == 4 || status == 5) {
        unawaited(_refreshAssignedDriverRoute());
      }
      return;
    }
    if (event.name == 'driverLocationUpdated') {
      final latitude = _asDouble(payload['latitude']);
      final longitude = _asDouble(payload['longitude']);
      if (latitude == null || longitude == null) return;
      final observedAt =
          DateTime.tryParse('${payload['observedAtUtc'] ?? ''}')?.toUtc();
      _animateTrackedDriver(DriverTrackingSnapshot(
        driverId: '${payload['driverId'] ?? ''}',
        location: RideCoordinate(latitude: latitude, longitude: longitude),
        heading: _asDouble(payload['bearing']),
        updatedAt: observedAt ?? DateTime.now().toUtc(),
      ));
      unawaited(_refreshAssignedDriverRoute());
      return;
    }
    if (event.name != 'offerReceived' && event.name != 'offerUpdated') return;
    final offer = _repository.mapRealtimeOffer(payload);
    if (offer == null) return;

    final index = driverOffers.indexWhere((item) => item.id == offer.id);
    if (offer.status == DriverOfferStatus.pending) {
      if (index < 0) {
        driverOffers.add(offer);
        receivedOffersCount.value++;
      } else {
        driverOffers[index] = offer;
      }
      offersExhausted.value = false;
      _tryAutoAcceptMatchingOffer();
      return;
    }

    if (index >= 0) driverOffers[index] = offer;
    if (offer.status == DriverOfferStatus.accepted &&
        _asInt(payload['rideStatus']) == 3) {
      acceptedOffer.value = offer;
      activeRideStatus.value = '${payload['rideStatus']}';
      negotiationStatus.value = NegotiationStatus.accepted;
      _offersDeadlineTimer?.cancel();
      driverOffers.assignAll(driverOffers.map((item) => item.copyWith(
            status: item.id == offer.id
                ? DriverOfferStatus.accepted
                : DriverOfferStatus.rejected,
          )));
      driverFound();
      return;
    }
    if (offer.status == DriverOfferStatus.rejected ||
        offer.status == DriverOfferStatus.expired) {
      _dismissOffer(offer.id);
    }
  }

  Future<void> acceptOffer(DriverOffer offer) async {
    final requestId = _requestId;
    if (requestId == null ||
        isCancellingRide.value ||
        isRespondingToOffer.value ||
        offer.status != DriverOfferStatus.pending ||
        (offer.expiresAt?.isBefore(DateTime.now()) ?? false)) return;
    isRespondingToOffer.value = true;
    try {
      await _repository.acceptOffer(requestId, offer.id);
    } on FormatException catch (error) {
      Get.snackbar('تعذر قبول العرض', error.message);
      return;
    } catch (_) {
      Get.snackbar('تعذر قبول العرض', 'تحقق من الاتصال وحاول مرة أخرى.');
      return;
    } finally {
      isRespondingToOffer.value = false;
    }
    if (requestId != _requestId) return;
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

  void _tryAutoAcceptMatchingOffer() {
    final requestedPrice = currentDraft.value?.offeredPrice;
    if (!autoAcceptMatchingPrice.value ||
        isCancellingRide.value ||
        !isSearchingForDriver.value ||
        _requestId == null ||
        requestedPrice == null ||
        isRespondingToOffer.value ||
        _searchMutationInProgress) return;
    for (final offer in driverOffers) {
      final attempt = '$_requestId|${offer.id}|${offer.price}';
      if (offer.status != DriverOfferStatus.pending ||
          offer.price != requestedPrice ||
          (offer.expiresAt?.isBefore(DateTime.now()) ?? false) ||
          !_autoAcceptAttempts.add(attempt)) continue;
      unawaited(acceptOffer(offer));
      break;
    }
  }

  Future<void> rejectOffer(DriverOffer offer) async {
    final requestId = _requestId;
    if (requestId == null || isRespondingToOffer.value) return;
    isRespondingToOffer.value = true;
    try {
      await _repository.rejectOffer(requestId, offer.id);
      if (requestId == _requestId) _dismissOffer(offer.id);
    } catch (_) {
      Get.snackbar('تعذر رفض العرض', 'تحقق من الاتصال وحاول مرة أخرى.');
    } finally {
      isRespondingToOffer.value = false;
    }
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
    if (!isSearchingForDriver.value ||
        _searchMutationInProgress ||
        offersExhausted.value ||
        driverOffers.isNotEmpty ||
        removingOfferIds.isNotEmpty) return;

    // Drivers can stay silent, so the one-minute search window remains the
    // timeout signal. Offer delivery itself no longer polls the API.
    if (offersStreamDone.value) {
      unawaited(_finishSearchAsExhausted());
    }
  }

  void acknowledgeOffersExhausted() => offersExhausted.value = false;

  Future<void> retryDriverSearch() async {
    if (_searchMutationInProgress) return;
    final requestId = _requestId;
    if (requestId == null) {
      await requestRide();
      return;
    }
    _searchMutationInProgress = true;
    var restarted = false;
    try {
      final location = Get.find<LocationController>().pickup.value;
      await loadNearbyDrivers(center: location);
      await _repository.restartSearch(requestId);
      _beginSearchCycle();
      await _watchOffers(requestId);
      restarted = true;
    } catch (error) {
      isSearchingForDriver.value = false;
      Get.snackbar('تعذر إعادة البحث', _searchErrorMessage(error));
    } finally {
      _searchMutationInProgress = false;
    }
    if (restarted) _updateOffersExhausted();
  }

  Future<void> cancelDriverSearch() async {
    if (_searchMutationInProgress) return;
    _searchMutationInProgress = true;
    offersExhausted.value = false;
    offersStreamDone.value = false;
    receivedOffersCount.value = 0;
    driverOffers.clear();
    requestViewers.clear();
    _offersDeadlineTimer?.cancel();
    isSearchingForDriver.value = false;
    ++_offersWatchGeneration;
    negotiationStatus.value = NegotiationStatus.searching;
    try {
      final requestId = _requestId;
      if (requestId != null) await _repository.closeSearch(requestId);
    } catch (error) {
      Get.snackbar('تعذر إيقاف البحث', _searchErrorMessage(error));
    } finally {
      if (Get.isRegistered<TrackingHubService>()) {
        unawaited(
            Get.find<TrackingHubService>().setRideSubscriptions(const <int>{}));
      }
      _searchMutationInProgress = false;
    }
  }

  void _beginSearchCycle() {
    isSearchingForDriver.value = true;
    hasShownTripSharePrompt = false;
    offersExhausted.value = false;
    offersStreamDone.value = false;
    _offersDeadlineTimer?.cancel();
    requestViewers.clear();
    pendingSearchPrice.value =
        currentDraft.value?.offeredPrice ?? offeredPrice.value;
    searchRemainingSeconds.value = 60;
    _searchDeadline = searchTime.add(const Duration(seconds: 60));
    removingOfferIds.clear();
    negotiationStatus.value = NegotiationStatus.searching;
    driverOffers.clear();
    _offersDeadlineTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isSearchingForDriver.value || isClosed) {
        timer.cancel();
        return;
      }
      searchRemainingSeconds.value =
          (_searchDeadline!.difference(searchTime).inMilliseconds / 1000)
              .ceil()
              .clamp(0, 60);
      if (searchRemainingSeconds.value == 0) {
        timer.cancel();
        offersStreamDone.value = true;
        _updateOffersExhausted();
      }
    });
  }

  void _upsertRequestViewer(RideRequestViewer viewer) {
    final index =
        requestViewers.indexWhere((item) => item.driverId == viewer.driverId);
    if (index < 0) {
      requestViewers.add(viewer);
    } else {
      requestViewers[index] = viewer;
    }
  }

  bool get canChangeSearchPrice =>
      _requestId != null &&
      isSearchingForDriver.value &&
      !isUpdatingSearchPrice.value &&
      !isRespondingToOffer.value &&
      !_searchMutationInProgress &&
      searchRemainingSeconds.value > 0;
  bool get canConfirmSearchPrice =>
      canChangeSearchPrice &&
      currentDraft.value != null &&
      pendingSearchPrice.value > 0 &&
      isPriceAllowed(pendingSearchPrice.value) &&
      pendingSearchPrice.value != currentDraft.value!.offeredPrice;

  void changeSearchPrice(int direction) {
    if (!canChangeSearchPrice) return;
    final step = quote.value?.priceStep ?? 1;
    pendingSearchPrice.value = (pendingSearchPrice.value + direction * step)
        .round()
        .clamp(minimumBookingPrice, maximumBookingPrice)
        .toDouble();
  }

  Future<void> confirmSearchPrice() async {
    if (!canConfirmSearchPrice) return;
    final requestId = _requestId!;
    final draft = currentDraft.value!;
    final price = pendingSearchPrice.value;
    _searchMutationInProgress = true;
    isUpdatingSearchPrice.value = true;
    try {
      await _repository.restartSearch(requestId, customerPrice: price);
      if (_requestId != requestId || isDriverAssigned.value) return;
      currentDraft.value = draft.withPrice(price);
      offeredPrice.value = price;
      _autoAcceptAttempts.clear();
      _beginSearchCycle();
      await _watchOffers(requestId);
    } catch (error) {
      Get.snackbar('search_price_failed'.tr, _searchErrorMessage(error));
    } finally {
      isUpdatingSearchPrice.value = false;
      _searchMutationInProgress = false;
      _tryAutoAcceptMatchingOffer();
      _updateOffersExhausted();
    }
  }

  Future<void> _finishSearchAsExhausted() async {
    if (!isSearchingForDriver.value || _searchMutationInProgress) return;
    _searchMutationInProgress = true;
    isSearchingForDriver.value = false;
    _offersDeadlineTimer?.cancel();
    ++_offersWatchGeneration;
    try {
      final requestId = _requestId;
      if (requestId != null) {
        await _repository.closeSearch(requestId, exhausted: true);
      }
    } catch (error) {
      Get.snackbar('تعذر إغلاق البحث', _searchErrorMessage(error));
    } finally {
      if (Get.isRegistered<TrackingHubService>()) {
        unawaited(
            Get.find<TrackingHubService>().setRideSubscriptions(const <int>{}));
      }
      offersExhausted.value = true;
      _searchMutationInProgress = false;
    }
  }

  String _searchErrorMessage(Object error) =>
      error is FormatException ? error.message.toString() : error.toString();

  Future<void> cancelActiveRide(String reason) async {
    if (isCancellingRide.value) return;
    final requestId = _requestId;
    if (requestId == null || reason.trim().length < 3) {
      Get.snackbar(
          'سبب الإلغاء مطلوب', 'حدد سبباً واضحاً قبل إرسال طلب الإلغاء.');
      return;
    }
    isCancellingRide.value = true;
    final assigned = isDriverAssigned.value;
    try {
      if (assigned) {
        await _repository.requestCancellation(requestId, reason.trim());
      } else {
        await _repository.closeSearch(requestId, reason: reason.trim());
      }
    } catch (_) {
      Get.snackbar('تعذر إرسال الطلب',
          'لم يُرسل طلب الإلغاء. تحقق من الاتصال ثم حاول مرة أخرى.');
      return;
    } finally {
      isCancellingRide.value = false;
    }
    await _passengerPositionSubscription?.cancel();
    trackedDriver.value = null;
    trackedPassenger.value = null;
    isDriverAssigned.value = false;
    acceptedOffer.value = null;
    if (assigned) {
      cancelRide(reason);
    } else {
      prepareNewRide();
      Get.offAllNamed<void>(RideRoutes.homeTransport);
    }
  }

  void driverFound() {
    _offersDeadlineTimer?.cancel();
    isSearchingForDriver.value = false;
    isDriverAssigned.value = true;
    startRealTracking();
    Get.offNamed<void>(RideRoutes.driverLocation);
  }

  void startRealTracking() {
    final rideId = int.tryParse(_requestId ?? '');
    unawaited(() async {
      if (rideId != null && Get.isRegistered<TrackingHubService>()) {
        await Get.find<TrackingHubService>()
            .setRideSubscriptions(<int>{rideId});
      }
      await refreshActiveRide();
      await _startPassengerPositionTracking();
    }());
  }

  Future<void> refreshActiveRide({bool requireSuccess = false}) async {
    final rideId = _requestId;
    if (rideId == null) return;
    try {
      final detail = await _repository.getRideDetail(rideId);
      if (rideId != _requestId) return;
      final ride = detail['ride'];
      if (requireSuccess && ride is! Map) {
        throw const FormatException('تعذر تحديث بيانات الرحلة.');
      }
      if (ride is Map) {
        final status = _asInt(ride['status']);
        activeRideStatus.value = '${ride['status'] ?? ''}';
        _applyConfirmedRoute(Map<String, Object?>.from(ride));
        customerPaymentEnabled.value = ride['customerPaymentEnabled'] == true;
        if (status == 6 || status == 7) {
          _stopRealTracking();
        }
      }
      final payments = detail['payments'];
      activeRidePaymentCompleted.value = detail['paymentCompleted'] == true ||
          (payments is List &&
              payments.any((raw) {
                if (raw is! Map) return false;
                final payment = Map<Object?, Object?>.from(raw);
                final status = '${payment['status'] ?? ''}'.toLowerCase();
                return status == '2' || status == 'paid';
              }));
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
          _animateTrackedDriver(DriverTrackingSnapshot(
            driverId: '${values['driverId'] ?? ''}',
            location: RideCoordinate(latitude: latitude, longitude: longitude),
            heading: _asDouble(values['bearing']),
            updatedAt: DateTime.tryParse('${values['observedAtUtc'] ?? ''}') ??
                DateTime.now(),
          ));
          unawaited(_refreshAssignedDriverRoute());
        }
      }
    } catch (_) {
      if (requireSuccess) rethrow;
      // Keep the last confirmed marker visible during a transient network failure.
    }
  }

  void _applyConfirmedRoute(Map<String, Object?> ride) {
    final version = _asInt(ride['routeVersion']) ?? 0;
    if (version < _confirmedRouteVersion) return;
    final draft = currentDraft.value;
    final latitude = _asDouble(ride['destinationLatitude']);
    final longitude = _asDouble(ride['destinationLongitude']);
    if (draft == null || latitude == null || longitude == null ||
        !latitude.isFinite || !longitude.isFinite || latitude.abs() > 90 ||
        longitude.abs() > 180) return;
    _confirmedRouteVersion = version;
    final price = _asDouble(ride['customerPrice']) ?? draft.offeredPrice;
    final label = '${ride['destinationDisplayName'] ?? ride['destinationAddress'] ?? draft.destination}';
    final changed = draft.destinationCoordinate.latitude != latitude ||
        draft.destinationCoordinate.longitude != longitude || draft.destination != label;
    if (!changed && draft.offeredPrice == price) return;
    currentDraft.value = RideRequestDraft(
      pickup: draft.pickup,
      destination: label,
      pickupCoordinate: draft.pickupCoordinate,
      destinationCoordinate: RideCoordinate(latitude: latitude, longitude: longitude),
      serviceKindId: draft.serviceKindId,
      serviceCatalogItemId: draft.serviceCatalogItemId,
      customerId: draft.customerId,
      offeredPrice: price,
      pickupAddress: draft.pickupAddress,
      destinationAddress: '${ride['destinationAddress'] ?? label}',
      destinationAddressName: label,
      destinationStreet: changed ? '' : draft.destinationStreet,
      destinationDetails: changed ? '' : draft.destinationDetails,
      moreThanFourPassengers: draft.moreThanFourPassengers,
      passengerNotes: draft.passengerNotes,
      routeDistanceMeters: _asInt(ride['routeDistanceMeters']) ?? draft.routeDistanceMeters,
      routeDurationSeconds: _asInt(ride['routeDurationSeconds']) ?? draft.routeDurationSeconds,
    );
    offeredPrice.value = price;
    if (!changed) return;
    final location = Get.find<LocationController>();
    location.destination.value = LatLng(latitude, longitude);
    location.toController.text = label;
    location.confirmedDestination.value = label;
    location.destinationArea.value = label;
    location.addressNameController.text = label;
    location.streetController.clear();
    location.detailsController.clear();
    // Clear the old geometry immediately; only routes to the accepted target
    // may subsequently populate the map and navigation instructions.
    location.routePoints.clear();
    trackingRoutePoints.clear();
    trackingRouteDistanceMeters.value = 0;
    trackingRouteDurationSeconds.value = 0;
    trackingNextStepInstruction.value = '';
    trackingNextManeuver.value = '';
    trackingNextStepDistanceMeters.value = 0;
    _lastTrackingRouteDestination = null;
    ++_trackingRouteRequestId;
    unawaited(_refreshAssignedDriverRoute());
  }

  void _stopRealTracking() {
    ++_trackingRouteRequestId;
    _driverAnimationTarget = null;
    _driverAnimationStart = null;
    _driverMarkerAnimationTimer?.cancel();
    _driverMarkerAnimationTimer = null;
    _passengerPositionSubscription?.cancel();
    _passengerPositionSubscription = null;
    if (Get.isRegistered<TrackingHubService>()) {
      unawaited(
          Get.find<TrackingHubService>().setRideSubscriptions(const <int>{}));
    }
  }

  void _animateTrackedDriver(DriverTrackingSnapshot target) {
    final current = trackedDriver.value;
    if (current != null && !target.updatedAt.isAfter(current.updatedAt)) return;
    _driverMarkerAnimationTimer?.cancel();
    _driverAnimationStart = current ?? target;
    _driverAnimationTarget = target;
    _driverAnimationStartedAt = DateTime.now();
    final sampleGap = current == null
        ? const Duration(milliseconds: 1200)
        : target.updatedAt.difference(current.updatedAt);
    _driverAnimationDuration = Duration(
      milliseconds: sampleGap.inMilliseconds.clamp(700, 2800),
    );
    if (current == null) {
      trackedDriver.value = target;
      return;
    }
    _driverMarkerAnimationTimer = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) {
        final from = _driverAnimationStart;
        final to = _driverAnimationTarget;
        final startedAt = _driverAnimationStartedAt;
        if (from == null || to == null || startedAt == null) return;
        final progress = (DateTime.now().difference(startedAt).inMilliseconds /
                _driverAnimationDuration.inMilliseconds)
            .clamp(0.0, 1.0);
        if (progress >= 1) {
          trackedDriver.value = to;
          _driverMarkerAnimationTimer?.cancel();
          _driverMarkerAnimationTimer = null;
          return;
        }
        trackedDriver.value = DriverTrackingSnapshot(
          driverId: to.driverId,
          location: RideCoordinate(
            latitude: from.location.latitude +
                (to.location.latitude - from.location.latitude) * progress,
            longitude: from.location.longitude +
                (to.location.longitude - from.location.longitude) * progress,
          ),
          heading: _interpolateHeading(from.heading, to.heading, progress),
          updatedAt: to.updatedAt,
        );
      },
    );
  }

  double? _interpolateHeading(double? from, double? to, double progress) {
    if (to == null) return from;
    if (from == null) return to;
    final delta = ((to - from + 540) % 360) - 180;
    return (from + delta * progress + 360) % 360;
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
    final lastRequestedAt = _lastTrackingRouteRequestedAt;
    final requestedRecently = lastRequestedAt != null &&
        DateTime.now().difference(lastRequestedAt) <
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
    if (!targetChanged && (!originChanged || requestedRecently)) return;

    if (targetChanged) trackingRoutePoints.clear();

    _lastTrackingRouteOrigin = origin;
    _lastTrackingRouteDestination = targetCoordinate;
    _lastTrackingRouteRequestedAt = DateTime.now();
    final requestId = ++_trackingRouteRequestId;
    try {
      final route = await routeRepository.getDrivingRoute(
        origin: LatLng(origin.latitude, origin.longitude),
        destination: target,
        includeSteps: true,
      );
      if (requestId == _trackingRouteRequestId) {
        trackingRoutePoints.assignAll(route.points);
        trackingRouteDistanceMeters.value = route.distanceMeters;
        trackingRouteDurationSeconds.value = route.durationSeconds;
        final nextStep = route.steps.isEmpty ? null : route.steps.first;
        trackingNextStepInstruction.value = nextStep?.instruction ?? '';
        trackingNextManeuver.value = nextStep?.maneuver ?? '';
        trackingNextStepDistanceMeters.value = nextStep?.distanceMeters ?? 0;
      }
    } catch (_) {
      // Retain the last confirmed route during a temporary maps failure.
      if (requestId == _trackingRouteRequestId) _lastTrackingRouteOrigin = null;
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
    _offersDeadlineTimer?.cancel();
    // Cancellation is a terminal booking state. Clear the same transient
    // booking data used by "start a new ride" so the next booking cannot
    // reuse the cancelled route, vehicle, offer, or payment state.
    prepareNewRide();
    cancellationReason.value = reason;
    Get.offNamed<void>(RideRoutes.requestThanks);
  }

  void prepareNewRide() {
    moreThanFourPassengers.value = false;
    passengerNotes.value = '';
    // The passenger foreground location service is only needed while a ride
    // is active. Stop it before clearing the request id so it cannot keep
    // consuming GPS after the rider returns to the booking flow.
    _stopRealTracking();
    _offersDeadlineTimer?.cancel();
    ++_offersWatchGeneration;
    _requestId = null;
    _confirmedRouteVersion = 0;
    _lastPassengerLocationPublished = null;
    if (Get.isRegistered<TrackingHubService>()) {
      unawaited(
          Get.find<TrackingHubService>().setRideSubscriptions(const <int>{}));
      unawaited(Get.find<TrackingHubService>().clearNearbyDriverSubscription());
    }
    currentDraft.value = null;
    autoAcceptMatchingPrice.value = false;
    _autoAcceptAttempts.clear();
    quote.value = null;
    acceptedOffer.value = null;
    driverOffers.clear();
    requestViewers.clear();
    nearbyDrivers.clear();
    isDriverAssigned.value = false;
    assignedDriverName.value = '';
    assignedDriverPhone.value = '';
    offeredPrice.value = 0;
    routeDistanceKm.value = 0;
    activeRideStatus.value = '';
    activeRidePaymentCompleted.value = false;
    customerPaymentEnabled.value = false;
    cashCollectionApproval.value = null;
    cancellationReason.value = '';
    cancellationReasonController.clear();
    isSearchingForDriver.value = false;
    trackingRoutePoints.clear();
    trackingRouteDistanceMeters.value = 0;
    trackingRouteDurationSeconds.value = 0;
    trackingNextStepInstruction.value = '';
    trackingNextManeuver.value = '';
    trackingNextStepDistanceMeters.value = 0;
    trackedDriver.value = null;
    trackedPassenger.value = null;
    _lastTrackingRouteOrigin = null;
    _lastTrackingRouteDestination = null;
    _lastTrackingRouteRequestedAt = null;
    _trackingRouteRequestId++;
    selectedVehicle.value = null;
    hasSelectedTransport.value = false;
    selectedServiceKindId.value = null;
    homeServiceIndex.value = -1;
    serviceType.value = RideServiceType.transport;
    catalogVehicles.clear();
    catalogError.value = '';
    if (Get.isRegistered<LocationController>()) {
      Get.find<LocationController>().resetForNewRide();
    }
    // Keep only the administration-selected default service when enabled.
    applyAdminDefaultServiceKind();
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
    _hubEventSubscription?.cancel();
    _hubConnectionSubscription?.cancel();
    _driverMarkerAnimationTimer?.cancel();
    _offersDeadlineTimer?.cancel();
    _passengerPositionSubscription?.cancel();
    cancellationReasonController.dispose();
    super.onClose();
  }
}
