import '../../../shared/widgets/ride_financial_follow_up.dart';
import '../../../shared/widgets/live_tracking_marker_icons.dart';
import '../../../shared/widgets/live_route_polyline.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/cache/persistent_network_image.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_models.dart';
import '../../../core/utils/utc_timestamp.dart';
import '../../../core/realtime/tracking_hub_service.dart';
import '../../../core/realtime/nearby_driver_presence.dart';
import '../../../core/realtime/realtime_state_binding.dart';
import '../../../core/realtime/state_change_coordinator.dart';
import '../../../core/services/auth_session_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/startup_connection_service.dart';
import '../../../core/services/ride_preferences.dart';
import '../../../core/services/offer_arrival_notifier.dart';
import '../../../core/services/ride_arrival_notifier.dart';
import '../../account/account_routes.dart';
import '../home/repositories/service_kind_repository.dart';
import '../location_selection/controllers/location_selection_controller.dart';
import '../location_selection/repositories/route_repository.dart';
import '../models/ride_models.dart';
import '../models/tracked_driver_motion.dart';
import '../models/rider_vehicle_location.dart';
import '../models/service_kind_models.dart';
import '../negotiation/repositories/ride_negotiation_repository.dart';
import '../ride_routes.dart';
import '../vehicle_selection/repositories/service_catalog_repository.dart';

