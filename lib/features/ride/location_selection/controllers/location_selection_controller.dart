import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_models.dart';
import '../../models/ride_models.dart';
import '../../ride_routes.dart';
import '../repositories/location_search_repository.dart';
import '../repositories/route_repository.dart';

class LocationController extends GetxController {
  LocationController(
      this._routeRepository, this._searchRepository, this._client);

  final RouteRepository _routeRepository;
  final LocationSearchRepository _searchRepository;
  final ApiClient _client;
  final TextEditingController fromController = TextEditingController(
    text: 'موقعي الحالي',
  );
  final TextEditingController toController = TextEditingController();
  final RxInt activeField = 0.obs;
  final RxString confirmedDestination = ''.obs;
  final Rxn<LatLng> pickup = Rxn<LatLng>();
  final Rxn<LatLng> destination = Rxn<LatLng>();
  final RxString pickupArea = ''.obs;
  final RxString destinationArea = ''.obs;
  final RxBool isLocating = false.obs;
  final RxBool locationPermissionBlocked = false.obs;
  bool _initialLocationRequested = false;
  final RxBool isRouteLoading = false.obs;
  final RxList<LatLng> routePoints = <LatLng>[].obs;
  final RxInt routeDistanceMeters = 0.obs;
  final RxInt routeDurationSeconds = 0.obs;
  final RxList<LocationSearchResult> searchResults =
      <LocationSearchResult>[].obs;
  final RxBool isSearching = false.obs;
  final RxBool searchFailed = false.obs;
  final RxBool isAddressLoading = false.obs;
  final TextEditingController addressNameController = TextEditingController();
  final TextEditingController streetController = TextEditingController();
  final TextEditingController detailsController = TextEditingController();

  GoogleMapController? _mapController;
  int _searchRequestId = 0;
  int _routeRequestId = 0;

  final RxList<RecentPlace> recentPlaces = <RecentPlace>[].obs;
  final Rxn<BitmapDescriptor> _personalPickupMarkerIcon =
      Rxn<BitmapDescriptor>();

  @override
  void onInit() {
    super.onInit();
    unawaited(loadSavedPlaces());
    unawaited(_loadPersonalPickupMarker());
  }

  Future<void> loadSavedPlaces() async {
    final result = await _client.execute<Object?>(
      model: 'SavedPlaceModel',
      operation: 'list',
      data: const {},
    );
    if (result is! ApiSuccess || result.data is! List) return;
    recentPlaces.assignAll((result.data as List)
        .whereType<Map<String, dynamic>>()
        .map((item) => RecentPlace(
              title: '${item['label'] ?? 'مكان محفوظ'}',
              address: '${item['address'] ?? ''}',
              kind: '${item['kind'] ?? 'place'}',
              latitude: (item['latitude'] as num?)?.toDouble() ?? 0,
              longitude: (item['longitude'] as num?)?.toDouble() ?? 0,
            ))
        .toList(growable: false));
  }

  /// Customer photos are not stored by the current profile model yet. Until
  /// that dedicated upload feature is added, the pickup is still rendered as
  /// a personal avatar rather than an anonymous green pin.
  Future<void> _loadPersonalPickupMarker() async {
    var displayName = 'م';
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
    _personalPickupMarkerIcon.value =
        await _buildPersonalPickupMarker(displayName);
  }

