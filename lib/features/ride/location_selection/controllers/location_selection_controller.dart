import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../../../core/services/auth_session_service.dart';
import '../../../../core/services/startup_connection_service.dart';
import '../../../../shared/widgets/live_tracking_marker_icons.dart';
import '../../../auth/routes/auth_routes.dart';
import '../../models/ride_models.dart';
import '../../ride_routes.dart';
import '../repositories/location_search_repository.dart';
import '../repositories/route_repository.dart';
import '../views/location_access_page.dart';
import '../../../account/favourites/models/saved_place_labels.dart';

class LocationController extends GetxController {
  LocationController(
    this._routeRepository,
    this._searchRepository,
    this._client,
    this._session,
  );

  final RouteRepository _routeRepository;
  final LocationSearchRepository _searchRepository;
  final ApiClient _client;
  final AuthSessionService _session;
  final TextEditingController fromController = TextEditingController();
  final TextEditingController toController = TextEditingController();
  final RxInt activeField = 0.obs;
  final Rx<MapType> mapType = MapType.normal.obs;
  final RxString confirmedDestination = ''.obs;
  final Rxn<LatLng> pickup = Rxn<LatLng>();
  final Rxn<LatLng> destination = Rxn<LatLng>();
  final RxString pickupArea = ''.obs;
  final RxString destinationArea = ''.obs;
  final RxBool pickupIsCurrentLocation = false.obs;
  final RxnBool serviceAreaAvailable = RxnBool();
  final RxString serviceCountryName = 'اليمن'.obs;
  final RxString serviceCityName = 'صنعاء'.obs;
  final RxBool isLocating = false.obs;
  final RxBool locationPermissionBlocked = false.obs;
  Future<void>? _initialLocationRequest;
  int _pickupEditRevision = 0;
  int _savedPlacesRevision = 0;
  final RxnInt focusedRouteField = RxnInt();
  Object? focusedRouteOwner;
  final RxBool isRouteLoading = false.obs;
  final RxString routeError = ''.obs;
  final RxList<LatLng> routePoints = <LatLng>[].obs;
  final RxInt routeDistanceMeters = 0.obs;
  final RxInt routeDurationSeconds = 0.obs;
  final RxList<LocationSearchResult> searchResults =
      <LocationSearchResult>[].obs;
  final RxBool isSearching = false.obs;
  final RxBool searchFailed = false.obs;
  final RxBool searchNeedsAuthentication = false.obs;
  final RxBool isAddressLoading = false.obs;
  final RxBool isChoosingMapPoint = false.obs;
  Completer<bool>? _mapSelection;
  final TextEditingController addressNameController = TextEditingController();
  final TextEditingController streetController = TextEditingController();
  final TextEditingController detailsController = TextEditingController();

  GoogleMapController? _mapController;
  int _searchRequestId = 0;
  int _routeRequestId = 0;
  String? _lastResumedLocationSearchId;
  Map<String, Object?>? _pendingSearchAfterLogin;
  Worker? _authenticationWorker;
  StreamSubscription<void>? _apiRecovery;

  final RxList<RecentPlace> recentPlaces = <RecentPlace>[].obs;
  final Rxn<BitmapDescriptor> _personalPickupMarkerIcon =
      Rxn<BitmapDescriptor>();
  final Rxn<BitmapDescriptor> _destinationMarkerIcon = Rxn<BitmapDescriptor>();
  String _pickupLabel = 'نقطة الالتقاء';

  void resetForNewRide() {
    _pickupEditRevision++;
    _routeRequestId++;
    _searchRequestId++;
    routeError.value = '';
    pickup.value = null;
    destination.value = null;
    pickupArea.value = '';
    destinationArea.value = '';
    pickupIsCurrentLocation.value = false;
    confirmedDestination.value = '';
    routePoints.clear();
    routeDistanceMeters.value = 0;
    routeDurationSeconds.value = 0;
    fromController.clear();
    toController.clear();
    _clearDestinationAddressFields();
    searchResults.clear();
    isSearching.value = false;
    isRouteLoading.value = false;
    activeField.value = 0;
  }