class RideController extends GetxController
    with WidgetsBindingObserver, GetTickerProviderStateMixin {
  RideController(this._repository, this._session,
      [this._catalogRepository,
      ServiceKindRepository? serviceKinds,
      RouteRepository? routeRepository,
      OfferArrivalNotifier? offerNotifier])
      : _serviceKinds = serviceKinds,
        _routeRepository = routeRepository,
        _offerNotifier = offerNotifier ?? OfferArrivalNotifier();

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
  final OfferArrivalNotifier _offerNotifier;
  final RxnString pendingRatingRideId = RxnString();
  final RxBool checkingPendingRating = false.obs;
  final Rxn<Map<String, Object?>> driverCancellationRequest =
      Rxn<Map<String, Object?>>();
  final RxBool isDecidingDriverCancellation = false.obs;
  final RxBool awaitingCancellationStatus = false.obs;
  final RxnString cancellationStatusError = RxnString();
  Future<bool>? _ratingCheck;
  final Set<String> _ratedRideIds = <String>{};
  bool _paused = false;

  bool _activeSnapshotQueued = false;
  Future<void>? _activeSnapshotTask;
  int _legacyStateRevision = 0;
  int get _stateEpoch =>
      _legacyStateRevision +
      (Get.isRegistered<TrackingHubService>()
          ? Get.find<TrackingHubService>()
              .stateChanges
              .epochForResources(const {'ride'})
          : 0);
  int get _catalogEpoch => Get.isRegistered<TrackingHubService>()
      ? Get.find<TrackingHubService>()
          .stateChanges
          .epochForResources(const {'catalog'})
      : 0;
  RideArrivalNotifier? _arrivalAlerts;
  RideArrivalNotifier? _arrivalNotifier() {
    final userId = _session.currentUserId.value;
    if (userId == null ||
        !Get.isRegistered<ApiClient>() ||
        !Get.isRegistered<TrackingHubService>()) return null;
    if (_arrivalAlerts?.userId != userId) {
      _arrivalAlerts?.onClose();
      _arrivalAlerts = RideArrivalNotifier(
          Get.find<ApiClient>(), Get.find<TrackingHubService>(),
          userId: userId)
        ..onInit();
    }
    return _arrivalAlerts;
  }

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
  String _sessionPaymentPreference = 'cash';
  void selectPaymentPreference(String value) {
    preferredPaymentMethod.value = value;
    _sessionPaymentPreference = value;
  }

  final RxString activePaymentMethodCode = 'cash'.obs;
  final RxBool paymentRequiredBeforeStart = false.obs;
  String? _paymentChoiceRideId;
  bool _paymentPageMounted = false;
  bool _mandatoryPaymentPageMounted = false;
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
  final assignedVehicleModel = ''.obs;
  final assignedPlateNumber = ''.obs;
  final assignedPassengerSeats = RxnInt();
  final assignedDriverRating = 0.0.obs;
  final assignedDriverPhotoUrl = ''.obs;
  final assignedDriverCompletedTrips = 0.obs;
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

  /// Only the server's persisted dispatch recipients belong in this list.
  final RxList<RideRequestViewer> requestRecipients = <RideRequestViewer>[].obs;
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
  final Rxn<DriverTrackingSnapshot> trackedVehicle =
      Rxn<DriverTrackingSnapshot>();
  final Rxn<DriverTrackingSnapshot> _vehicleGpsSample =
      Rxn<DriverTrackingSnapshot>();
  DriverTrackingSnapshot? get displayedVehicle => _isTripInProgress
      ? trackedVehicle.value
      : trackedVehicle.value ?? trackedDriver.value;
  DriverTrackingSnapshot? get latestVehicleGpsSample => _isTripInProgress
      ? _vehicleGpsSample.value
      : _vehicleGpsSample.value ?? latestDriverGpsSample;
  final RxBool vehicleUsesPassengerGps = false.obs;
  Position? _latestPassengerFix;
  bool _passengerVehicleFixExpired = false;
  Position? _lastValidatedVehicleFix;
  String? _localVehicleRideId;
  bool? _vehicleWasInProgress;
  DateTime? _vehiclePhaseStartedAt;
  Worker? _vehiclePhaseWorker;
  Worker? _vehicleAccountWorker;
  Worker? _trackingRouteGeometryWorker;
  Timer? _vehicleFreshnessTimer;
  AnimationController? _vehicleAnimation;
  Duration? _lastVehicleAnimationFrameAt;
  DriverTrackingSnapshot? _vehicleAnimationStart;
  DriverTrackingSnapshot? _vehicleAnimationTarget;
  bool _vehicleTargetIsPassenger = false;
  final RxList<LatLng> trackingRoutePoints = <LatLng>[].obs;
  final RxInt trackingRouteDistanceMeters = 0.obs;
  final RxInt trackingRouteDurationSeconds = 0.obs;
  final RxString trackingNextStepInstruction = ''.obs;
  final RxString trackingNextManeuver = ''.obs;
  final RxInt trackingNextStepDistanceMeters = 0.obs;
  StreamSubscription<TrackingHubEvent>? _hubEventSubscription;
  StreamSubscription<void>? _hubConnectionSubscription;
  StreamSubscription<void>? _apiRecoverySubscription;
  Timer? _automaticSyncTimer;
  Timer? _liveRideRefreshTimer;
  bool _automaticSyncInFlight = false;
  Timer? _offersDeadlineTimer;
  StreamSubscription<Position>? _passengerPositionSubscription;
  Future<void>? _passengerPositionStartTask;
  Timer? _passengerPositionRetry;
  Timer? _passengerPublishRetry;
  bool _realTrackingActive = false;
  int _passengerTrackingGeneration = 0;
  Map<String, Object?>? _pendingPassengerLocation;
  bool _passengerPublishInFlight = false;
  final RxnString passengerLocationError = RxnString();
  final RxBool passengerLocationApproximate = false.obs;
  DateTime? _lastPassengerPositionObservedAt;
  bool _passengerLocationPermissionNoticeShown = false;
  DriverTrackingSnapshot? _driverAnimationTarget;
  final RxnString chatRideId = RxnString();
  String? get _requestId => chatRideId.value;
  set _requestId(String? value) {
    if (value != chatRideId.value) {
      _clearLocalVehicleContinuity();
      _latestPassengerFix = null;
      _vehiclePhaseStartedAt =
          _isTripInProgress ? DateTime.now().toUtc() : null;
      _vehicleAnimation?.stop();
      _driverAnimationTarget = null;
      _vehicleAnimationStart = null;
      _vehicleAnimationTarget = null;
      trackedDriver.value = null;
      trackedVehicle.value = null;
      _vehicleGpsSample.value = null;
      trackedPassenger.value = null;
      vehicleUsesPassengerGps.value = false;
    }
    chatRideId.value = value;
  }

  bool _isResumingRequest = false;
  bool _searchMutationInProgress = false;
  final RxBool isRetryingSearch = false.obs;
  final RxnString searchRetryError = RxnString();
  int _searchSnapshotRevision = 0;
  int _requestRecipientsRevision = 0;
  int _offersWatchGeneration = 0;
  bool _hasCheckedForOpenRide = false;
  int _catalogRequestId = 0;
  int _quoteRequestId = 0;
  NearbyDriverPresence? _nearbyPresence;
  Worker? _nearbyFilterWorker;
  DateTime? _lastPassengerLocationPublished;
  RideCoordinate? _lastTrackingRouteOrigin;
  RideCoordinate? _lastTrackingRouteDestination;
  DateTime? _lastTrackingRouteRequestedAt;
  int _trackingRouteRequestId = 0;
  Future<void>? _trackingRouteTask;
  bool _trackingRouteRefreshRequested = false;
  DriverTrackingSnapshot? _remainingRouteSample;
  List<LatLng>? _remainingRouteTail;
  Set<Polyline>? _cachedTrackingPolylines;
  List<LatLng>? _cachedTrackingPoints;
  Set<Polyline>? _cachedTrackingTravelled;
  bool? _cachedTrackingInProgress;
  bool? _cachedBookingRouteComplete;
  Worker? _bookingMapGeometryWorker;
  Set<Polyline>? _cachedTravelledPolylines;
  DriverTrackingSnapshot? _cachedTravelledFirst;
  DriverTrackingSnapshot? _cachedTravelledLast;
  int _confirmedRouteVersion = 0;
  final RxList<DriverTrackingSnapshot> _travelledDriverSamples =
      <DriverTrackingSnapshot>[].obs;
  bool _bookingRouteLoading = false;
  int _bookingRouteRequestId = 0;
  bool hasShownTripSharePrompt = false;

  String? get currentRideId => _requestId;
  bool get cancellationReviewPending {
    if (_requestId == null) return false;
    if (awaitingCancellationStatus.value ||
        const {'8', 'CancellationPending'}.contains(activeRideStatus.value))
      return true;
    final request = driverCancellationRequest.value;
    if (request == null) return false;
    final status = _asInt(request['status']);
    return const {0, 2, 9, 10, 11, 12}.contains(status) ||
        (status == 5 &&
            const {'7', 'Cancelled'}.contains(activeRideStatus.value));
  }

  Future<bool> restorePendingCancellation() async {
    if (!Get.isRegistered<ApiClient>()) return false;
    final epoch = _stateEpoch;
    final userId = _session.currentUserId.value;
    final result = await Get.find<ApiClient>().execute<Object?>(
        model: 'RideCancellationRequestModel',
        operation: 'get',
        data: {'pendingOnly': true});
    if (isClosed ||
        userId != _session.currentUserId.value ||
        epoch != _stateEpoch) throw const StateSnapshotSuperseded();
    if (result is ApiFailure)
      throw const FormatException('تعذر التحقق من حالة الإلغاء.');
    if (result is! ApiSuccess || result.data is! Map) return false;
    final request = Map<String, Object?>.from(result.data as Map);
    final rideId = request['rideId']?.toString();
    if (rideId == null) return false;
    _requestId = rideId;
    activeRideStatus.value = '${request['rideStatus'] ?? 8}';
    driverCancellationRequest.value = request;
    if (!cancellationReviewPending) return false;
    if (Get.isRegistered<TrackingHubService>()) {
      await Get.find<TrackingHubService>()
          .setRideSubscriptions({int.parse(rideId)});
    }
    openActiveRide();
    return true;
  }

  DateTime get searchTime => DateTime.now();

  bool get bookingLocked =>
      _requestId != null ||
      pendingRatingRideId.value != null ||
      isSubmittingRequest.value ||
      checkingPendingRating.value;

  bool get mandatoryPaymentPending =>
      _requestId != null &&
      paymentRequiredBeforeStart.value &&
      !activeRidePaymentCompleted.value;

  void applyPaymentChoiceSnapshot(Map<Object?, Object?> ride) {
    final code = ride['paymentMethodCode']?.toString().trim();
    if (code != null && code.isNotEmpty) {
      if (_paymentChoiceRideId != _requestId ||
          activePaymentMethodCode.value.toLowerCase() != code.toLowerCase()) {
        final method = AppEnvironment.paymentMethods
            .where((item) => item.id.toLowerCase() == code.toLowerCase())
            .firstOrNull;
        final selection = method?.id ?? code;
        if (_paymentChoiceRideId == _requestId)
          _sessionPaymentPreference = selection;
        preferredPaymentMethod.value = selection;
      }
      activePaymentMethodCode.value = code;
      _paymentChoiceRideId = _requestId;
    }
    if (ride['paymentRequiredBeforeStart'] is bool) {
      paymentRequiredBeforeStart.value =
          ride['paymentRequiredBeforeStart'] == true;
    }
  }

  Future<void> openFinancialFollowUp(String rideId) async {
    final id = int.tryParse(rideId);
    if (id == null) return;
    await Get.to<void>(() => RideFinancialFollowUp(
        rideId: id,
        onPay: () async {
          final detail = await _repository.getRideDetail(rideId);
          final ride = detail['ride'];
          if (ride is! Map) throw const FormatException('تعذر تحديث الفاتورة.');
          _requestId = rideId;
          _restoreRideSnapshot(rideId, Map<String, Object?>.from(ride));
          activeRidePaymentCompleted.value = detail['paymentCompleted'] == true;
          await Get.toNamed<void>(RideRoutes.payment);
          if (_requestId == rideId) prepareNewRide();
        }));
  }

  final confirmingBoarding = false.obs;
  final passengerBoarded = false.obs;
  bool _boardingDialogOpen = false;
  Future<void> confirmBoarding() async {
    final rideId = int.tryParse(currentRideId ?? '');
    if (rideId == null || confirmingBoarding.value || _boardingDialogOpen)
      return;
    final arrived = activeRideStatus.value == '9' ||
        activeRideStatus.value == 'DriverArrived';
    _boardingDialogOpen = true;
    final confirmed = await Get.dialog<bool>(AlertDialog(
      title: const Text('تأكيد الصعود إلى المركبة'),
      content: Text(arrived
          ? 'هل التقيت بالسائق وصعدت إلى المركبة الصحيحة فعلياً؟'
          : 'استخدم هذا الخيار فقط إذا التقيت بالسائق عند نقطة الانطلاق وصعدت إلى المركبة فعلياً، وتعذر إثبات الوصول بالموقع. لا تؤكد وأنت بعيد عن السائق.'),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('رجوع')),
        FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('نعم، صعدت إلى المركبة'))
      ],
    )).whenComplete(() => _boardingDialogOpen = false);
    if (confirmed != true) return;
    if (currentRideId != '$rideId' || confirmingBoarding.value) return;
    confirmingBoarding.value = true;
    var boardingAccepted = false;
    try {
      final result = await Get.find<ApiClient>().execute<Object?>(
          model: 'RideServiceModel',
          operation: arrived ? 'board' : 'confirmPickup',
          data: {
            'rideId': rideId,
            'reason':
                'أكد الراكب وجود السائق وصعوده فعلياً عند نقطة الانطلاق؛ تعذر إثبات الوصول بالموقع.'
          });
      if (result is ApiFailure)
        throw FormatException(result.problem.detail ?? result.problem.title);
      final acknowledgement = (result as ApiSuccess).data;
      if (acknowledgement is! Map ||
          _asInt(acknowledgement['id']) != rideId ||
          acknowledgement['passengerBoardedAtUtc'] == null) {
        throw const FormatException(
            'تعذر التحقق من تأكيد الصعود. تجري مزامنة الرحلة تلقائياً.');
      }
      if (currentRideId != '$rideId') return;
      boardingAccepted = true;
      passengerBoarded.value = true;
      await refreshActiveRide(requireSuccess: true);
    } catch (error) {
      if (boardingAccepted) {
        Get.snackbar('تم تأكيد الصعود',
            'تجري مزامنة بقية بيانات الرحلة تلقائياً عند عودة الاتصال.');
      } else {
        Get.snackbar('تعذر تأكيد الصعود', _searchErrorMessage(error));
      }
    } finally {
      confirmingBoarding.value = false;
    }
  }

  void skipRating() {
    openRequiredRating();
  }

  void openActiveRide() {
    if (pendingRatingRideId.value != null) {
      openRequiredRating();
      return;
    }
    final target = cancellationReviewPending
        ? RideRoutes.cancellationStatus
        : mandatoryPaymentPending
            ? RideRoutes.payment
            : RideRoutes.driverLocation;
    if (isClosed || Get.currentRoute == target) return;
    Get.offAllNamed<void>(target);
  }

  void setPaymentPageMounted(bool mounted) {
    _paymentPageMounted = mounted;
    _mandatoryPaymentPageMounted = mounted && mandatoryPaymentPending;
  }

  void reconcilePaymentNavigation() {
    if (pendingRatingRideId.value != null) {
      openRequiredRating();
      return;
    }
    if (mandatoryPaymentPending &&
        !_paymentPageMounted &&
        Get.currentRoute != RideRoutes.rideCancel) {
      openActiveRide();
    } else if (_mandatoryPaymentPageMounted &&
        !mandatoryPaymentPending &&
        !activeRidePaymentCompleted.value &&
        activePaymentMethodCode.value.toLowerCase() == 'cash') {
      // A cash choice may have committed even if its response was lost.
      // Leave the required step only after a server snapshot confirms it.
      openActiveRide();
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _vehiclePhaseWorker = ever(activeRideStatus, (_) {
      if (_vehicleWasInProgress != _isTripInProgress) {
        _vehicleWasInProgress = _isTripInProgress;
        _clearLocalVehicleContinuity();
        _vehiclePhaseStartedAt =
            _isTripInProgress ? DateTime.now().toUtc() : null;
        _vehicleAnimation?.stop();
        _vehicleAnimationTarget = null;
        _vehicleAnimationStart = null;
        trackedVehicle.value = null;
        _vehicleGpsSample.value = null;
        vehicleUsesPassengerGps.value = false;
        _lastTrackingRouteOrigin = null;
        _lastTrackingRouteDestination = null;
        trackingRoutePoints.clear();
        ++_trackingRouteRequestId;
      }
      _syncVehicleSource();
    });
    _observeTrackingGeometry();
    _vehicleAccountWorker = ever(_session.currentUserId, (_) {
      _stopRealTracking();
      trackedDriver.value = null;
      trackedVehicle.value = null;
      trackedPassenger.value = null;
    });
    _automaticSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_syncCurrentRide());
    });
    _authenticationWorker =
        ever(_session.isAuthenticated, (bool authenticated) {
      _nearbyPresence?.reset();
      if (authenticated) {
        unawaited(_refreshServicesAfterLogin());
        if (Get.isRegistered<TrackingHubService>())
          unawaited(
              Get.find<TrackingHubService>().setUserEventListening(this, true));
      } else {
        _stopRealTracking();
        trackedPassenger.value = null;
      }
    });
    _defaultServiceWorker = ever(checkingPendingRating, (bool checking) {
      if (!checking) unawaited(applyAdminDefaultServiceKind());
    });
    _nearbyFilterWorker =
        everAll([selectedVehicle, selectedServiceKindId], (_) {
      _nearbyPresence?.reset();
    });
    if (Get.isRegistered<StartupConnectionService>()) {
      _apiRecoverySubscription =
          Get.find<StartupConnectionService>().recovered.listen((_) {
        unawaited(_recoverAfterApiOutage());
      });
    }
    unawaited(loadServiceCatalog());
    unawaited(_loadHomeServices());
    unawaited(_loadTrackingIcons());
    if (Get.isRegistered<TrackingHubService>()) {
      final hub = Get.find<TrackingHubService>();
      hub.stateChanges.register(this, _reconcileStateChanges);
      if (_session.isAuthenticated.value)
        unawaited(hub.setUserEventListening(this, true));
      _hubEventSubscription = hub.events.listen(_handleHubEvent);
      _hubConnectionSubscription = hub.connectionRestored.listen((_) {
        unawaited(_nearbyPresence?.refresh());
        unawaited(_publishPendingPassengerLocation());
        final rideId = _requestId;
        if (rideId != null && isSearchingForDriver.value) {
          unawaited(
            _refreshSearchSnapshotSafely(rideId, _offersWatchGeneration),
          );
        } else if (rideId != null) {
          unawaited(refreshActiveRide());
        } else {
          unawaited(restoreOpenRideOnLaunch(force: true));
        }
      });
    }
  }

  Future<void> _reconcileStateChanges(List<StateChange> changes) async {
    if (isClosed || !_session.isAuthenticated.value) return;
    if (changes.any((change) => change.resource == 'catalog')) {
      if (isHomeServicesLoading.value || isCatalogLoading.value)
        throw StateError('Catalog refresh is in progress');
      await loadHomeServices(requireSuccess: true);
      await loadServiceCatalog(requireSuccess: true);
      if (homeServicesError.value.isNotEmpty)
        throw StateError(homeServicesError.value);
    }
    if (!changes.any((change) =>
        change.resource == 'ride' &&
        (_requestId == null || '${change.resourceId}' == _requestId))) return;
    if (_searchMutationInProgress ||
        isRespondingToOffer.value ||
        isCancellingRide.value) {
      throw StateError('Ride command is still reconciling');
    }
    final rideId = _requestId;
    if (rideId == null) {
      await restoreOpenRideOnLaunch(force: true, requireSuccess: true);
    } else if (isSearchingForDriver.value) {
      await _refreshSearchSnapshot(rideId, _offersWatchGeneration,
          requireSuccess: true);
    } else {
      await refreshActiveRide(requireSuccess: true);
    }
  }

  Future<void> _recoverAfterApiOutage() async {
    if (isClosed || _paused) return;
    unawaited(_nearbyPresence?.refresh());
    unawaited(loadHomeServices());
    unawaited(loadServiceCatalog());
    if (!_session.isAuthenticated.value) return;
    final rideId = _requestId;
    if (rideId != null && isSearchingForDriver.value) {
      await _refreshSearchSnapshotSafely(rideId, _offersWatchGeneration);
    } else if (rideId != null) {
      await refreshActiveRide();
    } else {
      await restoreOpenRideOnLaunch(force: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    _nearbyPresence?.setForeground(!_paused);
    if (Get.isRegistered<TrackingHubService>())
      unawaited(Get.find<TrackingHubService>().setForeground(!_paused));
    if (_paused) {
      _vehicleAnimation?.stop();
      if (_vehicleGpsSample.value != null) {
        trackedVehicle.value = _vehicleGpsSample.value;
      }
      _liveRideRefreshTimer?.cancel();
      _liveRideRefreshTimer = null;
      return;
    }
    if (_realTrackingActive) unawaited(_startPassengerPositionTracking());
    if (pendingRatingRideId.value != null) openRequiredRating();
    final rideId = _requestId;
    if (rideId != null && isSearchingForDriver.value) {
      unawaited(_refreshSearchSnapshotSafely(rideId, _offersWatchGeneration));
    } else if (rideId != null) {
      unawaited(refreshActiveRide());
    } else {
      unawaited(restoreOpenRideOnLaunch(force: true));
    }
  }

  Future<void> _syncCurrentRide() async {
    if (_paused ||
        isClosed ||
        !_session.isAuthenticated.value ||
        _automaticSyncInFlight ||
        _searchMutationInProgress ||
        isRespondingToOffer.value ||
        isCancellingRide.value) return;
    if (Get.isRegistered<StartupConnectionService>() &&
        Get.find<StartupConnectionService>().runtimeUnavailable.value) return;
    if (Get.isRegistered<TrackingHubService>()) {
      final hub = Get.find<TrackingHubService>();
      if (hub.isStateSynchronized.value && hub.stateChanges.covers(this))
        return;
    }
    final rideId = _requestId;
    if (rideId == null) return;
    _automaticSyncInFlight = true;
    try {
      if (isSearchingForDriver.value) {
        await _refreshSearchSnapshotSafely(rideId, _offersWatchGeneration);
      } else if (pendingRatingRideId.value == null) {
        await refreshActiveRide();
      }
    } finally {
      _automaticSyncInFlight = false;
    }
  }

  void _queueLiveRideRefresh() {
    if (isClosed || _paused || _liveRideRefreshTimer != null) return;
    _liveRideRefreshTimer = Timer(const Duration(milliseconds: 100), () {
      _liveRideRefreshTimer = null;
      if (isClosed || _paused) return;
      final rideId = _requestId;
      if (rideId == null) return;
      if (isSearchingForDriver.value) {
        unawaited(_refreshSearchSnapshotSafely(rideId, _offersWatchGeneration));
      } else {
        unawaited(refreshActiveRide());
      }
    });
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
    if (payload['action'] == 'ride_arrival_alert') {
      final arrivalRideId = int.tryParse(payload['rideId'] ?? '');
      if (arrivalRideId != null)
        await _arrivalNotifier()?.refresh(arrivalRideId);
      return;
    }
    if (!await ensureNoPendingRating()) return;
    if (mandatoryPaymentPending) {
      openActiveRide();
      return;
    }
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
        final notificationDetail = await _repository.getRideDetail(rideId);
        final notificationRide = notificationDetail['ride'];
        if (notificationRide is Map &&
            {6, 7}.contains(_asInt(notificationRide['status']))) {
          await openFinancialFollowUp(rideId);
          return;
        }
        await resumeOpenRide(rideId);
        await _markNotificationRead(notificationId);
        if (mandatoryPaymentPending) return;
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
      action == 'open_wallet_top_up' ||
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
  Future<void> restoreOpenRideOnLaunch(
      {bool force = false, bool requireSuccess = false}) async {
    if ((!force && _hasCheckedForOpenRide) || !_session.isAuthenticated.value)
      return;
    _hasCheckedForOpenRide = true;
    final epoch = _stateEpoch;
    final userId = _session.currentUserId.value;

    try {
      if (await restorePendingCancellation()) return;
      if (!await ensureNoPendingRating()) {
        if (requireSuccess && pendingRatingRideId.value == null)
          throw StateError('تعذر التحقق من حالة التقييم.');
        return;
      }
      if (_requestId != null) return;
      final ride = await _repository.findLatestOpenRide();
      if (userId != _session.currentUserId.value || isClosed) return;
      if (epoch != _stateEpoch) throw const StateSnapshotSuperseded();
      if (ride == null) return;
      final rideId = ride['id']?.toString();
      final status = _asInt(ride['status']);
      if (rideId == null || rideId.isEmpty || status == null) return;

      _restoreRideSnapshot(rideId, ride);
      await _continueRestoredRide(rideId, status);
    } catch (_) {
      _hasCheckedForOpenRide = false;
      if (requireSuccess) rethrow;
      // Opening the home screen remains available when the network is offline.
    }
  }

  /// A server-backed gate: a failed check never authorizes another booking.
  Future<bool> ensureNoPendingRating({bool showError = false}) {
    final active = _ratingCheck;
    if (active != null) return active;
    final task = _checkPendingRating(showError: showError);
    _ratingCheck = task;
    return task.whenComplete(() => _ratingCheck = null);
  }

  Future<bool> _checkPendingRating({required bool showError}) async {
    if (!_session.isAuthenticated.value) return true;
    final epoch = _stateEpoch;
    final userId = _session.currentUserId.value;
    checkingPendingRating.value = true;
    try {
      final pending = await _repository.getPendingRating();
      if (isClosed ||
          userId != _session.currentUserId.value ||
          epoch != _stateEpoch) throw const StateSnapshotSuperseded();
      if (pending != null) {
        final rideId = pending['rideId'].toString();
        pendingRatingRideId.value = rideId;
        openRequiredRating();
        return false;
      }
      final previous = pendingRatingRideId.value;
      pendingRatingRideId.value = null;
      if (previous != null) _ratedRideIds.add(previous);
      return true;
    } on Object {
      _hasCheckedForOpenRide = false;
      if (showError) {
        Get.snackbar('تعذر التحقق من التقييم',
            'تحقق من الاتصال ثم أعد المحاولة قبل طلب رحلة جديدة.');
      }
      if (pendingRatingRideId.value != null) openRequiredRating();
      return false;
    } finally {
      checkingPendingRating.value = false;
    }
  }

  void openRequiredRating() {
    if (isClosed ||
        pendingRatingRideId.value == null ||
        // Let the customer finish a provider challenge and read its receipt.
        // The pending rating still prevents another booking.
        (Get.currentRoute == RideRoutes.payment &&
            !activeRidePaymentCompleted.value) ||
        Get.currentRoute == RideRoutes.review) return;
    Get.offAllNamed<void>(RideRoutes.review);
  }

  void ratingSubmitted(String rideId) {
    _ratedRideIds.add(rideId);
    if (pendingRatingRideId.value == rideId) pendingRatingRideId.value = null;
  }

  void _requireRating(String rideId) {
    if (_ratedRideIds.contains(rideId)) return;
    pendingRatingRideId.value = rideId;
    isSearchingForDriver.value = false;
    _offersDeadlineTimer?.cancel();
    openRequiredRating();
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
    if (status == 6 || status == 7) {
      await openFinancialFollowUp(rideId);
      return;
    }
    if (status == null || status == 6 || status == 7) {
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
    if (pendingRatingRideId.value != null || _requestId != rideId) return;
    startRealTracking();
    if (!isClosed) openActiveRide();
  }

  void _restoreRideSnapshot(String rideId, Map<String, Object?> ride) {
    _requestId = rideId;
    applyPaymentChoiceSnapshot(ride);
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
      paymentMethodCode: activePaymentMethodCode.value,
      pickupAddress: '${ride['pickupAddress'] ?? ''}',
      destinationAddress: '${ride['destinationAddress'] ?? ''}',
    );
    final location = Get.find<LocationController>();
    final pickupPoint = LatLng(pickupLatitude, pickupLongitude);
    final destinationPoint = LatLng(destinationLatitude, destinationLongitude);
    location.pickup.value = pickupPoint;
    location.destination.value = destinationPoint;
    // Only a road route returned by the provider may be shown as a route.
    // Coordinates alone must not create a straight line across buildings.
    location.routePoints.clear();
    unawaited(_refreshBookingRoute());
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

  Future<void> loadHomeServices({bool requireSuccess = false}) async {
    final serviceKinds = _serviceKinds;
    if (serviceKinds == null || isHomeServicesLoading.value) return;
    isHomeServicesLoading.value = true;
    homeServicesError.value = '';
    final epoch = _catalogEpoch;
    try {
      final values = await serviceKinds.getServices();
      if (isClosed) return;
      if (epoch != _catalogEpoch) throw const StateSnapshotSuperseded();
      homeServices.assignAll(values);
      await applyAdminDefaultServiceKind();
    } catch (_) {
      homeServicesError.value = 'تعذر تحميل أنواع الرحلات. حاول مرة أخرى.';
      if (requireSuccess) rethrow;
    } finally {
      isHomeServicesLoading.value = false;
    }
  }

  Worker? _authenticationWorker;
  Worker? _defaultServiceWorker;

  Future<void> _refreshServicesAfterLogin() async {
    if (isHomeServicesLoading.value) {
      await isHomeServicesLoading.stream.firstWhere((loading) => !loading);
    }
    await loadHomeServices();
    if (selectedServiceKindId.value != null && catalogVehicles.isEmpty) {
      await loadServiceCatalog();
    }
  }

  Future<void> ensureHomeServiceReady() async {
    if (isHomeServicesLoading.value) {
      await isHomeServicesLoading.stream.firstWhere((loading) => !loading);
    }
    if (homeServices.isEmpty && _serviceKinds != null) await loadHomeServices();
    await applyAdminDefaultServiceKind();
    if (isCatalogLoading.value) {
      await isCatalogLoading.stream.firstWhere((loading) => !loading);
    }
    if (selectedServiceKindId.value != null && catalogVehicles.isEmpty) {
      await loadServiceCatalog();
    }
  }

  Future<void> applyAdminDefaultServiceKind() async {
    // The catalog and the user's carousel interaction load asynchronously.
    // Never let a late default-service response overwrite a manual choice.
    if (selectedServiceKindId.value != null) return;
    var index =
        homeServices.indexWhere((item) => item.isDefault && item.id != null);
    if (index < 0) index = homeServices.indexWhere((item) => item.id != null);
    if (index < 0) return;
    await selectHomeService(index);
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

  Future<void> loadServiceCatalog(
      {int? requestedKindId, bool requireSuccess = false}) async {
    final epoch = _catalogEpoch;
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
      if (isClosed) return;
      if (epoch != _catalogEpoch) throw const StateSnapshotSuperseded();
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
      if (requireSuccess) rethrow;
      if (epoch != _catalogEpoch) return;
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
    ValueChanged<NearbyDriver>? onTap,
  }) =>
      (showNearbyDriversOnMaps ? nearbyDrivers : <NearbyDriver>[])
          .map(
            (driver) => Marker(
              markerId: MarkerId('nearby-${driver.id}'),
              position: LatLng(
                driver.location.latitude,
                driver.location.longitude,
              ),
              anchor: const ui.Offset(.5, .5),
              flat: true,
              rotation: driver.heading != null &&
                      driver.heading!.isFinite &&
                      driver.heading! >= 0 &&
                      driver.heading! < 360
                  ? driver.heading!
                  : 0,
              // A driver marker is an interactive object, not a map point
              // that may be used as the customer's pickup/destination.
              consumeTapEvents: onTap != null,
              onTap: onTap == null ? null : () => onTap(driver),
              infoWindow: onTap == null
                  ? InfoWindow(title: driver.name, snippet: driver.vehicleModel)
                  : InfoWindow.noText,
              icon: _approachingCarIcon.value ??
                  BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  ),
            ),
          )
          .toSet();

  bool get _isTripInProgress =>
      activeRideStatus.value == 'InProgress' || activeRideStatus.value == '5';

  bool get showNearbyDriversOnMaps =>
      !isDriverAssigned.value &&
      !const {
        '3',
        '4',
        '5',
        '9',
        'DriverAssigned',
        'DriverEnRoute',
        'DriverArrived',
        'InProgress'
      }.contains(activeRideStatus.value);

  NearbyDriver? get assignedDriverOnMap {
    final vehicle = displayedVehicle;
    if (vehicle == null) return null;
    return NearbyDriver(
      id: vehicle.driverId,
      name: assignedDriverName.value.isEmpty
          ? 'السائق'
          : assignedDriverName.value,
      location: vehicle.location,
      photoUrl: assignedDriverPhotoUrl.value.isNotEmpty
          ? assignedDriverPhotoUrl.value
          : acceptedOffer.value?.photoUrl ?? '',
      vehicleType: selectedVehicle.value?.type ?? RideVehicleType.car,
      rating: assignedDriverRating.value,
      vehicleModel: assignedVehicleModel.value,
      plateNumber: assignedPlateNumber.value,
      completedTrips: assignedDriverCompletedTrips.value,
      heading: vehicle.heading,
    );
  }

  Set<Marker> get trackingMarkers => <Marker>{
        if (displayedVehicle != null)
          Marker(
            markerId: const MarkerId('tracked-driver'),
            position: LatLng(
              displayedVehicle!.location.latitude,
              displayedVehicle!.location.longitude,
            ),
            rotation: displayedVehicle!.heading ?? 0,
            flat: true,
            anchor: const ui.Offset(.5, .5),
            consumeTapEvents: true,
            infoWindow: InfoWindow.noText,
            // An approaching car and an active-trip direction marker are
            // intentionally distinct. A profile pin is useful when choosing
            // a driver, but is less clear than a directional vehicle while
            // following a live route.
            icon: (_isTripInProgress
                    ? _inTripDirectionIcon.value
                    : _approachingCarIcon.value) ??
                BitmapDescriptor.defaultMarkerWithHue(
                  _isTripInProgress
                      ? BitmapDescriptor.hueBlue
                      : BitmapDescriptor.hueCyan,
                ),
          ),
      };

  void _observeTrackingGeometry() {
    _trackingRouteGeometryWorker ??= ever(trackingRoutePoints, (_) {
      _remainingRouteSample = null;
      _remainingRouteTail = null;
      _cachedTrackingPolylines = null;
    });
  }

  /// Route geometry follows confirmed GPS fixes. Interpolating the symbol must
  /// not copy and send thousands of unchanged vertices across the native map
  /// channel on every frame, including when a driver is off the planned route.
  List<LatLng> get remainingTrackingRoutePoints {
    _observeTrackingGeometry();
    final driver = latestVehicleGpsSample ?? displayedVehicle;
    final count = trackingRoutePoints.length;
    if (identical(driver, _remainingRouteSample) &&
        _remainingRouteTail != null) {
      return _remainingRouteTail!;
    }
    _remainingRouteSample = driver;
    if (driver == null || count < 2) {
      return _remainingRouteTail = trackingRoutePoints.toList(growable: false);
    }
    final current = LatLng(driver.location.latitude, driver.location.longitude);
    var nextIndex = 1;
    var nearestMeters = double.infinity;
    final longitudeScale = math.cos(current.latitude * math.pi / 180);
    for (var index = 0; index < trackingRoutePoints.length - 1; index++) {
      final a = trackingRoutePoints[index];
      final b = trackingRoutePoints[index + 1];
      final dx = (b.longitude - a.longitude) * longitudeScale;
      final dy = b.latitude - a.latitude;
      final lengthSquared = dx * dx + dy * dy;
      final progress = lengthSquared == 0
          ? 0.0
          : (((current.longitude - a.longitude) * longitudeScale * dx +
                      (current.latitude - a.latitude) * dy) /
                  lengthSquared)
              .clamp(0.0, 1.0);
      final point = LatLng(a.latitude + dy * progress,
          a.longitude + (b.longitude - a.longitude) * progress);
      final meters = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        point.latitude,
        point.longitude,
      );
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nextIndex = index + 1;
      }
    }
    // Keep the next road vertex, including a turn immediately ahead. When a
    // driver is off route, wait for routing instead of drawing a false shortcut.
    if (nearestMeters > 100) {
      return _remainingRouteTail = trackingRoutePoints.toList(growable: false);
    }
    return _remainingRouteTail = <LatLng>[
      current,
      ...trackingRoutePoints.skip(nextIndex)
    ];
  }

  /// Frames the current live route rather than the customer trip route. While
  /// the driver is on the way this means driver -> pickup; after the trip
  /// starts it becomes driver -> destination. The driver and target are both
  /// included even when the route provider has not returned its polyline yet.
  LatLngBounds? get trackingFocusBounds {
    final driver = displayedVehicle;
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
    final location = Get.find<LocationController>();
    _bookingMapGeometryWorker ??= ever(location.routePoints, (_) {
      _cachedTrackingPolylines = null;
    });
    final inProgress = _isTripInProgress;
    // Keep reactive dependencies registered even on a cache hit.
    final bookingPointCount = location.routePoints.length;
    final bookingComplete = location.hasCompleteRoute;
    final travelled = inProgress ? _travelledPolylines : null;
    if (_cachedTrackingPolylines != null &&
        identical(points, _cachedTrackingPoints) &&
        identical(travelled, _cachedTrackingTravelled) &&
        inProgress == _cachedTrackingInProgress &&
        bookingComplete == _cachedBookingRouteComplete)
      return _cachedTrackingPolylines!;
    _cachedTrackingPoints = points;
    _cachedTrackingTravelled = travelled;
    _cachedTrackingInProgress = inProgress;
    _cachedBookingRouteComplete = bookingComplete;
    return _cachedTrackingPolylines = <Polyline>{
      if (!inProgress && bookingPointCount >= 2)
        for (final route in location.polylines)
          LiveRoutePolyline.from(route.copyWith(
              colorParam: const ui.Color(0xFF8056D9), widthParam: 4)),
      if (travelled != null) ...travelled,
      if (points.length >= 2)
        LiveRoutePolyline(
          polylineId: const PolylineId('assigned-driver-route'),
          points: points,
          width: 6,
          color: inProgress
              ? const ui.Color(0xFF1A73E8)
              : const ui.Color(0xFF009DAD),
          zIndex: 2,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
    };
  }

  Set<Polyline> get _travelledPolylines {
    final first = _travelledDriverSamples.firstOrNull;
    final last = _travelledDriverSamples.lastOrNull;
    if (_cachedTravelledPolylines != null &&
        identical(first, _cachedTravelledFirst) &&
        identical(last, _cachedTravelledLast))
      return _cachedTravelledPolylines!;
    final segments = <List<LatLng>>[];
    DriverTrackingSnapshot? previous;
    for (final sample in _travelledDriverSamples) {
      final point = LatLng(sample.location.latitude, sample.location.longitude);
      final gap = previous == null
          ? null
          : sample.updatedAt.difference(previous.updatedAt);
      final distance = previous == null
          ? 0.0
          : Geolocator.distanceBetween(
              previous.location.latitude,
              previous.location.longitude,
              sample.location.latitude,
              sample.location.longitude);
      // A long outage has no observed road geometry. Never join its endpoints
      // with an invented travelled line.
      if (previous == null || gap!.inSeconds > 30 || distance > 500) {
        segments.add([point]);
      } else {
        segments.last.add(point);
      }
      previous = sample;
    }
    _cachedTravelledFirst = first;
    _cachedTravelledLast = last;
    return _cachedTravelledPolylines = {
      for (var index = 0; index < segments.length; index++)
        if (segments[index].length >= 2)
          LiveRoutePolyline(
              polylineId: PolylineId('travelled-driver-route-$index'),
              points: segments[index],
              width: 4,
              color: const ui.Color(0x665477A8),
              zIndex: 1)
    };
  }

  void _recordTravelledDriver(DriverTrackingSnapshot sample) {
    if (!_isTripInProgress) return;
    if (_travelledDriverSamples.isNotEmpty &&
        !sample.updatedAt.isAfter(_travelledDriverSamples.last.updatedAt))
      return;
    _travelledDriverSamples.add(sample);
    if (_travelledDriverSamples.length > 2000) {
      _travelledDriverSamples.removeRange(
          0, _travelledDriverSamples.length - 2000);
    }
  }

  void _restoreTravelledDriverSamples(Object? raw) {
    if (raw is! List) return;
    final samples = <DateTime, DriverTrackingSnapshot>{
      for (final sample in _travelledDriverSamples) sample.updatedAt: sample,
    };
    for (final item in raw.whereType<Map<Object?, Object?>>()) {
      final latitude = _asDouble(item['latitude']);
      final longitude = _asDouble(item['longitude']);
      final observed = parseUtcTimestamp(item['observedAtUtc']);
      if (latitude == null ||
          longitude == null ||
          observed == null ||
          !latitude.isFinite ||
          !longitude.isFinite ||
          latitude.abs() > 90 ||
          longitude.abs() > 180) continue;
      samples[observed] = DriverTrackingSnapshot(
          driverId: '${item['driverId'] ?? ''}',
          location: RideCoordinate(latitude: latitude, longitude: longitude),
          heading: _asDouble(item['bearing']),
          updatedAt: observed);
    }
    _travelledDriverSamples.assignAll(samples.values.toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt)));
  }

  Future<void> _refreshBookingRoute() async {
    final repository = _routeRepository;
    if (repository == null || _bookingRouteLoading || _isTripInProgress) return;
    final location = Get.find<LocationController>();
    if (location.routePoints.length >= 2) return;
    final pickup = location.pickup.value;
    final destination = location.destination.value;
    if (pickup == null || destination == null) return;
    final rideId = _requestId;
    final requestId = ++_bookingRouteRequestId;
    _bookingRouteLoading = true;
    try {
      final route = await repository.getDrivingRoute(
          origin: pickup, destination: destination);
      if (!isClosed &&
          requestId == _bookingRouteRequestId &&
          rideId == _requestId &&
          pickup == location.pickup.value &&
          destination == location.destination.value) {
        location.routePoints.assignAll(route.points);
      }
    } on Object {
      // The automatic ride refresh retries; no fabricated direct line is used.
    } finally {
      _bookingRouteLoading = false;
    }
  }

  NearbyDriverPresence get _nearby => _nearbyPresence ??= NearbyDriverPresence(
        drivers: nearbyDrivers,
        canRequest: () =>
            !isClosed &&
            (!Get.isRegistered<StartupConnectionService>() ||
                !Get.find<StartupConnectionService>().runtimeUnavailable.value),
        load: (center) {
          final selected = selectedVehicle.value;
          return _repository.getNearbyDrivers(
            pickup: center,
            serviceKindId:
                selected?.serviceKindId ?? selectedServiceKindId.value,
            serviceCatalogItemId: selected?.serviceCatalogItemId,
          );
        },
        subscribe: (center, drivers) async {
          if (!Get.isRegistered<TrackingHubService>()) return;
          final selected = selectedVehicle.value;
          await Get.find<TrackingHubService>().setNearbyDriverSubscription(
            serviceKindId:
                selected?.serviceKindId ?? selectedServiceKindId.value,
            serviceCatalogItemId: selected?.serviceCatalogItemId,
            pickupLatitude: center.latitude,
            pickupLongitude: center.longitude,
            radiusMeters: NearbyDriverPresence.radiusMeters.toInt(),
            initialDriverIds: drivers
                .map((driver) => int.tryParse(driver.id))
                .whereType<int>(),
          );
        },
        unsubscribe: () async {
          if (Get.isRegistered<TrackingHubService>()) {
            await Get.find<TrackingHubService>()
                .clearNearbyDriverSubscription();
          }
        },
        onDriver: (driver) => unawaited(_loadDriverPhotoMarker(driver)),
        onChanged: () {
          final selected = selectedNearbyDriver.value;
          if (selected != null) {
            selectedNearbyDriver.value = nearbyDrivers
                .firstWhereOrNull((item) => item.id == selected.id);
          }
        },
      );

  void setNearbyMapVisible(Object owner, bool visible) {
    if (isClosed) return;
    if (visible) {
      _nearby.setForeground(!_paused);
      _nearby.setMapVisible(owner, true);
    } else {
      _nearbyPresence?.setMapVisible(owner, false);
    }
  }

  /// Kept for existing callers; editable pickup/camera coordinates never
  /// replace the actual GPS center used by nearby-driver discovery.
  Future<void> loadNearbyDrivers({LatLng? center}) async =>
      _nearbyPresence?.refresh();

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
        await LiveTrackingMarkerIcons.build(inProgress: false);
    _inTripDirectionIcon.value =
        await LiveTrackingMarkerIcons.build(inProgress: true);
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

  Future<void> _startPassengerPositionTracking() {
    if (!_realTrackingActive ||
        isClosed ||
        _passengerPositionSubscription != null) {
      return Future<void>.value();
    }
    final existing = _passengerPositionStartTask;
    if (existing != null) return existing;
    final generation = _passengerTrackingGeneration;
    late final Future<void> task;
    task = _openPassengerPositionStream(generation).whenComplete(() {
      if (identical(_passengerPositionStartTask, task)) {
        _passengerPositionStartTask = null;
      }
    });
    _passengerPositionStartTask = task;
    return task;
  }

  bool _isPassengerTrackingCurrent(int generation) =>
      _realTrackingActive &&
      !isClosed &&
      generation == _passengerTrackingGeneration &&
      _requestId != null;

  Future<void> _openPassengerPositionStream(int generation) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (_isPassengerTrackingCurrent(generation)) {
          passengerLocationError.value =
              'فعّل خدمة الموقع لتحديث موقعك أثناء الرحلة.';
          _retryPassengerPositionStream(generation);
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (!_isPassengerTrackingCurrent(generation)) return;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!_isPassengerTrackingCurrent(generation)) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        passengerLocationError.value =
            'اسمح للتطبيق بالوصول إلى الموقع لتحديث موقعك.';
        _showPassengerLocationPermissionNotice(permission);
        return;
      }
      _passengerPositionRetry?.cancel();
      passengerLocationError.value = null;
      _passengerPositionSubscription = Geolocator.getPositionStream(
        locationSettings: _passengerLocationStreamSettings(),
      ).listen((position) {
        if (!_isPassengerTrackingCurrent(generation)) return;
        final latitude = position.latitude;
        final longitude = position.longitude;
        final observedAt = position.timestamp.toUtc();
        final age = DateTime.now().toUtc().difference(observedAt);
        final accuracy = position.accuracy;
        if (!latitude.isFinite ||
            !longitude.isFinite ||
            latitude.abs() > 90 ||
            longitude.abs() > 180 ||
            !accuracy.isFinite ||
            accuracy <= 0 ||
            age > const Duration(seconds: 30) ||
            age < const Duration(seconds: -5) ||
            (_lastPassengerPositionObservedAt != null &&
                observedAt.isBefore(_lastPassengerPositionObservedAt!))) return;
        _lastPassengerPositionObservedAt = observedAt;
        passengerLocationApproximate.value = accuracy > 75;
        trackedPassenger.value =
            RideCoordinate(latitude: latitude, longitude: longitude);
        _latestPassengerFix = position;
        _passengerVehicleFixExpired = false;
        _syncVehicleSource();
        if (vehicleUsesPassengerGps.value) {
          unawaited(_refreshAssignedDriverRoute());
        }
        final rideId = int.tryParse(_requestId ?? '');
        if (rideId == null || accuracy > 75) return;
        final heading = position.heading;
        final speed = position.speed;
        _pendingPassengerLocation = <String, Object?>{
          'rideId': rideId,
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
          'observedAtUtc': observedAt.toIso8601String(),
          if (heading.isFinite && heading >= 0 && heading < 360)
            'bearing': heading,
          if (speed.isFinite && speed >= 0 && speed <= 75) 'speed': speed,
        };
        unawaited(_publishPendingPassengerLocation());
      }, onError: (Object error) {
        if (!_isPassengerTrackingCurrent(generation)) return;
        _passengerPositionSubscription = null;
        passengerLocationError.value = 'تعذر تحديث موقعك، تجري إعادة المحاولة.';
        _retryPassengerPositionStream(generation);
      }, onDone: () {
        if (!_isPassengerTrackingCurrent(generation)) return;
        _passengerPositionSubscription = null;
        _retryPassengerPositionStream(generation);
      }, cancelOnError: true);
    } on Object {
      if (!_isPassengerTrackingCurrent(generation)) return;
      passengerLocationError.value = 'تعذر تشغيل الموقع، تجري إعادة المحاولة.';
      _retryPassengerPositionStream(generation);
    }
  }

  void _retryPassengerPositionStream(int generation) {
    _passengerPositionRetry?.cancel();
    if (!_isPassengerTrackingCurrent(generation) || _paused) return;
    _passengerPositionRetry = Timer(const Duration(seconds: 5), () {
      if (_isPassengerTrackingCurrent(generation)) {
        unawaited(_startPassengerPositionTracking());
      }
    });
  }

  Future<void> _publishPendingPassengerLocation() async {
    final generation = _passengerTrackingGeneration;
    final payload = _pendingPassengerLocation;
    if (!_isPassengerTrackingCurrent(generation) ||
        payload == null ||
        _passengerPublishInFlight ||
        !Get.isRegistered<TrackingHubService>()) return;
    final now = DateTime.now();
    final observed = parseUtcTimestamp(payload['observedAtUtc']);
    if (observed == null ||
        now.toUtc().difference(observed) > const Duration(seconds: 30)) {
      _pendingPassengerLocation = null;
      return;
    }
    final elapsed = _lastPassengerLocationPublished == null
        ? const Duration(seconds: 3)
        : now.difference(_lastPassengerLocationPublished!);
    if (elapsed < const Duration(seconds: 3)) {
      _passengerPublishRetry?.cancel();
      _passengerPublishRetry = Timer(const Duration(seconds: 3) - elapsed,
          () => unawaited(_publishPendingPassengerLocation()));
      return;
    }
    _passengerPublishInFlight = true;
    _lastPassengerLocationPublished = now;
    try {
      final sent = await Get.find<TrackingHubService>()
          .publishPassengerLocation(payload);
      if (!_isPassengerTrackingCurrent(generation)) return;
      if (sent) {
        if (identical(_pendingPassengerLocation, payload))
          _pendingPassengerLocation = null;
        passengerLocationError.value = null;
      } else {
        passengerLocationError.value =
            'موقعك ظاهر على جهازك، ويجري إعادة إرساله للسائق.';
      }
    } on Object {
      if (_isPassengerTrackingCurrent(generation)) {
        passengerLocationError.value =
            'تعذر إرسال موقعك للسائق، تجري إعادة المحاولة.';
      }
    } finally {
      _passengerPublishInFlight = false;
      if (_isPassengerTrackingCurrent(generation) &&
          _pendingPassengerLocation != null) {
        _passengerPublishRetry?.cancel();
        _passengerPublishRetry = Timer(const Duration(seconds: 3),
            () => unawaited(_publishPendingPassengerLocation()));
      }
    }
  }

  LocationSettings _passengerLocationStreamSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'يمن درايف يتتبع الرحلة',
          notificationText: 'يستمر تحديث موقعك أثناء الرحلة النشطة.',
          notificationChannelName: 'تتبع الرحلة',
          notificationIcon: AndroidResource(name: 'ic_stat_yemendrive'),
          color: Color(0xFF174C43),
          setOngoing: true,
        ),
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
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
        openActiveRide();
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
    if (!await ensureNoPendingRating(showError: true)) return;
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
    final passengerPosition = _nearbyPresence?.requestPosition;
    final draft = RideRequestDraft(
      customerId: _session.currentUserId.value,
      passengerCoordinate: passengerPosition == null
          ? null
          : RideCoordinate(
              latitude: passengerPosition.latitude,
              longitude: passengerPosition.longitude),
      passengerAccuracy: passengerPosition?.accuracy,
      passengerObservedAt: passengerPosition?.timestamp.toUtc(),
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
      paymentMethodCode: preferredPaymentMethod.value,
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
      applyPaymentChoiceSnapshot({
        'paymentMethodCode': draft.paymentMethodCode,
        'paymentRequiredBeforeStart': false,
      });
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
    if (rideId == null) return;
    try {
      // REST must remain usable while a realtime transport is reconnecting.
      // Read once now and once after joining to close the subscription gap.
      if (Get.isRegistered<TrackingHubService>()) {
        unawaited(_joinSearchUpdates(requestId, rideId, generation));
      }
      await _refreshSearchSnapshot(requestId, generation);
    } on StateSnapshotSuperseded {
      // A newer canonical read owns the snapshot.
    } catch (_) {
      if (generation == _offersWatchGeneration) {
        Get.snackbar(
            'تعذر تحديث حالة البحث', 'تحقق من الاتصال ثم أعد المحاولة.');
      }
    }
  }

  Future<void> _joinSearchUpdates(
      String requestId, int rideId, int generation) async {
    try {
      await Get.find<TrackingHubService>().setRideSubscriptions(<int>{rideId});
      if (isClosed ||
          generation != _offersWatchGeneration ||
          requestId != _requestId ||
          !isSearchingForDriver.value) return;
      await _refreshSearchSnapshotSafely(requestId, generation);
    } on Object {
      // The initial REST snapshot stays usable; reconnect will refresh again.
    }
  }

  Future<void> _refreshSearchSnapshot(String requestId, int generation,
      {bool requireSuccess = false}) async {
    final revision = ++_searchSnapshotRevision;
    final epoch = _stateEpoch;
    final detail = await _repository.getRideDetail(requestId);
    if (revision != _searchSnapshotRevision)
      throw const StateSnapshotSuperseded();
    if (epoch != _stateEpoch) throw const StateSnapshotSuperseded();
    if (generation != _offersWatchGeneration ||
        requestId != _requestId ||
        !isSearchingForDriver.value) return;

    final rawRide = detail['ride'];
    if (rawRide is! Map)
      throw const FormatException('تعذر تحديث بيانات الطلب.');
    final ride = Map<Object?, Object?>.from(rawRide);
    final status = _asInt(ride['status']);
    applyPaymentChoiceSnapshot(ride);
    final rawOffers = detail['offers'];
    final allOffers = rawOffers is List
        ? rawOffers
            .whereType<Map<Object?, Object?>>()
            .map((item) => Map<String, Object?>.from(item))
            .map(_repository.mapRealtimeOffer)
            .whereType<DriverOffer>()
            .toList(growable: false)
        : const <DriverOffer>[];
    if (status != null && <int>{3, 4, 5, 8, 9}.contains(status)) {
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
      if (status == 6 && detail['requiresRating'] == true)
        _requireRating(requestId);
      if (Get.isRegistered<TrackingHubService>()) {
        unawaited(
            Get.find<TrackingHubService>().setRideSubscriptions(const <int>{}));
      }
      return;
    }

    final snapshot = allOffers
        .where((offer) => offer.status == DriverOfferStatus.pending)
        .where((offer) =>
            offer.expiresAt == null || offer.expiresAt!.isAfter(DateTime.now()))
        .toList(growable: false);
    driverOffers.assignAll(snapshot);
    for (final offer in snapshot) {
      unawaited(_offerNotifier.announce(requestId, offer.id));
    }
    _tryAutoAcceptMatchingOffer();
    receivedOffersCount.value = snapshot.length;
    _updateOffersExhausted();
    await _refreshRequestRecipients(requestId, generation,
        requireSuccess: requireSuccess);
    try {
      final viewers = await _repository.getRequestViewers(requestId);
      if (epoch != _stateEpoch) throw const StateSnapshotSuperseded();
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
      if (requireSuccess) rethrow;
    }
  }

  Future<void> _refreshRequestRecipients(String rideId, int generation,
      {bool requireSuccess = false}) async {
    final revision = ++_requestRecipientsRevision;
    final epoch = _stateEpoch;
    try {
      final recipients = await _repository.getRequestRecipients(rideId);
      if (epoch != _stateEpoch) throw const StateSnapshotSuperseded();
      if (revision == _requestRecipientsRevision &&
          generation == _offersWatchGeneration &&
          rideId == _requestId &&
          isSearchingForDriver.value) {
        requestRecipients.assignAll(recipients);
      }
    } on Object {
      // Keep the last confirmed recipients; never substitute nearby drivers.
      if (requireSuccess) rethrow;
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
      _nearbyPresence?.removeDriver(driverId);
      return;
    }
    if (event.name == 'nearbyDriverLocationUpdated') {
      final driver = _repository.mapRealtimeNearbyDriver(payload);
      if (driver == null) return;
      _nearbyPresence?.receiveDriver(driver);
      return;
    }
    final rideId =
        payload['rideId']?.toString() ?? payload['rideID']?.toString();
    if (rideId == null || rideId != _requestId) return;
    final changesRide = const {
      'rideSearchRecipientsUpdated',
      'rideArrivalUpdated',
      'paymentUpdated',
      'cashApprovalUpdated',
      'rideCancellationUpdated',
      'rideUnavailable',
      'rideStatusUpdated',
      'rideRouteChangeUpdated',
      'offerReceived',
      'offerUpdated',
    }.contains(event.name);
    if (changesRide) _legacyStateRevision++;
    if (changesRide &&
        Get.isRegistered<TrackingHubService>() &&
        Get.find<TrackingHubService>().supportsStateRecovery.value) {
      // Legacy envelopes have no durable version. Once recovery is supported,
      // use them as invalidations so a delayed payload cannot roll state back.
      _queueLiveRideRefresh();
      return;
    }

    if (event.name == 'rideSearchRecipientsUpdated' &&
        isSearchingForDriver.value) {
      _queueLiveRideRefresh();
      return;
    }

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

    if (event.name == 'rideArrivalUpdated' ||
        event.name == 'paymentUpdated' ||
        event.name == 'cashApprovalUpdated' ||
        event.name == 'rideRouteChangeUpdated' ||
        event.name == 'rideCancellationUpdated') {
      _queueLiveRideRefresh();
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
      if (status == 5 || payload['passengerBoardedAtUtc'] != null) {
        passengerBoarded.value = true;
      }
      if (status == 7) {
        if (cancellationReviewPending || isCancellingRide.value) {
          _queueLiveRideRefresh();
          return;
        }
        // The server has already committed cancellation. A slow or failed
        // snapshot must not leave the passenger on the active trip screen.
        cancelRide('${payload['cancellationReason'] ?? ''}');
        return;
      }
      applyPaymentChoiceSnapshot(payload);
      customerPaymentEnabled.value = payload['customerPaymentEnabled'] == true;
      if (status == 6) {
        _stopRealTracking();
        _requireRating(rideId);
      } else if (status == 3 || status == 4 || status == 5 || status == 9) {
        unawaited(_refreshAssignedDriverRoute());
      }
      _showArrivalNotice(status, rideId);
      reconcilePaymentNavigation();
      _queueLiveRideRefresh();
      return;
    }
    if (event.name == 'driverLocationUpdated') {
      final latitude = _asDouble(payload['latitude']);
      final longitude = _asDouble(payload['longitude']);
      if (latitude == null || longitude == null) return;
      final observedAt = parseUtcTimestamp(payload['observedAtUtc']);
      _animateTrackedDriver(DriverTrackingSnapshot(
        driverId: '${payload['driverId'] ?? ''}',
        location: RideCoordinate(latitude: latitude, longitude: longitude),
        heading: _asDouble(payload['bearing']),
        updatedAt:
            observedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ));
      unawaited(_refreshAssignedDriverRoute());
      return;
    }
    if (event.name != 'offerReceived' && event.name != 'offerUpdated') return;
    if (!isSearchingForDriver.value) return;
    final offer = _repository.mapRealtimeOffer(payload);
    if (offer == null) return;

    final index = driverOffers.indexWhere((item) => item.id == offer.id);
    if (offer.status == DriverOfferStatus.pending) {
      if (offer.expiresAt != null && !offer.expiresAt!.isAfter(DateTime.now()))
        return;
      if (index < 0) {
        driverOffers.add(offer);
        receivedOffersCount.value++;
      } else {
        driverOffers[index] = offer;
      }
      offersExhausted.value = false;
      unawaited(_offerNotifier.announce(rideId, offer.id));
      _tryAutoAcceptMatchingOffer();
      return;
    }

    if (index >= 0) driverOffers[index] = offer;
    if (offer.status == DriverOfferStatus.accepted &&
        _asInt(payload['rideStatus']) == 3) {
      applyPaymentChoiceSnapshot(payload);
      if (!payload.containsKey('paymentRequiredBeforeStart')) {
        paymentRequiredBeforeStart.value =
            activePaymentMethodCode.value.toLowerCase() != 'cash' &&
                !activeRidePaymentCompleted.value;
      }
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
    paymentRequiredBeforeStart.value =
        activePaymentMethodCode.value.toLowerCase() != 'cash' &&
            !activeRidePaymentCompleted.value;
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
    if (_searchMutationInProgress ||
        isCancellingRide.value ||
        isDriverAssigned.value ||
        isClosed) return;
    final requestId = _requestId;
    if (requestId == null) {
      await requestRide();
      return;
    }
    _searchMutationInProgress = true;
    isRetryingSearch.value = true;
    searchRetryError.value = null;
    var restarted = false;
    try {
      await _repository.restartSearch(requestId);
      if (isClosed || requestId != _requestId || isDriverAssigned.value) return;
      _beginSearchCycle();
      restarted = true;
      unawaited(_watchOffers(requestId));
    } catch (error) {
      if (!isClosed && requestId == _requestId && !isDriverAssigned.value) {
        isSearchingForDriver.value = false;
        searchRetryError.value = _searchErrorMessage(error);
        offersExhausted.value = true;
      }
    } finally {
      _searchMutationInProgress = false;
      isRetryingSearch.value = false;
    }
    if (restarted) {
      _tryAutoAcceptMatchingOffer();
      _updateOffersExhausted();
    }
  }

  Future<bool> cancelDriverSearch() async {
    if (_searchMutationInProgress) return false;
    _searchMutationInProgress = true;
    try {
      final requestId = _requestId;
      if (requestId != null) await _repository.closeSearch(requestId);
      offersExhausted.value = false;
      offersStreamDone.value = false;
      receivedOffersCount.value = 0;
      driverOffers.clear();
      requestViewers.clear();
      requestRecipients.clear();
      _offersDeadlineTimer?.cancel();
      isSearchingForDriver.value = false;
      ++_offersWatchGeneration;
      negotiationStatus.value = NegotiationStatus.searching;
      return true;
    } catch (error) {
      Get.snackbar('تعذر إيقاف البحث', _searchErrorMessage(error));
      offersExhausted.value = true;
      return false;
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
    searchRetryError.value = null;
    receivedOffersCount.value = 0;
    _offersDeadlineTimer?.cancel();
    requestViewers.clear();
    requestRecipients.clear();
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
    isSearchingForDriver.value = false;
    _offersDeadlineTimer?.cancel();
    // Keep the request and subscriptions alive until the customer chooses.
    // Closing here emits rideUnavailable and navigates away from the dialog.
    offersExhausted.value = true;
  }

  String _searchErrorMessage(Object error) =>
      error is FormatException ? error.message.toString() : error.toString();

  final RxBool preparingCancellation = false.obs;

  Future<Map<String, Object?>> getCancellationQuote() async {
    final rideId = _requestId;
    if (rideId == null) throw const FormatException('الرحلة غير موجودة.');
    return _repository.getCancellationQuote(rideId);
  }

  Future<void> cancelActiveRide(String reason) async {
    if (isCancellingRide.value) return;
    if (cancellationReviewPending) {
      openActiveRide();
      return;
    }
    final requestId = _requestId;
    if (requestId == null || reason.trim().length < 3) {
      Get.snackbar(
          'سبب الإلغاء مطلوب', 'حدد سبباً واضحاً قبل إرسال طلب الإلغاء.');
      return;
    }
    isCancellingRide.value = true;
    final assigned = isDriverAssigned.value;
    try {
      final confirmed = await Get.dialog<bool>(AlertDialog(
        title: const Text('تأكيد إلغاء الرحلة'),
        content: Text('هل تريد إلغاء الرحلة؟\n\nسبب الإلغاء: ${reason.trim()}'),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Get.back(result: true),
              child: const Text('تأكيد الإلغاء')),
        ],
      ));
      if (confirmed != true) return;
      if (assigned) {
        var safeStopConfirmed = false;
        if (activeRideStatus.value == '5' ||
            activeRideStatus.value == 'InProgress') {
          final stopped = await Get.dialog<bool>(AlertDialog(
            title: const Text('تأكيد التوقف الآمن'),
            content: const Text(
                'اطلب من السائق التوقف في مكان آمن. أكد فقط بعد توقف النقل فعلياً وخروجك بأمان. الحقوق والمبالغ تُراجع بعد الإلغاء.'),
            actions: [
              TextButton(
                  onPressed: () => Get.back(result: false),
                  child: const Text('لم نتوقف بعد')),
              FilledButton(
                  onPressed: () => Get.back(result: true),
                  child: const Text('توقفنا بأمان'))
            ],
          ));
          if (stopped != true) return;
          safeStopConfirmed = true;
        }
        final decision = await _repository.requestCancellation(
            requestId, reason.trim(),
            safeStopConfirmed: safeStopConfirmed);
        if (isClosed || _requestId != requestId) return;
        final decisionStatus = _asInt(decision?['status']);
        final confirmedRideStatus = _asInt(decision?['rideStatus']);
        final hasDecision = decision?['id'] != null &&
            decisionStatus != null &&
            confirmedRideStatus != null;
        awaitingCancellationStatus.value = !hasDecision;
        if (hasDecision) {
          driverCancellationRequest.value = decision;
          activeRideStatus.value = '$confirmedRideStatus';
          if (confirmedRideStatus == 7) {
            _stopRealTracking();
            if (!cancellationReviewPending) {
              cancelRide(reason);
              return;
            }
          }
        }
        openActiveRide();
        await refreshActiveRide();
        if (_requestId == requestId) {
          openActiveRide();
          if (awaitingCancellationStatus.value) {
            Get.snackbar('أُرسل طلب الإلغاء', 'جارٍ التحقق من نتيجة الإلغاء.');
          } else if (cancellationReviewPending) {
            final ended =
                const {'7', 'Cancelled'}.contains(activeRideStatus.value);
            Get.snackbar(
                ended ? 'أُلغيت الرحلة' : 'أُرسل طلب الإلغاء',
                ended
                    ? 'انتهى النقل. تجري متابعة الحقوق والمبالغ بشكل مستقل.'
                    : 'سيصلك إشعار بقرار المراجعة.');
          }
        }
        return;
      } else {
        await _repository.closeSearch(requestId, reason: reason.trim());
      }
    } catch (error) {
      Get.snackbar(
          'تعذر إرسال الطلب',
          error is FormatException
              ? error.message.toString()
              : 'لم يُرسل طلب الإلغاء. تحقق من الاتصال ثم حاول مرة أخرى.');
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
    openActiveRide();
  }

  void startRealTracking() {
    final rideId = int.tryParse(_requestId ?? '');
    if (rideId == null ||
        isClosed ||
        const {'6', '7', 'Completed', 'Cancelled'}
            .contains(activeRideStatus.value)) return;
    _realTrackingActive = true;
    // Native GPS must not wait for a disconnected Hub or a slow REST request.
    unawaited(_startPassengerPositionTracking());
    unawaited(() async {
      if (Get.isRegistered<TrackingHubService>()) {
        await Get.find<TrackingHubService>()
            .setRideSubscriptions(<int>{rideId});
      }
      if (!_realTrackingActive || '$rideId' != _requestId || isClosed) return;
      await refreshActiveRide();
    }());
  }

  Future<void> refreshActiveRide({bool requireSuccess = false}) async {
    _activeSnapshotQueued = true;
    final existing = _activeSnapshotTask;
    late final Future<void> task;
    if (existing != null) {
      task = existing;
    } else {
      task = _drainActiveSnapshots().whenComplete(() {
        if (identical(_activeSnapshotTask, task)) _activeSnapshotTask = null;
      });
      _activeSnapshotTask = task;
    }
    try {
      await task;
    } catch (_) {
      if (requireSuccess) rethrow;
    }
  }

  /// Keep the original observed time; opening a map does not renew GPS age.
  void applyMapWatchSnapshot(Map<String, Object?> location) {
    if (location['rideId']?.toString() != _requestId) return;
    _handleHubEvent(TrackingHubEvent('driverLocationUpdated', location));
  }

  Future<void> _drainActiveSnapshots() async {
    do {
      _activeSnapshotQueued = false;
      try {
        await _refreshActiveRideOnce();
      } on StateSnapshotSuperseded {
        _activeSnapshotQueued = true;
      }
    } while (_activeSnapshotQueued && !isClosed);
  }

  Future<void> _refreshActiveRideOnce() async {
    final rideId = _requestId;
    final epoch = _stateEpoch;
    if (rideId == null) {
      return;
    }
    try {
      final detail = await _repository.getRideDetail(rideId);
      if (rideId != _requestId) return;
      if (epoch != _stateEpoch) throw const StateSnapshotSuperseded();
      final ride = detail['ride'];
      if (ride is! Map) {
        throw const FormatException('تعذر تحديث بيانات الرحلة.');
      }
      applyPaymentChoiceSnapshot(Map<Object?, Object?>.from(ride));
      final status = _asInt(ride['status']);
      activeRideStatus.value = '${ride['status'] ?? ''}';
      _applyConfirmedRoute(Map<String, Object?>.from(ride));
      // The in-progress map records this phone's fixes only. Server history is
      // useful for the completed trip, but must not replace local live travel.
      if (!_isTripInProgress) {
        _restoreTravelledDriverSamples(detail['driverRouteSamples']);
      }
      unawaited(_refreshBookingRoute());
      customerPaymentEnabled.value = ride['customerPaymentEnabled'] == true;
      if (status == 6 || status == 7) {
        _stopRealTracking();
      }
      _showArrivalNotice(status, rideId);
      passengerBoarded.value = (ride['passengerBoardedAtUtc'] != null ||
          _asInt(ride['status']) == 5);
      activeRidePaymentCompleted.value = detail['paymentCompleted'] == true;
      reconcilePaymentNavigation();
      final approval = detail['cashCollectionApproval'];
      cashCollectionApproval.value =
          approval is Map ? Map<String, Object?>.from(approval) : null;
      final driver = detail['driver'];
      if (driver is Map) {
        final driverValues = Map<Object?, Object?>.from(driver);
        assignedDriverName.value = '${driverValues['name'] ?? ''}'.trim();
        assignedVehicleModel.value =
            '${driverValues['vehicleModel'] ?? ''}'.trim();
        assignedPlateNumber.value =
            '${driverValues['plateNumber'] ?? ''}'.trim();
        assignedPassengerSeats.value =
            _asInt(driverValues['approvedPassengerSeats']);
        assignedDriverRating.value = _asDouble(driverValues['rating']) ?? 0;
        assignedDriverPhone.value =
            '${driverValues['phoneNumber'] ?? ''}'.trim();
        final driverId =
            '${driverValues['id'] ?? driverValues['driverId'] ?? ''}'.trim();
        final photoUrl = '${driverValues['photoUrl'] ?? ''}'.trim();
        assignedDriverPhotoUrl.value = photoUrl;
        assignedDriverCompletedTrips.value =
            _asInt(driverValues['completedTrips']) ?? 0;
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
            updatedAt: parseUtcTimestamp(values['observedAtUtc']) ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ));
          unawaited(_refreshAssignedDriverRoute());
        }
      }
      await _refreshDriverCancellation(rideId);
      if (rideId != _requestId) return;
      if (epoch != _stateEpoch) throw const StateSnapshotSuperseded();
      if (cancellationReviewPending) {
        openActiveRide();
        return;
      }
      if (status == 7 && Get.currentRoute != RideRoutes.payment) {
        cancelRide('${ride['cancellationReason'] ?? ''}');
        return;
      }
      if (status == 6 && detail['requiresRating'] == true) {
        _requireRating(rideId);
      } else if (status == 6 && detail['requiresRating'] == false) {
        ratingSubmitted(rideId);
      }
    } catch (_) {
      if (cancellationReviewPending)
        cancellationStatusError.value =
            'تعذر تحديث القرار. ستتم إعادة المحاولة تلقائياً عند توفر الاتصال.';
      rethrow;
      // Keep the last confirmed marker visible during a transient network failure.
    }
  }

  void _showArrivalNotice(int? status, String rideId) {
    if (status != 9) return;
    final id = int.tryParse(rideId);
    if (id != null)
      unawaited(_arrivalNotifier()?.refresh(id) ?? Future<void>.value());
  }

  Future<void> _refreshDriverCancellation(String rideId) async {
    if (!Get.isRegistered<ApiClient>()) return;
    final epoch = _stateEpoch;
    final result = await Get.find<ApiClient>().execute<Object?>(
      model: 'RideCancellationRequestModel',
      operation: 'get',
      data: {'rideId': rideId},
    );
    if (_requestId != rideId) return;
    if (epoch != _stateEpoch) throw const StateSnapshotSuperseded();
    if (result is ApiFailure) {
      if (result.problem.code == 'cancellation_request_not_found') {
        driverCancellationRequest.value = null;
        cancellationStatusError.value = null;
        return;
      }
      // Cancellation is an auxiliary read. Its absence or temporary failure
      // must never discard an otherwise valid boarding, driver or route
      // snapshot. Keep an existing review until its canonical read recovers.
      if (cancellationReviewPending) {
        cancellationStatusError.value =
            'تعذر تحديث القرار. ستتم إعادة المحاولة تلقائياً عند توفر الاتصال.';
      }
      return;
    }
    if (result is! ApiSuccess) return;
    final raw = result.data;
    if (raw != null && raw is! Map) {
      if (cancellationReviewPending) {
        cancellationStatusError.value =
            'تعذر تحديث القرار. ستتم إعادة المحاولة تلقائياً عند توفر الاتصال.';
      }
      return;
    }
    driverCancellationRequest.value =
        raw is Map ? Map<String, Object?>.from(raw) : null;
    cancellationStatusError.value = null;
    if (raw is Map) awaitingCancellationStatus.value = false;
  }

  Future<void> decideDriverCancellation({required bool accept}) async {
    final request = driverCancellationRequest.value;
    if (request == null ||
        (request['requestedByDriver'] != true &&
            request['refundConsentPending'] != true &&
            request['cashReceiptPending'] != true) ||
        request['canDecide'] != true ||
        isDecidingDriverCancellation.value) return;
    isDecidingDriverCancellation.value = true;
    try {
      final result = await Get.find<ApiClient>().execute<Object?>(
        model: 'RideCancellationRequestModel',
        operation: accept ? 'accept' : 'reject',
        data: {
          'id': request['id'],
          if (request['refundConsentPending'] == true ||
              request['cashReceiptPending'] == true)
            'refundChoiceRevision': request['refundChoiceRevision'],
          if (request['cashReceiptPending'] == true && accept)
            'cashReceiptConfirmed': true,
        },
      );
      if (result is! ApiSuccess) throw const FormatException();
      await refreshActiveRide(requireSuccess: true);
      if (!accept)
        Get.snackbar(
            request['refundConsentPending'] == true
                ? 'رُفضت طريقة الاسترداد'
                : 'أُحيل الطلب للإدارة',
            request['refundConsentPending'] == true
                ? 'سيختار السائق طريقة إعادة المبلغ مجدداً.'
                : 'تراجع الإدارة طلب السائق وتتخذ القرار.');
    } on Object {
      Get.snackbar('تعذر تنفيذ القرار', 'تحقق من الاتصال ثم أعد المحاولة.');
    } finally {
      isDecidingDriverCancellation.value = false;
    }
  }

  void _applyConfirmedRoute(Map<String, Object?> ride) {
    final version = _asInt(ride['routeVersion']) ?? 0;
    if (version < _confirmedRouteVersion) return;
    final draft = currentDraft.value;
    final latitude = _asDouble(ride['destinationLatitude']);
    final longitude = _asDouble(ride['destinationLongitude']);
    if (draft == null ||
        latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) return;
    _confirmedRouteVersion = version;
    final price = _asDouble(ride['customerPrice']) ?? draft.offeredPrice;
    final label =
        '${ride['destinationDisplayName'] ?? ride['destinationAddress'] ?? draft.destination}';
    final changed = draft.destinationCoordinate.latitude != latitude ||
        draft.destinationCoordinate.longitude != longitude ||
        draft.destination != label;
    if (!changed && draft.offeredPrice == price) return;
    currentDraft.value = RideRequestDraft(
      pickup: draft.pickup,
      destination: label,
      pickupCoordinate: draft.pickupCoordinate,
      destinationCoordinate:
          RideCoordinate(latitude: latitude, longitude: longitude),
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
      paymentMethodCode: draft.paymentMethodCode,
      routeDistanceMeters:
          _asInt(ride['routeDistanceMeters']) ?? draft.routeDistanceMeters,
      routeDurationSeconds:
          _asInt(ride['routeDurationSeconds']) ?? draft.routeDurationSeconds,
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
    _realTrackingActive = false;
    _passengerTrackingGeneration++;
    _passengerPositionStartTask = null;
    _passengerPositionRetry?.cancel();
    _passengerPublishRetry?.cancel();
    _pendingPassengerLocation = null;
    passengerLocationError.value = null;
    passengerLocationApproximate.value = false;
    _lastPassengerPositionObservedAt = null;
    _latestPassengerFix = null;
    _clearLocalVehicleContinuity();
    _vehicleWasInProgress = null;
    _passengerVehicleFixExpired = false;
    _vehiclePhaseStartedAt = null;
    _vehicleFreshnessTimer?.cancel();
    _vehicleFreshnessTimer = null;
    _vehicleAnimation?.stop();
    _vehicleAnimationStart = null;
    _vehicleAnimationTarget = null;
    _vehicleGpsSample.value = null;
    trackedVehicle.value = null;
    vehicleUsesPassengerGps.value = false;
    _trackingRouteRefreshRequested = false;
    ++_trackingRouteRequestId;
    _driverAnimationTarget = null;
    _passengerPositionSubscription?.cancel();
    _passengerPositionSubscription = null;
    if (Get.isRegistered<TrackingHubService>()) {
      unawaited(
          Get.find<TrackingHubService>().setRideSubscriptions(const <int>{}));
    }
  }

  void _animateTrackedDriver(DriverTrackingSnapshot target) {
    final latest = latestDriverGpsSample;
    if (!target.location.latitude.isFinite ||
        !target.location.longitude.isFinite ||
        target.location.latitude.abs() > 90 ||
        target.location.longitude.abs() > 180 ||
        (latest != null &&
            latest.driverId == target.driverId &&
            !target.updatedAt.isAfter(latest.updatedAt))) return;
    target = DriverTrackingSnapshot(
      driverId: target.driverId,
      location: target.location,
      updatedAt: target.updatedAt,
      heading: TrackedDriverMotion.heading(latest, target),
    );
    _driverAnimationTarget = target;
    // Keep remote state authoritative, with one animation for the visible
    // vehicle. An ongoing ride never spends a second ticker on hidden GPS.
    trackedDriver.value = target;
    _syncVehicleSource();
  }

  double? _interpolateHeading(double? from, double? to, double progress) {
    if (to == null) return from;
    if (from == null) return to;
    final delta = ((to - from + 540) % 360) - 180;
    return (from + delta * progress + 360) % 360;
  }

  void _syncVehicleSource() {
    if (isClosed) return;
    final driver = latestDriverGpsSample;
    final fix = _latestPassengerFix;
    final usePassenger = _realTrackingActive &&
        !_passengerVehicleFixExpired &&
        _isTripInProgress &&
        fix != null &&
        (_vehiclePhaseStartedAt == null ||
            !fix.timestamp.toUtc().isBefore(_vehiclePhaseStartedAt!)) &&
        RiderVehicleLocation.canUse(
            position: fix,
            now: DateTime.now(),
            previousPassengerPosition: _localVehicleRideId == _requestId
                ? _lastValidatedVehicleFix
                : null);
    if (usePassenger) {
      _lastValidatedVehicleFix = fix;
      _localVehicleRideId = _requestId;
    } else if (!_isTripInProgress) {
      _clearLocalVehicleContinuity();
    }
    if (_isTripInProgress && !usePassenger) {
      vehicleUsesPassengerGps.value = false;
      _vehicleAnimation?.stop();
      // Keep only the last actual local fix. Never jump to the remote driver
      // when local GPS is unavailable, rejected, or expires.
      trackedVehicle.value =
          _vehicleTargetIsPassenger ? _vehicleGpsSample.value : null;
      return;
    }
    final target = usePassenger
        ? DriverTrackingSnapshot(
            driverId: driver?.driverId ??
                _vehicleGpsSample.value?.driverId ??
                'ride:$_requestId',
            location: RideCoordinate(
                latitude: fix.latitude, longitude: fix.longitude),
            heading: fix.speed.isFinite && fix.speed >= .8 ? fix.heading : null,
            updatedAt: fix.timestamp.toUtc())
        : driver;
    if (target == null) return;
    final previousTarget = _vehicleAnimationTarget;
    if (previousTarget != null &&
        _vehicleTargetIsPassenger == usePassenger &&
        previousTarget.driverId == target.driverId &&
        previousTarget.updatedAt == target.updatedAt) return;
    final current = displayedVehicle;
    final next = DriverTrackingSnapshot(
        driverId: target.driverId,
        location: target.location,
        updatedAt: target.updatedAt,
        heading: TrackedDriverMotion.heading(
            _vehicleTargetIsPassenger == usePassenger
                ? previousTarget
                : current,
            target));
    final sourceChanged = _vehicleTargetIsPassenger != usePassenger;
    _vehicleTargetIsPassenger = usePassenger;
    vehicleUsesPassengerGps.value = usePassenger;
    _vehicleGpsSample.value = next;
    if (usePassenger) _recordTravelledDriver(next);
    _vehicleFreshnessTimer?.cancel();
    _vehicleFreshnessTimer = null;
    if (usePassenger) {
      final age = DateTime.now().toUtc().difference(fix.timestamp.toUtc());
      _vehicleFreshnessTimer = Timer(
          Duration(milliseconds: (4000 - age.inMilliseconds).clamp(0, 4000)),
          () {
        _vehicleFreshnessTimer = null;
        _passengerVehicleFixExpired = true;
        _clearLocalVehicleContinuity();
        _syncVehicleSource();
      });
    }
    _vehicleAnimation?.stop();
    _vehicleAnimationStart = current ?? next;
    _vehicleAnimationTarget = next;
    final gap = previousTarget == null || sourceChanged
        ? const Duration(milliseconds: 700)
        : next.updatedAt.difference(previousTarget.updatedAt);
    if (_paused ||
        current == null ||
        current.driverId != next.driverId ||
        gap > Duration(seconds: usePassenger ? 4 : 10) ||
        Geolocator.distanceBetween(
                current.location.latitude,
                current.location.longitude,
                next.location.latitude,
                next.location.longitude) >
            250) {
      trackedVehicle.value = next;
      return;
    }
    final animation = _vehicleAnimation ??= AnimationController(vsync: this)
      ..addListener(() {
        final from = _vehicleAnimationStart, to = _vehicleAnimationTarget;
        if (isClosed || from == null || to == null) return;
        final t = _vehicleAnimation!.value;
        final elapsed = _vehicleAnimation!.lastElapsedDuration ?? Duration.zero;
        final lastFrame = _lastVehicleAnimationFrameAt;
        if (t < 1 &&
            lastFrame != null &&
            elapsed - lastFrame < const Duration(milliseconds: 33)) {
          return;
        }
        _lastVehicleAnimationFrameAt = elapsed;
        trackedVehicle.value = DriverTrackingSnapshot(
            driverId: to.driverId,
            location: RideCoordinate(
                latitude: from.location.latitude +
                    (to.location.latitude - from.location.latitude) * t,
                longitude: from.location.longitude +
                    (to.location.longitude - from.location.longitude) * t),
            heading: _interpolateHeading(from.heading, to.heading, t),
            updatedAt: to.updatedAt);
      });
    animation.duration = usePassenger
        ? TrackedDriverMotion.localDuration(gap)
        : TrackedDriverMotion.duration(gap);
    _lastVehicleAnimationFrameAt = null;
    animation.forward(from: 0);
  }

  void _clearLocalVehicleContinuity() {
    _lastValidatedVehicleFix = null;
    _localVehicleRideId = null;
    _vehicleFreshnessTimer?.cancel();
    _vehicleFreshnessTimer = null;
  }

  Future<void> _refreshAssignedDriverRoute() async {
    _trackingRouteRefreshRequested = true;
    final running = _trackingRouteTask;
    if (running != null) return running;
    late final Future<void> task;
    task = _drainAssignedDriverRoutes().whenComplete(() {
      if (identical(_trackingRouteTask, task)) _trackingRouteTask = null;
    });
    _trackingRouteTask = task;
    return task;
  }

  Future<void> _drainAssignedDriverRoutes() async {
    do {
      _trackingRouteRefreshRequested = false;
      await _refreshAssignedDriverRouteOnce();
    } while (_trackingRouteRefreshRequested && !isClosed);
  }

  Future<void> _refreshAssignedDriverRouteOnce() async {
    final routeRepository = _routeRepository;
    final inProgress = _isTripInProgress;
    final driver = inProgress
        ? vehicleUsesPassengerGps.value
            ? _vehicleGpsSample.value
            : null
        : latestDriverGpsSample;
    final location = Get.find<LocationController>();
    if (isClosed || _paused || routeRepository == null || driver == null)
      return;
    final rideId = _requestId;

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
      final currentTarget = _isTripInProgress
          ? location.destination.value
          : location.pickup.value;
      if (!isClosed &&
          requestId == _trackingRouteRequestId &&
          rideId == _requestId &&
          inProgress == _isTripInProgress &&
          target == currentTarget) {
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
    final requestReason =
        '${driverCancellationRequest.value?['reason'] ?? ''}'.trim();
    final confirmedReason =
        reason.trim().isNotEmpty ? reason.trim() : requestReason;
    // Cancellation is a terminal booking state. Clear the same transient
    // booking data used by "start a new ride" so the next booking cannot
    // reuse the cancelled route, vehicle, offer, or payment state.
    prepareNewRide();
    negotiationStatus.value = NegotiationStatus.cancelled;
    cancellationReason.value = confirmedReason;
    Get.offAllNamed<void>(RideRoutes.requestThanks);
  }

  void prepareNewRide() {
    if (cancellationReviewPending || pendingRatingRideId.value != null) {
      openActiveRide();
      return;
    }
    pendingRatingRideId.value = null;
    awaitingCancellationStatus.value = false;
    cancellationStatusError.value = null;
    passengerBoarded.value = false;
    moreThanFourPassengers.value = false;
    passengerNotes.value = '';
    // The passenger foreground location service is only needed while a ride
    // is active. Stop it before clearing the request id so it cannot keep
    // consuming GPS after the rider returns to the booking flow.
    _stopRealTracking();
    _offersDeadlineTimer?.cancel();
    ++_offersWatchGeneration;
    _requestId = null;
    _paymentChoiceRideId = null;
    activePaymentMethodCode.value = 'cash';
    preferredPaymentMethod.value = _sessionPaymentPreference;
    paymentRequiredBeforeStart.value = false;
    _confirmedRouteVersion = 0;
    _travelledDriverSamples.clear();
    ++_bookingRouteRequestId;
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
    requestRecipients.clear();
    driverCancellationRequest.value = null;
    nearbyDrivers.clear();
    isDriverAssigned.value = false;
    assignedDriverName.value = '';
    assignedDriverPhotoUrl.value = '';
    assignedDriverCompletedTrips.value = 0;
    assignedDriverPhone.value = '';
    assignedVehicleModel.value = '';
    assignedPlateNumber.value = '';
    assignedPassengerSeats.value = null;
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
    trackedVehicle.value = null;
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
    _nearbyPresence?.dispose();
    _nearbyFilterWorker?.dispose();
    _stopRealTracking();
    if (Get.isRegistered<TrackingHubService>()) {
      Get.find<TrackingHubService>().stateChanges.unregister(this);
      unawaited(
          Get.find<TrackingHubService>().setUserEventListening(this, false));
    }
    _arrivalAlerts?.onClose();
    _authenticationWorker?.dispose();
    _defaultServiceWorker?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _hubEventSubscription?.cancel();
    _hubConnectionSubscription?.cancel();
    _apiRecoverySubscription?.cancel();
    _automaticSyncTimer?.cancel();
    _liveRideRefreshTimer?.cancel();
    _bookingMapGeometryWorker?.dispose();
    _vehiclePhaseWorker?.dispose();
    _vehicleAccountWorker?.dispose();
    _trackingRouteGeometryWorker?.dispose();
    _vehicleAnimation?.dispose();
    _offersDeadlineTimer?.cancel();
    _passengerPositionSubscription?.cancel();
    cancellationReasonController.dispose();
    super.onClose();
  }
}
