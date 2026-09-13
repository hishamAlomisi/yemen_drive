import 'dart:math' as math;

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
  final RxBool isLocating = false.obs;
  final RxBool locationPermissionBlocked = false.obs;
  bool _initialLocationRequested = false;
  final RxBool isRouteLoading = false.obs;
  final RxList<LatLng> routePoints = <LatLng>[].obs;
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

  final RxList<RecentPlace> recentPlaces = <RecentPlace>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadSavedPlaces();
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

  bool get _useDevelopmentRouteFallback =>
      !AppEnvironment.isProduction && AppEnvironment.googleRoutesApiKey.isEmpty;

  Set<Marker> get markers => <Marker>{
        if (pickup.value != null)
          Marker(
            markerId: const MarkerId('pickup'),
            position: pickup.value!,
            infoWindow: const InfoWindow(title: 'نقطة الانطلاق'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
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
  }

  Future<void> selectMapPoint(LatLng point) async {
    if (!await _ensureLocationPermission()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    cancelSearch();
    if (activeField.value == 0 || pickup.value == null) {
      pickup.value = point;
      routePoints.clear();
      fromController.text = _coordinateLabel('نقطة الانطلاق', point);
      activeField.value = 1;
    } else {
      destination.value = point;
      toController.text = _coordinateLabel('الوجهة', point);
      confirmedDestination.value = toController.text;
      await enrichDestinationAddress(point);
    }
    if (hasCompleteRoute) await _loadDrivingRoute();
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
      fromController.text = 'تم تحديد موقعي الحالي';
      activeField.value = 1;
      await _mapController
          ?.animateCamera(CameraUpdate.newLatLngZoom(point, 16));
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
      final normalizedQuery = query.trim().toLowerCase();
      final results = await _searchRepository.search(query);
      if (requestId != _searchRequestId) return;
      searchResults.assignAll(
        results.where(
          (result) =>
              result.title.toLowerCase().contains(normalizedQuery) ||
              result.formattedAddress.toLowerCase().contains(normalizedQuery),
        ),
      );
    } on NoInternetException {
      if (requestId != _searchRequestId) return;
      searchResults.clear();
      searchFailed.value = true;
      Get.snackbar(
        'لا يوجد اتصال بالإنترنت',
        'تحقق من اتصال الشبكة وحاول مرة أخرى',
      );
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
      activeField.value = 1;
    } else {
      destination.value = result.location;
      toController.text = result.formattedAddress.isEmpty
          ? result.title
          : result.formattedAddress;
      confirmedDestination.value = toController.text;
      addressNameController.text = result.title;
      streetController.text = result.street;
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
        if (addressNameController.text.trim().isEmpty) {
          addressNameController.text = result.title;
        }
        if (streetController.text.trim().isEmpty) {
          streetController.text = result.street;
        }
        if (detailsController.text.trim().isEmpty) {
          detailsController.text = result.formattedAddress;
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

  Future<void> selectPlace(RecentPlace place) async {
    if (activeField.value == 0 && !await _ensureLocationPermission()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    cancelSearch();
    final value = place.kind == 'recent' ? place.title : place.address;
    final point = LatLng(place.latitude, place.longitude);
    if (activeField.value == 0) {
      pickup.value = point;
      routePoints.clear();
      fromController.text = value;
      activeField.value = 1;
    } else {
      destination.value = point;
      toController.text = value;
      confirmedDestination.value = '${place.title}، ${place.address}';
      addressNameController.text = place.title;
      streetController.text = place.address;
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
    final map = _mapController;
    if (map == null) return;
    if (!hasCompleteRoute) {
      final point = pickup.value ?? destination.value;
      if (point != null) await map.animateCamera(CameraUpdate.newLatLng(point));
      return;
    }
    final a = pickup.value!;
    final b = destination.value!;
    await map.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            math.min(a.latitude, b.latitude),
            math.min(a.longitude, b.longitude),
          ),
          northeast: LatLng(
            math.max(a.latitude, b.latitude),
            math.max(a.longitude, b.longitude),
          ),
        ),
        70,
      ),
    );
  }

  Future<void> _loadDrivingRoute() async {
    final start = pickup.value;
    final end = destination.value;
    if (start == null || end == null || isRouteLoading.value) return;
    isRouteLoading.value = true;
    routePoints.clear();
    try {
      if (_useDevelopmentRouteFallback) {
        routePoints.assignAll(<LatLng>[start, end]);
        Get.snackbar(
          'مسار تقديري للتطوير',
          'استُخدم خط بين النقطتين المختارتين للاختبار. لا يمثل مسار قيادة فعلياً.',
        );
        return;
      }
      final points = await _routeRepository.getDrivingRoute(
        origin: start,
        destination: end,
      );

      routePoints.assignAll(points);
    } on RouteRequestException {
      Get.snackbar(
        'تعذر حساب المسار',
        'تعذر حساب مسار الرحلة حاليًا. حاول مرة أخرى لاحقًا.',
        duration: const Duration(seconds: 7),
      );
    } catch (_) {
      Get.snackbar(
        'تعذر حساب المسار',
        'تعذر حساب مسار الرحلة حاليًا. حاول مرة أخرى لاحقًا.',
      );
    } finally {
      isRouteLoading.value = false;
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

  String _coordinateLabel(String prefix, LatLng point) =>
      '$prefix (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})';

  @override
  void onClose() {
    _mapController?.dispose();
    fromController.dispose();
    toController.dispose();
    addressNameController.dispose();
    streetController.dispose();
    detailsController.dispose();
    super.onClose();
  }
}