  @override
  void onInit() {
    super.onInit();
    if (Get.isRegistered<StartupConnectionService>()) {
      _apiRecovery = Get.find<StartupConnectionService>().recovered.listen((_) {
        if (!isClosed &&
            hasCompleteRoute &&
            !hasDrivingRoute &&
            !isRouteLoading.value) {
          unawaited(retryDrivingRoute());
        }
      });
    }
    _authenticationWorker =
        ever(_session.isAuthenticated, (bool authenticated) {
      if (!authenticated) {
        _savedPlacesRevision++;
        recentPlaces.clear();
        return;
      }
      unawaited(loadSavedPlaces());
      final pending = _pendingSearchAfterLogin;
      _pendingSearchAfterLogin = null;
      if (pending != null) resumeLocationSearchFromArguments(pending);
    });
    unawaited(loadSavedPlaces());
    unawaited(_loadPersonalPickupMarker());
  }

  Future<void> loadSavedPlaces() async {
    final revision = ++_savedPlacesRevision;
    final owner = _session.currentUserId.value;
    if (!_session.isAuthenticated.value) {
      recentPlaces.clear();
      return;
    }
    final result = await _client.execute<Object?>(
      model: 'SavedPlaceModel',
      operation: 'list',
      data: const {},
    );
    if (isClosed ||
        revision != _savedPlacesRevision ||
        owner != _session.currentUserId.value ||
        result is! ApiSuccess ||
        result.data is! List) return;
    recentPlaces.assignAll(
      (result.data as List)
          .whereType<Map<String, dynamic>>()
          .where((item) => validSavedCoordinates(
              (item['latitude'] as num?)?.toDouble(),
              (item['longitude'] as num?)?.toDouble()))
          .map(
            (item) => RecentPlace(
              title: '${item['label'] ?? 'مكان محفوظ'}',
              address: '${item['address'] ?? ''}',
              kind: '${item['kind'] ?? 'place'}',
              latitude: (item['latitude'] as num?)?.toDouble() ?? 0,
              longitude: (item['longitude'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList(growable: false),
    );
  }

  /// Customer photos are not stored by the current profile model yet. Until
  /// that dedicated upload feature is added, the pickup is still rendered as
  /// a personal avatar rather than an anonymous green pin.
  Future<void> _loadPersonalPickupMarker() async {
    var displayName = 'نقطة الالتقاء';
    try {
      final result = await _client.execute<Object?>(
        model: 'UserModel',
        operation: 'get',
        data: const {},
      );
      if (result is ApiSuccess && result.data is Map) {
        final name = (result.data as Map)['displayName']?.toString().trim();
        if (name != null && name.isNotEmpty) displayName = name;
      }
    } catch (_) {
      // Profile lookup must not block map interaction.
    }
    if (isClosed) return;
    _pickupLabel = displayName.trim().split(RegExp(r'\s+')).take(2).join(' ');
    _personalPickupMarkerIcon.value = await LiveTrackingMarkerIcons.buildStop(
        destination: false, label: _pickupLabel);
    _destinationMarkerIcon.value = await LiveTrackingMarkerIcons.buildStop(
        destination: true, label: 'الوجهة');
  }

  Future<bool> saveCurrentDestination({String? kind, String? label}) async {
    final point = destination.value;
    final savedLabel =
        kind == 'unnamed' ? '' : (label ?? addressNameController.text).trim();
    final address = streetController.text.trim().isEmpty
        ? toController.text.trim()
        : streetController.text.trim();
    if (point == null ||
        (kind != 'unnamed' && savedLabel.isEmpty) ||
        address.isEmpty) {
      Get.snackbar(
          'بيانات المكان ناقصة', 'حدد الوجهة واسمها أو اختر بدون اسم.');
      return false;
    }
    final result = await _client.execute<Object?>(
      model: 'SavedPlaceModel',
      operation: 'add',
      data: {
        'label': savedLabel,
        'kind': kind ?? 'place',
        'address': address,
        'latitude': point.latitude,
        'longitude': point.longitude,
      },
    );
    if (result is! ApiSuccess) return false;
    await loadSavedPlaces();
    return true;
  }

  bool get hasCompleteRoute =>
      pickup.value != null && destination.value != null;
  bool get hasDrivingRoute => hasCompleteRoute && routePoints.length >= 2;
  bool get canContinueLocationFlow => hasDrivingRoute;

  LatLngBounds? get selectedRouteBounds {
    final start = pickup.value;
    final end = destination.value;
    if (start == null || end == null) return null;
    final points = routePoints.length >= 2
        ? routePoints.toList(growable: false)
        : <LatLng>[start, end];
    final latitudes = points.map((point) => point.latitude);
    final longitudes = points.map((point) => point.longitude);
    return LatLngBounds(
      southwest: LatLng(
        latitudes.reduce(math.min),
        longitudes.reduce(math.min),
      ),
      northeast: LatLng(
        latitudes.reduce(math.max),
        longitudes.reduce(math.max),
      ),
    );
  }

  Set<Marker> get markers => <Marker>{
        if (pickup.value != null)
          Marker(
            markerId: const MarkerId('pickup'),
            position: pickup.value!,
            infoWindow: InfoWindow(title: _pickupLabel),
            anchor: LiveTrackingMarkerIcons.stopAnchor,
            icon: _personalPickupMarkerIcon.value ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
          ),
        if (destination.value != null)
          Marker(
            markerId: const MarkerId('destination'),
            position: destination.value!,
            infoWindow: const InfoWindow(title: 'الوجهة'),
            anchor: LiveTrackingMarkerIcons.stopAnchor,
            icon: _destinationMarkerIcon.value ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
      };

  /// Booking coordinates stay fixed while the avatar follows the actual GPS.
  Set<Marker> liveTripMarkers({
    LatLng? passengerPosition,
    bool hasTrackedDriver = false,
  }) =>
      <Marker>{
        ...markers,
        if (passengerPosition != null && !hasTrackedDriver)
          Marker(
            markerId: const MarkerId('tracked-passenger'),
            position: passengerPosition,
            infoWindow: const InfoWindow(title: 'موقعي الآن'),
            anchor: const Offset(.5, .84),
            icon: _personalPickupMarkerIcon.value ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueViolet),
          ),
      };

  Set<Polyline> get polylines {
    if (!hasDrivingRoute) return const <Polyline>{};
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('selected-route'),
        points: routePoints.toList(growable: false),
        width: 6,
        color: const Color(0xFF087AC1),
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  void onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // A map can be recreated after a brief native-map interruption. Reload a
    // complete route that did not finish earlier so the user is not left with
    // only the two markers.
    if (hasCompleteRoute && !hasDrivingRoute && !isRouteLoading.value) {
      unawaited(retryDrivingRoute());
    }
  }

  Future<void> selectMapPoint(LatLng point) async {
    FocusManager.instance.primaryFocus?.unfocus();
    cancelSearch();
    Future<void>? routeRequest;
    if (activeField.value == 0) {
      pickup.value = point;
      pickupIsCurrentLocation.value = false;
      routePoints.clear();
      routeDistanceMeters.value = 0;
      routeDurationSeconds.value = 0;
      fromController.text = 'نقطة انطلاق محددة على الخريطة';
      pickupArea.value = 'منطقة الانطلاق المحددة';
      activeField.value = 1;
      if (hasCompleteRoute) routeRequest = _loadDrivingRoute();
      await enrichPickupAddress(point);
    } else {
      destination.value = point;
      _clearDestinationAddressFields();
      toController.text = 'وجهة محددة على الخريطة';
      destinationArea.value = 'منطقة الوجهة المحددة';
      confirmedDestination.value = toController.text;
      if (hasCompleteRoute) routeRequest = _loadDrivingRoute();
      await enrichDestinationAddress(point);
    }
    if (routeRequest != null) await routeRequest;
    await _fitSelectedRoute();
    if (isChoosingMapPoint.value) {
      isChoosingMapPoint.value = false;
      _mapSelection?.complete(true);
      _mapSelection = null;
    }
  }

  Future<void> useCurrentLocation({
    bool silently = false,
    int field = 0,
    bool closeSearchPage = false,
  }) async {
    if (isLocating.value) return;
    final pickupRevision = _pickupEditRevision;
    isLocating.value = true;
    try {
      var enabled = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();
      if (!silently &&
          (!enabled ||
              permission == LocationPermission.denied ||
              permission == LocationPermission.deniedForever)) {
        final granted = await Get.to<bool>(() => const LocationAccessPage());
        if (granted != true) return;
        enabled = await Geolocator.isLocationServiceEnabled();
        permission = await Geolocator.checkPermission();
      }
      if (!enabled) return;
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        locationPermissionBlocked.value = true;
        if (!silently) {
          Get.snackbar(
            'تعذر الوصول للموقع',
            'امنح التطبيق صلاحية الموقع لاستخدام موقعي الحالي.',
          );
        }
        return;
      }
      locationPermissionBlocked.value = false;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 15),
        ),
      );
      // A delayed initial GPS fix must not replace a manually chosen origin.
      if (isClosed ||
          silently &&
              (pickup.value != null || pickupRevision != _pickupEditRevision))
        return;
      final point = LatLng(position.latitude, position.longitude);
      if (!validSavedCoordinates(point.latitude, point.longitude)) return;
      if (!silently) {
        FocusManager.instance.primaryFocus?.unfocus();
        cancelSearch();
      }
      if (field == 0) {
        pickup.value = point;
        pickupIsCurrentLocation.value = true;
        routePoints.clear();
        routeDistanceMeters.value = 0;
        routeDurationSeconds.value = 0;
        fromController.text = 'تم تحديد موقعي الحالي';
        pickupArea.value = 'موقعي الحالي';
        if (!silently ||
            activeField.value == 0 && focusedRouteField.value == null)
          activeField.value = 1;
        await enrichPickupAddress(point);
      } else {
        destination.value = point;
        _clearDestinationAddressFields();
        routePoints.clear();
        routeDistanceMeters.value = 0;
        routeDurationSeconds.value = 0;
        toController.text = 'موقعي الحالي';
        confirmedDestination.value = toController.text;
        destinationArea.value = 'موقعي الحالي';
        await enrichDestinationAddress(point);
      }
      await _animateMap(CameraUpdate.newLatLngZoom(point, 16));
      if (hasCompleteRoute) await _loadDrivingRoute();
      if (closeSearchPage && Get.currentRoute == RideRoutes.locationSearch) {
        Get.back<bool>(result: true);
      }
    } catch (_) {
      if (!silently) {
        Get.snackbar(
          'تعذر تحديد موقعي الحالي',
          'حاول مرة أخرى، أو ابحث عن نقطة الانطلاق واخترها يدويًا.',
        );
      }
    } finally {
      isLocating.value = false;
    }
  }