  Future<BitmapDescriptor?> _buildPersonalPickupMarker(String name) async {
    try {
      const width = 88;
      const height = 104;
      const avatarCenter = ui.Offset(44, 37);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final shadow = ui.Paint()
        ..isAntiAlias = true
        ..color = const ui.Color(0x3D000000);
      final fill = ui.Paint()
        ..isAntiAlias = true
        ..color = const ui.Color(0xFF1499C5);
      final tail = ui.Path()
        ..moveTo(44, 88)
        ..lineTo(27, 58)
        ..lineTo(61, 58)
        ..close();
      canvas.drawPath(tail.shift(const ui.Offset(0, 3)), shadow);
      canvas.drawCircle(avatarCenter + const ui.Offset(0, 3), 31, shadow);
      canvas.drawPath(tail, fill);
      canvas.drawCircle(avatarCenter, 31, fill);
      canvas.drawCircle(
        avatarCenter,
        26,
        ui.Paint()
          ..isAntiAlias = true
          ..color = const ui.Color(0xFFFFFFFF),
      );
      canvas.drawCircle(
        avatarCenter,
        23,
        ui.Paint()
          ..isAntiAlias = true
          ..color = const ui.Color(0xFFE0F4FA),
      );
      final value = name.trim();
      final letter = value.isEmpty ? 'م' : value.substring(0, 1);
      final painter = TextPainter(
        text: TextSpan(
          text: letter,
          style: const TextStyle(
            color: Color(0xFF087EA6),
            fontSize: 27,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      painter.paint(
        canvas,
        avatarCenter - Offset(painter.width / 2, painter.height / 2),
      );
      final image = await recorder.endRecording().toImage(width, height);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      return BitmapDescriptor.bytes(
        Uint8List.sublistView(bytes),
        imagePixelRatio: 2,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveCurrentDestination({String? kind}) async {
    final point = destination.value;
    final label = addressNameController.text.trim();
    final address = streetController.text.trim().isEmpty
        ? toController.text.trim()
        : streetController.text.trim();
    if (point == null || label.isEmpty || address.isEmpty) {
      Get.snackbar('بيانات المكان ناقصة', 'أدخل اسم المكان والعنوان أولاً.');
      return false;
    }
    final result = await _client.execute<Object?>(
      model: 'SavedPlaceModel',
      operation: 'add',
      data: {
        'label': label,
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

  bool get _useDevelopmentRouteFallback => AppEnvironment.useDemoData;

  Set<Marker> get markers => <Marker>{
        if (pickup.value != null)
          Marker(
            markerId: const MarkerId('pickup'),
            position: pickup.value!,
            infoWindow: const InfoWindow(title: 'موقعي — نقطة الانطلاق'),
            anchor: const Offset(.5, .84),
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
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
      };

  Set<Polyline> get polylines {
    if (!hasDrivingRoute) return const <Polyline>{};
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('selected-route'),
        points: routePoints.toList(growable: false),
        width: 6,
        color: const Color(0xFF1A73E8),
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
    if (!await _ensureLocationPermission()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    cancelSearch();
    Future<void>? routeRequest;
    if (activeField.value == 0 || pickup.value == null) {
      pickup.value = point;
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
  }

  Future<void> useCurrentLocation() async {
    if (isLocating.value) return;
    isLocating.value = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        Get.snackbar('الموقع غير مفعل', 'فعّل خدمة الموقع في الجهاز أولًا.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        locationPermissionBlocked.value = true;
        Get.snackbar(
          'تعذر الوصول للموقع',
          'امنح التطبيق صلاحية الموقع للمتابعة.',
        );
        return;
      }
      locationPermissionBlocked.value = false;
      final position = await Geolocator.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      FocusManager.instance.primaryFocus?.unfocus();
      cancelSearch();
      pickup.value = point;
      routePoints.clear();
      routeDistanceMeters.value = 0;
      routeDurationSeconds.value = 0;
      fromController.text = 'تم تحديد موقعي الحالي';
      pickupArea.value = 'موقعي الحالي';
      activeField.value = 1;
      await enrichPickupAddress(point);
      await _animateMap(CameraUpdate.newLatLngZoom(point, 16));
      if (destination.value != null) await _loadDrivingRoute();
    } finally {
      isLocating.value = false;
    }
  }

  void startSearch({int field = 1}) {
    if (locationPermissionBlocked.value || pickup.value == null) {
      _showLocationPermissionMessage();
      return;
    }
    activeField.value = field;
    Get.toNamed<void>(RideRoutes.locationSearch);
  }

  Future<void> searchPlaces(String query) async {
    final requestId = ++_searchRequestId;
    if (query.trim().length < 2) {
      searchResults.clear();
      searchFailed.value = false;
      isSearching.value = false;
      return;
    }
    searchFailed.value = false;
    isSearching.value = true;
    try {
      final results = await _searchRepository.search(query);
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

  void cancelSearch() {
    _searchRequestId++;
    searchResults.clear();
    searchFailed.value = false;
    isSearching.value = false;
  }

  /// Clears one editable route field and invalidates only the route data that
  /// depended on it. The map screen owns the focus request so this method can
  /// also be reused by non-interactive route fields safely.
  void clearRouteField(int field) {
    activeField.value = field;
    cancelSearch();
    _routeRequestId++;
    routePoints.clear();
    routeDistanceMeters.value = 0;
    routeDurationSeconds.value = 0;
    isRouteLoading.value = false;

    if (field == 0) {
      pickup.value = null;
      pickupArea.value = '';
      fromController.clear();
      return;
    }

    destination.value = null;
    destinationArea.value = '';
    confirmedDestination.value = '';
    toController.clear();
    _clearDestinationAddressFields();
  }

  Future<void> selectSearchResult(
    LocationSearchResult result, {
    bool closeSearchPage = true,
  }) async {
    if (activeField.value == 0 && !await _ensureLocationPermission()) return;
    if (activeField.value == 0) {
      pickup.value = result.location;
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
    if (closeSearchPage) Get.back<void>();
    if (hasCompleteRoute) await _loadDrivingRoute();
    await _fitSelectedRoute();
  }

  Future<void> enrichDestinationAddress(LatLng point) async {
    isAddressLoading.value = true;
    try {
      final result = await _searchRepository.reverseGeocode(point);
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
      isAddressLoading.value = false;
    }
  }

  Future<void> enrichPickupAddress(LatLng point) async {
    try {
      final result = await _searchRepository.reverseGeocode(point);
      if (result != null) {
        final displayName = _displayLocationName(result);
        if (displayName.isNotEmpty) fromController.text = displayName;
        if (result.area.trim().isNotEmpty) {
          pickupArea.value = result.area.trim();
        }
      }
    } catch (_) {
      // The selected coordinate remains valid even if its display area is not
      // available yet. Route selection must not be blocked by reverse geocoding.
    }
  }

  Future<void> selectPlace(RecentPlace place) async {
    if (activeField.value == 0 && !await _ensureLocationPermission()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    cancelSearch();
    final value = place.kind == 'recent' ? place.title : place.address;
    final point = LatLng(place.latitude, place.longitude);
    if (activeField.value == 0) {
      pickup.value = point;
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
      confirmedDestination.value = '${place.title}، ${place.address}';
      addressNameController.text = place.title;
      streetController.text = place.address;
      detailsController.text = place.address;
      destinationArea.value = place.title;
    }
    if (hasCompleteRoute) {
      await _loadDrivingRoute();
      await _fitSelectedRoute();
    }
    if (!hasDrivingRoute) {
      await _fitSelectedRoute();
      if (Get.currentRoute == RideRoutes.locationSearch) Get.back<void>();
      Get.snackbar('تم تحديد نقطة الانطلاق', 'حدد الوجهة للمتابعة');
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
    routePoints.clear();
    routeDistanceMeters.value = 0;
    routeDurationSeconds.value = 0;
    try {
      if (_useDevelopmentRouteFallback) {
        if (requestId != _routeRequestId) return;
        routePoints.assignAll(<LatLng>[start, end]);
        Get.snackbar(
          'مسار تقديري للتطوير',
          'استُخدم خط بين النقطتين المختارتين للاختبار. لا يمثل مسار قيادة فعلياً.',
        );
        return;
      }
      final route = await _routeRepository.getDrivingRoute(
        origin: start,
        destination: end,
      );
      if (requestId != _routeRequestId) return;
      routePoints.assignAll(route.points);
      routeDistanceMeters.value = route.distanceMeters;
      routeDurationSeconds.value = route.durationSeconds;
    } on RouteRequestException {
      if (requestId != _routeRequestId) return;
      Get.snackbar(
        'تعذر حساب المسار',
        'تعذر حساب مسار الرحلة حاليًا. حاول مرة أخرى لاحقًا.',
        duration: const Duration(seconds: 7),
      );
    } catch (_) {
      if (requestId != _routeRequestId) return;
      Get.snackbar(
        'تعذر حساب المسار',
        'تعذر حساب مسار الرحلة حاليًا. حاول مرة أخرى لاحقًا.',
      );
    } finally {
      if (requestId == _routeRequestId) isRouteLoading.value = false;
    }
  }

  Future<void> ensureInitialPickupLocation() async {
    if (_initialLocationRequested || pickup.value != null) return;
    _initialLocationRequested = true;
    await useCurrentLocation();
  }

  Future<bool> _ensureLocationPermission() async {
    if (pickup.value != null && !locationPermissionBlocked.value) return true;
    await useCurrentLocation();
    return pickup.value != null && !locationPermissionBlocked.value;
  }

  void _showLocationPermissionMessage() {
    Get.snackbar(
      'صلاحية الموقع مطلوبة',
      'امنح التطبيق صلاحية الوصول لموقعك الحالي لتحديد نقطة الانطلاق والمتابعة.',
      duration: const Duration(seconds: 5),
    );
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