  Future<bool> startSearch({int field = 1}) async {
    // Searching and choosing coordinates do not require device GPS access.
    activeField.value = field;
    final selected = await Get.toNamed<dynamic>(RideRoutes.locationSearch);
    if (isChoosingMapPoint.value && _mapSelection != null) {
      return _mapSelection!.future;
    }
    return selected == true;
  }

  void choosePointOnMap() {
    _mapSelection = Completer<bool>();
    isChoosingMapPoint.value = true;
    Get.back<bool>(result: false);
  }

  void cancelMapSelection() {
    isChoosingMapPoint.value = false;
    _mapSelection?.complete(false);
    _mapSelection = null;
  }

  Future<void> searchPlaces(String query) async {
    final requestId = ++_searchRequestId;
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      searchResults.clear();
      searchFailed.value = false;
      searchNeedsAuthentication.value = false;
      isSearching.value = false;
      return;
    }

    final returnRoute = _locationSearchReturnRoute;
    final resumeArguments = _locationSearchResumeArguments(normalizedQuery);
    if (!_session.requireAuthentication(
      returnRoute: returnRoute,
      arguments: resumeArguments,
    )) {
      _pendingSearchAfterLogin = resumeArguments;
      searchResults.clear();
      searchFailed.value = false;
      searchNeedsAuthentication.value = true;
      isSearching.value = false;
      return;
    }

    searchFailed.value = false;
    searchNeedsAuthentication.value = false;
    isSearching.value = true;
    try {
      final results = await _searchRepository.search(normalizedQuery);
      if (requestId != _searchRequestId) return;
      // Google already applies locale-aware matching. Re-filtering the
      // results literally here hid valid Arabic/Latin transliterations such
      // as Sanaa / صنعاء.
      searchResults.assignAll(results);
    } on NoInternetException {
      if (requestId != _searchRequestId) return;
      searchResults.clear();
      searchFailed.value = true;
      Get.snackbar(
        'لا يوجد اتصال بالإنترنت',
        'تحقق من اتصال الشبكة وحاول مرة أخرى',
      );
    } on LocationSearchRequestException catch (error) {
      if (error.requiresAuthentication) {
        searchResults.clear();
        searchNeedsAuthentication.value = true;
        _session.requireAuthentication(
          returnRoute: returnRoute,
          arguments: resumeArguments,
        );
        return;
      }
      if (requestId != _searchRequestId) return;
      searchResults.clear();
      searchFailed.value = true;
      Get.snackbar('تعذر البحث', error.message);
    } catch (_) {
      if (requestId != _searchRequestId) return;
      searchResults.clear();
      searchFailed.value = true;
      Get.snackbar('تعذر البحث', 'تعذر العثور على الموقع. حاول مرة أخرى.');
    } finally {
      if (requestId == _searchRequestId) isSearching.value = false;
    }
  }

  String get _locationSearchReturnRoute {
    final route = Get.currentRoute;
    return route.isEmpty || route == AuthRoutes.signIn
        ? RideRoutes.locationPicker
        : route;
  }

  Map<String, Object?> _locationSearchResumeArguments(String query) =>
      <String, Object?>{
        'resumeLocationSearch': true,
        'locationSearchQuery': query,
        'locationSearchField': activeField.value,
        'locationSearchRequestId': DateTime.now().microsecondsSinceEpoch,
      };

  /// Restores and reruns a location search after sign-in navigates back to the
  /// page where the user entered the query.
  bool resumeLocationSearchFromArguments(Object? arguments) {
    if (arguments is! Map || arguments['resumeLocationSearch'] != true) {
      return false;
    }
    final query = arguments['locationSearchQuery']?.toString().trim() ?? '';
    final requestId = arguments['locationSearchRequestId']?.toString() ?? '';
    if (query.length < 2 ||
        requestId.isEmpty ||
        requestId == _lastResumedLocationSearchId) {
      return false;
    }

    final rawField = arguments['locationSearchField'];
    final field = rawField is num && rawField.toInt() == 0 ? 0 : 1;
    activeField.value = field;
    final textController = field == 0 ? fromController : toController;
    if (textController.text != query) {
      textController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    _lastResumedLocationSearchId = requestId;
    unawaited(searchPlaces(query));
    return true;
  }

  /// Saved places are part of the same search experience as Google places.
  /// Keep them first because they are the customer's own named locations.
  List<RecentPlace> filteredSavedPlaces(String query) {
    final needle = _normalizeSearchText(query);
    if (needle.isEmpty) return recentPlaces.toList(growable: false);
    return recentPlaces.where((place) {
      final searchable = _normalizeSearchText(
        '${place.title} ${place.address}',
      );
      return searchable.contains(needle);
    }).toList(growable: false);
  }

  String _normalizeSearchText(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[ًٌٍَُِّْـ]'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي');

  void cancelSearch() {
    _pendingSearchAfterLogin = null;
    _searchRequestId++;
    searchResults.clear();
    searchFailed.value = false;
    searchNeedsAuthentication.value = false;
    isSearching.value = false;
  }

  /// Clears one editable route field and invalidates only the route data that
  /// depended on it. The map screen owns the focus request so this method can
  /// also be reused by non-interactive route fields safely.
  void clearRouteField(int field, {bool clearText = true}) {
    if (field == 0) _pickupEditRevision++;
    activeField.value = field;
    cancelSearch();
    _routeRequestId++;
    routeError.value = '';
    routePoints.clear();
    routeDistanceMeters.value = 0;
    routeDurationSeconds.value = 0;
    isRouteLoading.value = false;

    if (field == 0) {
      pickup.value = null;
      pickupIsCurrentLocation.value = false;
      pickupArea.value = '';
      if (clearText) fromController.clear();
      return;
    }

    destination.value = null;
    destinationArea.value = '';
    confirmedDestination.value = '';
    if (clearText) toController.clear();
    _clearDestinationAddressFields();
  }

  Future<void> selectSearchResult(
    LocationSearchResult result, {
    bool closeSearchPage = true,
  }) async {
    if (activeField.value == 0) {
      pickup.value = result.location;
      pickupIsCurrentLocation.value = false;
      fromController.text = result.formattedAddress.isEmpty
          ? result.title
          : result.formattedAddress;
      pickupArea.value = _areaOrFallback(result, 'منطقة الانطلاق المحددة');
      activeField.value = 1;
      routePoints.clear();
      routeDistanceMeters.value = 0;
      routeDurationSeconds.value = 0;
    } else {
      destination.value = result.location;
      _clearDestinationAddressFields();
      toController.text = result.formattedAddress.isEmpty
          ? result.title
          : result.formattedAddress;
      confirmedDestination.value = toController.text;
      addressNameController.text = result.title;
      streetController.text = result.street;
      detailsController.text = result.formattedAddress;
      destinationArea.value = _areaOrFallback(result, 'منطقة الوجهة المحددة');
    }
    searchResults.clear();
    if (closeSearchPage) Get.back<bool>(result: true);
    if (hasCompleteRoute) await _loadDrivingRoute();
    await _fitSelectedRoute();
  }

  Future<void> enrichDestinationAddress(LatLng point) async {
    isAddressLoading.value = true;
    try {
      final result = await _searchRepository.reverseGeocode(point);
      if (destination.value != point) return;
      if (result != null) {
        final displayName = _displayLocationName(result);
        if (displayName.isNotEmpty) {
          toController.text = displayName;
          confirmedDestination.value = displayName;
        }
        if (addressNameController.text.trim().isEmpty) {
          addressNameController.text = displayName;
        }
        if (streetController.text.trim().isEmpty) {
          streetController.text = result.street;
        }
        if (detailsController.text.trim().isEmpty) {
          detailsController.text = result.formattedAddress;
        }
        if (result.area.trim().isNotEmpty) {
          destinationArea.value = result.area.trim();
        }
      }
    } on NoInternetException {
      Get.snackbar(
        'لا يوجد اتصال بالإنترنت',
        'تم تحديد الموقع، ويمكنك إدخال العنوان يدويًا',
      );
    } catch (_) {
    } finally {
      if (destination.value == point) isAddressLoading.value = false;
    }
  }

  Future<void> enrichPickupAddress(LatLng point) async {
    try {
      final result = await _searchRepository.reverseGeocode(point);
      if (pickup.value != point) return;
      if (result != null) {
        final displayName = _displayLocationName(result);
        if (displayName.isNotEmpty) fromController.text = displayName;
        if (result.area.trim().isNotEmpty) {
          pickupArea.value = result.area.trim();
          serviceCityName.value = result.area.trim();
          await checkServiceAvailability(result.area.trim());
        }
      }
    } catch (_) {
      // The selected coordinate remains valid even if its display area is not
      // available yet. Route selection must not be blocked by reverse geocoding.
    }
  }

  Future<void> checkServiceAvailability(String city) async {
    try {
      final response = await _client.execute<Object?>(
        model: 'ServiceAreaModel',
        operation: 'report',
        data: {'countryCode': 'YE', 'cityNameAr': city},
      );
      if (response is ApiSuccess && response.data is Map) {
        serviceAreaAvailable.value =
            (response.data as Map)['available'] == true;
      }
    } catch (_) {
      serviceAreaAvailable.value = null;
    }
  }

  Future<void> selectPlace(RecentPlace place,
      {int? field, bool closeSearchPage = true}) async {
    if (!validSavedCoordinates(place.latitude, place.longitude)) return;
    if (field != null) activeField.value = field;
    FocusManager.instance.primaryFocus?.unfocus();
    cancelSearch();
    final address = place.address.trim();
    final title = place.title.trim();
    final value = address.isNotEmpty ? address : title;
    final point = LatLng(place.latitude, place.longitude);
    if (activeField.value == 0) {
      _pickupEditRevision++;
      pickup.value = point;
      pickupIsCurrentLocation.value = false;
      routePoints.clear();
      routeDistanceMeters.value = 0;
      routeDurationSeconds.value = 0;
      fromController.text = value;
      pickupArea.value = place.title;
      activeField.value = 1;
    } else {
      destination.value = point;
      _clearDestinationAddressFields();
      toController.text = value;
      confirmedDestination.value = value;
      addressNameController.text = title.isNotEmpty ? title : value;
      streetController.text = place.address;
      detailsController.text = place.address;
      destinationArea.value = place.title;
    }
    if (hasCompleteRoute) {
      await _loadDrivingRoute();
      await _fitSelectedRoute();
    }
    if (closeSearchPage && Get.currentRoute == RideRoutes.locationSearch) {
      Get.back<bool>(result: true);
    }
    if (destination.value == null) {
      await _fitSelectedRoute();
    }
  }

  void openAddressDetails() {
    if (!canContinueLocationFlow) {
      Get.snackbar(
        'المسار غير مكتمل',
        'حدد نقطة الانطلاق والوجهة وانتظر حتى يتم حساب المسار.',
      );
      return;
    }
    Get.toNamed<void>(RideRoutes.locationAddress);
  }

  void openLocationConfirmation() {
    if (addressNameController.text.trim().isEmpty) {
      Get.snackbar(
        'اسم العنوان مطلوب',
        'اكتب اسمًا واضحًا للوجهة قبل المتابعة.',
      );
      return;
    }
    confirmedDestination.value = addressNameController.text.trim();
    Get.toNamed<void>(RideRoutes.locationConfirm);
  }

  Future<void> focusRoute() => _fitSelectedRoute();

  Future<void> retryDrivingRoute() async {
    if (!hasCompleteRoute) return;
    await _loadDrivingRoute();
    await _fitSelectedRoute();
  }

  void useTypedValue() {
    final value = activeField.value == 0
        ? fromController.text.trim()
        : toController.text.trim();
    if (value.isEmpty) return;
    confirmedDestination.value = value;
    Get.toNamed<void>(RideRoutes.locationConfirm);
  }

  bool confirmLocation() {
    if (!canContinueLocationFlow) {
      Get.snackbar(
        'المسار غير مكتمل',
        'حدد نقطة الانطلاق والوجهة على الخريطة.',
      );
      return false;
    }
    if (addressNameController.text.trim().isEmpty) {
      Get.snackbar(
        'اسم العنوان مطلوب',
        'اكتب اسمًا واضحًا للوجهة قبل المتابعة',
      );
      return false;
    }
    return true;
  }

  Future<void> _fitSelectedRoute() async {
    if (!hasCompleteRoute) {
      final point = pickup.value ?? destination.value;
      if (point != null) {
        await _animateMap(CameraUpdate.newLatLng(point));
      }
      return;
    }
    final bounds = selectedRouteBounds;
    if (bounds == null) return;
    await _animateMap(
      CameraUpdate.newLatLngBounds(bounds, 86),
    );
  }

  /// AppGoogleMap owns the native controller lifecycle. Location updates can
  /// complete after Flutter recreates a platform view, so camera work must
  /// quietly skip an old disposed controller and wait for the next map.
  Future<void> _animateMap(CameraUpdate update) async {
    final map = _mapController;
    if (map == null) return;
    try {
      await map.animateCamera(update);
    } catch (_) {
      // A replacement GoogleMap will publish a fresh controller through
      // [onMapCreated]; no user action is required for this transient state.
    }
  }

  Future<void> _loadDrivingRoute() async {
    final start = pickup.value;
    final end = destination.value;
    if (start == null || end == null) return;
    final requestId = ++_routeRequestId;
    isRouteLoading.value = true;
    routeError.value = '';
    routePoints.clear();
    routeDistanceMeters.value = 0;
    routeDurationSeconds.value = 0;
    try {
      final route = await _routeRepository.getDrivingRoute(
        origin: start,
        destination: end,
      );
      if (isClosed ||
          requestId != _routeRequestId ||
          pickup.value != start ||
          destination.value != end) return;
      routePoints.assignAll(route.points);
      routeDistanceMeters.value = route.distanceMeters;
      routeDurationSeconds.value = route.durationSeconds;
    } on RouteRequestException catch (error) {
      if (isClosed ||
          requestId != _routeRequestId ||
          pickup.value != start ||
          destination.value != end) return;
      routeError.value = error.message;
      Get.snackbar(
        'تعذر حساب المسار',
        error.message,
        duration: const Duration(seconds: 7),
      );
    } catch (_) {
      if (isClosed ||
          requestId != _routeRequestId ||
          pickup.value != start ||
          destination.value != end) return;
      routeError.value = 'تعذر حساب مسار الرحلة حاليًا. حاول مرة أخرى لاحقًا.';
      Get.snackbar(
        'تعذر حساب المسار',
        'تعذر حساب مسار الرحلة حاليًا. حاول مرة أخرى لاحقًا.',
      );
    } finally {
      if (requestId == _routeRequestId) isRouteLoading.value = false;
    }
  }

  Future<void> ensureInitialPickupLocation() async {
    if (pickup.value != null ||
        isClosed ||
        fromController.text.trim().isNotEmpty) return;
    final active = _initialLocationRequest;
    if (active != null) {
      await active;
      return;
    }
    final task = useCurrentLocation(silently: true);
    _initialLocationRequest = task;
    try {
      await task;
    } finally {
      if (identical(_initialLocationRequest, task))
        _initialLocationRequest = null;
    }
  }

  List<RecentPlace> get shortcutPlaces {
    final seen = <String>{};
    final named = recentPlaces
        .where((p) =>
            p.kind != 'unnamed' &&
            p.title.trim().isNotEmpty &&
            validSavedCoordinates(p.latitude, p.longitude))
        .where((p) => seen.add(p.title.trim().toLowerCase()))
        .toList();
    return [
      ...named.where((p) => !savedPlaceKinds.containsKey(p.kind)),
      ...named.where((p) => savedPlaceKinds.containsKey(p.kind))
    ];
  }

  String _areaOrFallback(LocationSearchResult result, String fallback) {
    final area = result.area.trim();
    if (area.isNotEmpty) return area;
    final title = result.title.trim();
    return title.isEmpty ? fallback : title;
  }

  String _displayLocationName(LocationSearchResult result) {
    final title = result.title.trim();
    if (title.isNotEmpty && title != 'موقع') return title;
    final formattedAddress = result.formattedAddress.trim();
    return formattedAddress.isNotEmpty ? formattedAddress : title;
  }

  void _clearDestinationAddressFields() {
    addressNameController.clear();
    streetController.clear();
    detailsController.clear();
  }

  @override
  void onClose() {
    _routeRequestId++;
    _searchRequestId++;
    _apiRecovery?.cancel();
    _authenticationWorker?.dispose();
    // The AppGoogleMap widget owns and disposes its native controller.
    _mapController = null;
    fromController.dispose();
    toController.dispose();
    addressNameController.dispose();
    streetController.dispose();
    detailsController.dispose();
    super.onClose();
  }
}
