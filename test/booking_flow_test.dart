import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as maps;
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:yemen_drive/app/localization/app_translations.dart';
import 'package:yemen_drive/app/theme/app_theme.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/realtime/tracking_hub_service.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/booking/controllers/booking_controller.dart';
import 'package:yemen_drive/features/ride/booking/widgets/booking_panel.dart';
import 'package:yemen_drive/features/ride/booking/widgets/booking_review_panel.dart';
import 'package:yemen_drive/features/ride/booking/widgets/ride_options_sheet.dart';
import 'package:yemen_drive/features/ride/location_selection/views/location_access_page.dart';
import 'package:yemen_drive/features/ride/views/vehicle_request_views.dart';
import 'package:yemen_drive/features/ride/booking/views/booking_review_view.dart';
import 'package:yemen_drive/features/ride/booking/views/ride_search_view.dart';
import 'package:yemen_drive/features/ride/booking/widgets/booking_service_widgets.dart';
import 'package:yemen_drive/features/ride/bindings/ride_binding.dart';
import 'package:yemen_drive/features/ride/controllers/ride_controller.dart';
import 'package:yemen_drive/features/ride/controllers/notifications_controller.dart';
import 'package:yemen_drive/features/ride/home/repositories/service_kind_repository.dart';
import 'package:yemen_drive/features/ride/location_selection/controllers/location_selection_controller.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/location_search_repository.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/route_repository.dart';
import 'package:yemen_drive/features/ride/models/ride_models.dart';
import 'package:yemen_drive/features/ride/models/service_kind_models.dart';
import 'package:yemen_drive/features/ride/negotiation/repositories/ride_negotiation_repository.dart';
import 'package:yemen_drive/features/ride/ride_routes.dart';
import 'package:yemen_drive/features/ride/views/negotiation_views.dart';
import 'package:yemen_drive/features/ride/views/home_notifications_location_views.dart';
import 'package:yemen_drive/features/ride/widgets/ride_map_shell.dart';
import 'package:yemen_drive/features/ride/widgets/ride_booking_widgets.dart';
import 'package:yemen_drive/features/ride/widgets/ride_trip_widgets.dart';
import 'package:yemen_drive/shared/widgets/app_button.dart';

const _vehicle = RideVehicle(
    id: '12',
    name: 'سيارة اقتصادية',
    type: RideVehicleType.car,
    serviceKindId: 1,
    serviceCatalogItemId: 12,
    arrivalMinutes: 0,
    price: 0,
    rating: 0,
    seats: 4,
    description: 'رحلات المدينة');
const _quote = RideQuote(
    suggestedPrice: 1500,
    minPrice: 1000,
    maxPrice: 2000,
    priceStep: 100,
    serviceFee: 100,
    currency: 'YER');
const _secondVehicle = RideVehicle(
    id: '13',
    name: 'مريحة',
    type: RideVehicleType.car,
    serviceKindId: 1,
    serviceCatalogItemId: 13,
    arrivalMinutes: 4,
    price: 0,
    rating: 0,
    seats: 4,
    description: 'سيارات أحدث');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Repository repository;
  late _QuietRide ride;
  late _QuietLocation location;
  late BookingController booking;
  late _Api api;

  setUpAll(() async {
    final storageDirectory = Directory('build/booking-test-storage')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => storageDirectory.absolute.path);
    await GetStorage.init();
    final font = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    Get.testMode = true;
    final storage = SecureStorageService();
    api = _Api(storage);
    final session = AuthSessionService(storage, api);
    session.isAuthenticated.value = true;
    session.currentUserId.value = 1;
    repository = _Repository();
    ride = Get.put<RideController>(_QuietRide(repository, session,
        serviceKinds: ApiServiceKindRepository(api))) as _QuietRide;
    location = Get.put<LocationController>(_QuietLocation(api, session))
        as _QuietLocation;
    location.pickup.value = const LatLng(15.36, 44.19);
    location.destination.value = const LatLng(15.38, 44.21);
    location.routePoints
        .assignAll([location.pickup.value!, location.destination.value!]);
    location.routeDistanceMeters.value = 3000;
    location.routeDurationSeconds.value = 480;
    location.fromController.text = 'شارع حدة';
    location.toController.text = 'ميدان التحرير';
    location.serviceAreaAvailable.value = true;
    ride.selectedServiceKindId.value = 1;
    ride.catalogVehicles.assignAll([_vehicle]);
    ride.selectedVehicle.value = _vehicle;
    booking = Get.put(BookingController(ride, location));
  });
  tearDown(() async {
    Get.delete<BookingController>(force: true);
    Get.delete<RideController>(force: true);
    Get.delete<LocationController>(force: true);
    Get.reset();
  });

  testWidgets(
      'riding options survive price changes and are sent with the request',
      (tester) async {
    _phoneSize(tester);
    Get.put<TrackingHubService>(_QuietHub());
    await booking.refreshQuote();
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(RepaintBoundary(
        key: boundary,
        child: Material(
            color: AppTheme.light.colorScheme.surface,
            child: const RideOptionsSheet()))));
    await tester.tap(find.byType(Switch));
    await tester.enterText(find.byType(TextField), 'لدينا حقائب إضافية');
    await tester.pump();
    expect(ride.moreThanFourPassengers.value, isTrue);
    await _capture(tester, boundary, 'ride-options');
    await ride.requestRide();
    final draft = repository.requests.single;
    expect(draft.moreThanFourPassengers, isTrue);
    expect(draft.withPrice(2000).passengerNotes, 'لدينا حقائب إضافية');
    await tester.pumpWidget(const SizedBox());
    ride.prepareNewRide();
    expect(ride.moreThanFourPassengers.value, isFalse);
    expect(ride.passengerNotes.value, isEmpty);
  });

  testWidgets(
      'location waits for device services before asking Android for permission',
      (tester) async {
    _phoneSize(tester);
    final original = GeolocatorPlatform.instance;
    final geo = _LocationAccessPlatform();
    GeolocatorPlatform.instance = geo;
    addTearDown(() => GeolocatorPlatform.instance = original);
    await tester.pumpWidget(_host(const Text('اختيار الموقع يدويًا')));
    final boundary = GlobalKey();
    Get.to<bool>(() =>
        RepaintBoundary(key: boundary, child: const LocationAccessPage()));
    await tester.pumpAndSettle();
    expect(geo.permissionRequests, 0);
    await _capture(tester, boundary, 'location-access');
    await tester.tap(find.text('تفعيل خدمة الموقع'));
    await tester.pumpAndSettle();
    expect(geo.settingsOpened, 1);
    expect(geo.permissionRequests, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(LocationAccessPage), findsOneWidget);
    expect(geo.permissionRequests, 0);
    await tester.tap(find.text('تفعيل خدمة الموقع'));
    await tester.pumpAndSettle();
    geo.enabled = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(geo.permissionRequests, 1);
    expect(find.byType(LocationAccessPage), findsNothing);
  });

  testWidgets(
      'cancellation preserves viewers and skip returns without cancelling',
      (tester) async {
    _phoneSize(tester);
    final originalMaps = maps.GoogleMapsFlutterPlatform.instance;
    maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
    addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = originalMaps);
    Get.put<TrackingHubService>(_QuietHub());
    await tester.pumpWidget(_host(const Text('شاشة البحث السابقة')));
    await booking.refreshQuote();
    await ride.requestRide();
    await tester.pump(const Duration(milliseconds: 400));
    ride.requestViewers
        .assignAll([const RideRequestViewer(driverId: '9', name: 'سائق')]);
    final boundary = GlobalKey();
    Get.to<void>(
        () => RepaintBoundary(key: boundary, child: const RideCancelPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RideCancelPage), findsOneWidget);
    expect(find.byKey(const ValueKey('search-viewers-count')), findsOneWidget);
    expect(ride.requestViewers.single.driverId, '9');
    await _capture(tester, boundary, 'cancellation-reasons');
    await tester.tap(find.text('تخطي'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.closedAsExhausted, isEmpty);
    expect(ride.currentRideId, '42');
    Get.to<void>(() => const RideCancelPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('الأجرة لا تناسبني'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.cancellationReasons, isEmpty);
    await tester.tap(find.text('تأكيد الإلغاء'));
    await tester.pumpAndSettle();
    expect(repository.cancellationReasons, ['الأجرة لا تناسبني']);
    expect(ride.currentRideId, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancellation reasons follow ride status and received offers',
      (tester) async {
    final originalMaps = maps.GoogleMapsFlutterPlatform.instance;
    maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
    addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = originalMaps);
    ride.activeRideStatus.value = '5';
    await tester.pumpWidget(_host(const RideCancelPage()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('لا أشعر بالأمان أثناء الرحلة'), findsOneWidget);
    expect(find.text('حدث عطل في السيارة'), findsOneWidget);
    expect(find.textContaining('الأجرة'), findsNothing);
    expect(find.textContaining('تأخر السائق'), findsNothing);
    expect(find.textContaining('لا يوجد سائق'), findsNothing);
    expect(find.byKey(const ValueKey('search-viewers-count')), findsNothing);
    ride.activeRideStatus.value = '4';
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('تأخر السائق عن موعد الوصول المتوقع'), findsOneWidget);
    expect(find.text('حدث عطل في السيارة'), findsNothing);
    ride.activeRideStatus.value = '9';
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('تأخر السائق'), findsNothing);
    expect(find.text('السيارة أو السائق لا يطابقان البيانات المعروضة'),
        findsOneWidget);
    ride.activeRideStatus.value = '1';
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('لا يوجد سائق متاح بالقرب مني'), findsOneWidget);
    ride.driverOffers.add(const DriverOffer(
        id: '1',
        driverName: 'سائق',
        vehicleSummary: '',
        price: 1500,
        rating: 4,
        etaMinutes: 3));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('لا يوجد سائق متاح بالقرب مني'), findsNothing);
    expect(find.text('الأجرة المعروضة لا تناسبني'), findsOneWidget);
    ride.activeRideStatus.value = '6';
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('انتهت الرحلة ولا يمكن إلغاؤها'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'trip action icons stay visible above system navigation with long scrolling details',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    var shared = false;
    var cancelled = false;
    await tester.pumpWidget(_host(RepaintBoundary(
        key: boundary,
        child: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 568),
                padding: EdgeInsets.only(bottom: 24),
                textScaler: TextScaler.linear(1.3)),
            child: RideMapShell(
              map: const ColoredBox(color: Color(0xFFE5EBDD)),
              panelMaxHeightFactor: .65,
              panel: const SizedBox(
                  height: 1000, child: Text('تفاصيل الرحلة الطويلة')),
              panelFooter: Column(mainAxisSize: MainAxisSize.min, children: [
                TripEmergencyActions(
                    onShareTrip: () => shared = true,
                    onCancelRide: () => cancelled = true),
                const SizedBox(height: 8),
                const AppButton(label: 'بانتظار اكتمال الرحلة'),
              ]),
            )))));
    await tester.pumpAndSettle();
    for (final icon in [
      Icons.health_and_safety_outlined,
      Icons.ios_share_rounded,
      Icons.cancel_outlined
    ]) {
      final rect = tester.getRect(find.byIcon(icon));
      expect(rect.bottom, lessThan(544));
      expect(find.byIcon(icon).hitTestable(), findsOneWidget);
    }
    await tester.tap(find.byIcon(Icons.ios_share_rounded));
    await tester.tap(find.byIcon(Icons.cancel_outlined));
    expect(shared, isTrue);
    expect(cancelled, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await _capture(tester, boundary, 'trip-actions-footer');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'offer selection keeps cancel visible and countdown inside acceptance button',
      (tester) async {
    _phoneSize(tester);
    final originalMaps = maps.GoogleMapsFlutterPlatform.instance;
    maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
    addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = originalMaps);
    const offer = DriverOffer(
        id: '71',
        driverName: 'سائق الاختبار',
        vehicleSummary: 'تويوتا كورولا',
        price: 1500,
        rating: 4.8,
        etaMinutes: 2);
    ride.driverOffers.assignAll([offer]);
    ride.requestRecipients.assignAll(const [
      RideRequestViewer(driverId: '2', name: 'سائق الاختبار'),
      RideRequestViewer(driverId: '3', name: 'سائق لم يقدم عرضًا'),
    ]);
    var cancelled = false;
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(RepaintBoundary(
        key: boundary,
        child: RideSearchView(
          onCancel: () => cancelled = true,
          offerCards: [
            DriverOfferTile(
                offer: offer,
                currency: 'ر.ي',
                progress: .5,
                remainingSeconds: 30,
                onAccept: () {},
                onReject: () {})
          ],
        ))));
    await tester.pump();
    expect(find.text('قبول · 30 ث'), findsOneWidget);
    expect(find.text('اختيار سائق'), findsOneWidget);
    expect(find.byKey(const ValueKey('request-recipient-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('request-recipient-3')), findsOneWidget);
    expect(find.text('أُرسل الطلب إلى 2 من السائقين'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, boundary, 'offer-selection');
    await tester.tap(find.text('إلغاء الطلب'));
    expect(cancelled, isTrue);
  });

  testWidgets(
      'all notified driver photos overlap and remain reachable on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ride.requestRecipients.assignAll(List.generate(
        20,
        (i) =>
            RideRequestViewer(driverId: '${i + 1}', name: 'السائق ${i + 1}')));
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(RepaintBoundary(
        key: boundary, child: const SearchRequestRecipients())));
    await tester.pump();
    final first =
        tester.getRect(find.byKey(const ValueKey('request-recipient-1')));
    final second =
        tester.getRect(find.byKey(const ValueKey('request-recipient-2')));
    expect(first.overlaps(second), isTrue);
    expect(first.size, const Size(48, 48));
    expect(find.text('أُرسل الطلب إلى 20 من السائقين'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    await _capture(tester, boundary, 'search-recipient-stack');
    await tester
        .ensureVisible(find.byKey(const ValueKey('request-recipient-20')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('request-recipient-20')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('safety page declares the binding for its ride and safety controllers',
      () {
    expect(
        ridePages.singleWhere((page) => page.name == RideRoutes.safety).binding,
        isA<RideBinding>());
  });

  testWidgets('location search opens without GPS or a pickup coordinate',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox()));
    location.pickup.value = null;
    location.locationPermissionBlocked.value = true;
    final search = location.startSearch(field: 0);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.locationSearch);
    expect(location.activeField.value, 0);
    expect(Get.isSnackbarOpen, isFalse);
    Get.back<bool>(result: true);
    await tester.pumpAndSettle();
    expect(await search, isTrue);
  });

  testWidgets('both route points can be chosen by name without GPS permission',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox()));
    location.resetForNewRide();
    location.locationPermissionBlocked.value = true;
    await location.selectSearchResult(
      const LocationSearchResult(
        title: 'نقطة انطلاق أخرى',
        formattedAddress: 'شارع الزبيري',
        location: LatLng(15.35, 44.20),
      ),
      closeSearchPage: false,
    );
    expect(location.pickup.value, const LatLng(15.35, 44.20));
    expect(location.pickupIsCurrentLocation.value, isFalse);
    expect(location.fromController.text, 'شارع الزبيري');
    expect(location.activeField.value, 1);
    await location.selectSearchResult(
      const LocationSearchResult(
        title: 'وجهة أخرى',
        formattedAddress: 'شارع تعز',
        location: LatLng(15.30, 44.22),
      ),
      closeSearchPage: false,
    );
    expect(location.destination.value, const LatLng(15.30, 44.22));
    expect(location.hasDrivingRoute, isTrue);
    expect(Get.isSnackbarOpen, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  testWidgets('request audit sends actual GPS independently of edited pickup',
      (tester) async {
    final previousGps = GeolocatorPlatform.instance;
    final gps = _BookingGps();
    GeolocatorPlatform.instance = gps;
    addTearDown(() => GeolocatorPlatform.instance = previousGps);
    await tester.pumpWidget(_host(const SizedBox()));
    location.pickup.value = const LatLng(15.35, 44.2);
    ride.setNearbyMapVisible('review', true);
    await tester.pump();
    await booking.refreshQuote();
    await ride.requestRide();
    final draft = repository.requests.single;
    expect(draft.pickupCoordinate.latitude, 15.35);
    expect(draft.passengerCoordinate!.latitude, 15.36);
    expect(draft.passengerCoordinate!.longitude, 44.19);
    expect(draft.passengerObservedAt, gps.observedAt);
    await ApiRideNegotiationRepository(api)
        .createRequest(draft.withPrice(1600));
    expect(api.payload['pickupLatitude'], 15.35);
    expect(api.payload['passengerLatitude'], 15.36);
    expect(api.payload['passengerLongitude'], 44.19);
    expect(api.payload['passengerAccuracy'], 8);
    expect(api.payload['passengerObservedAtUtc'],
        gps.observedAt.toIso8601String());
    ride.setNearbyMapVisible('review', false);
    ride.prepareNewRide();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'manual booking without a GPS fix leaves request audit position unknown',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    await ride.requestRide();
    final draft = repository.requests.single;
    expect(draft.passengerCoordinate, isNull);
    await ApiRideNegotiationRepository(api).createRequest(draft);
    expect(
        api.payload.keys.where((key) => key.startsWith('passengerL')), isEmpty);
    expect(api.payload.containsKey('passengerObservedAtUtc'), isFalse);
    expect(api.payload.containsKey('passengerAccuracy'), isFalse);
    expect(api.payload['pickupLatitude'], 15.36);
    ride.prepareNewRide();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('map selection respects the destination field without an origin',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox()));
    location.resetForNewRide();
    location.locationPermissionBlocked.value = true;
    location.activeField.value = 1;
    await location.selectMapPoint(const LatLng(15.30, 44.22));
    expect(location.destination.value, const LatLng(15.30, 44.22));
    expect(location.pickup.value, isNull);
    expect(location.hasCompleteRoute, isFalse);
    expect(Get.isSnackbarOpen, isFalse);
  });

  testWidgets(
      'search countdown expires after one minute without fabricating viewers',
      (tester) async {
    Get.put<TrackingHubService>(_QuietHub());
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    ride.currentSearchTime = DateTime.utc(2026, 10, 19);
    await ride.requestRide();
    expect(ride.searchRemainingSeconds.value, 60);
    expect(ride.requestViewers, isEmpty);
    ride.currentSearchTime =
        ride.currentSearchTime!.add(const Duration(seconds: 14));
    await tester.pump(const Duration(seconds: 1));
    expect(ride.searchRemainingSeconds.value, 46);
    ride.currentSearchTime =
        ride.currentSearchTime!.add(const Duration(seconds: 46));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(ride.searchRemainingSeconds.value, 0);
    expect(ride.isSearchingForDriver.value, isFalse);
    expect(ride.offersExhausted.value, isTrue);
    expect(repository.closedAsExhausted, isEmpty,
        reason:
            'Timeout must preserve the request until the customer chooses.');
    await ride.cancelDriverSearch();
    expect(repository.closedAsExhausted, [false]);
  });

  testWidgets('notification system back returns home from the root page',
      (tester) async {
    final session = AuthSessionService(SecureStorageService(), api);
    Get.put(NotificationsController(api, session, _QuietHub()));
    await tester.pumpWidget(_host(const NotificationsPage()));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(Get.currentRoute, RideRoutes.homeTransport);
  });

  testWidgets('notification toolbar back returns home from the root page',
      (tester) async {
    final session = AuthSessionService(SecureStorageService(), api);
    Get.put(NotificationsController(api, session, _QuietHub()));
    await tester.pumpWidget(_host(const NotificationsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.homeTransport);
  });

  testWidgets('expired search offers retry and ends only after customer choice',
      (tester) async {
    _phoneSize(tester);
    final originalMaps = maps.GoogleMapsFlutterPlatform.instance;
    maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
    addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = originalMaps);
    Get.put<TrackingHubService>(_QuietHub());
    await tester.pumpWidget(_host(const SizedBox(), realReview: true));
    await booking.refreshQuote();
    ride.currentSearchTime = DateTime.utc(2026, 11, 2);
    await ride.requestRide();
    Get.toNamed<void>(RideRoutes.negotiationQuote);
    await tester.pump();
    ride.currentSearchTime =
        ride.currentSearchTime!.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('search_retry'.tr), findsOneWidget);
    expect(find.text('search_end_trip'.tr), findsOneWidget);
    expect(repository.closedAsExhausted, isEmpty);
    repository.pendingRestart = Completer<int>();
    await tester.tap(find.text('search_retry'.tr));
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.restartedPrices, hasLength(1));
    expect(find.byKey(const ValueKey('search-retry-progress')), findsOneWidget);
    expect(ride.searchRemainingSeconds.value, 0,
        reason: 'The timer must wait for a confirmed restart.');
    await ride.retryDriverSearch();
    expect(repository.restartedPrices, hasLength(1));
    repository.pendingRestart!.complete(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(ride.isSearchingForDriver.value, isTrue);
    expect(ride.searchRemainingSeconds.value, 60);
    expect(find.byKey(const ValueKey('search-retry-progress')), findsNothing);
    ride.currentSearchTime =
        ride.currentSearchTime!.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(ride.searchRemainingSeconds.value, 59);
    ride.currentSearchTime =
        ride.currentSearchTime!.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('search_end_trip'.tr));
    await tester.pumpAndSettle();
    expect(repository.closedAsExhausted, [false]);
    expect(ride.currentRideId, isNull);
    expect(Get.currentRoute, RideRoutes.homeTransport);
  });

  testWidgets(
      'retry reaches API and reads offers while nearby and Hub are stalled',
      (tester) async {
    final hub = Get.put<TrackingHubService>(_QuietHub()) as _QuietHub;
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    await ride.requestRide();
    ride.pendingNearby = Completer<void>();
    hub.pendingJoin = Completer<void>();
    addTearDown(() {
      if (!ride.pendingNearby!.isCompleted) ride.pendingNearby!.complete();
      if (!hub.pendingJoin!.isCompleted) hub.pendingJoin!.complete();
    });
    final initialReads = repository.detailReads;
    final retry = ride.retryDriverSearch();
    await tester.pump();
    expect(repository.restartedPrices, [null]);
    expect(ride.nearbyLoads, 0,
        reason: 'Map discovery cannot hold a requested search restart.');
    expect(repository.detailReads, greaterThan(initialReads));
    expect(ride.isRetryingSearch.value, false);
    expect(ride.isSearchingForDriver.value, true);
    expect(ride.searchRemainingSeconds.value, 60);
    await retry;
    hub.pendingJoin!.complete();
    await tester.pump();
    await ride.cancelDriverSearch();
  });

  testWidgets('failed retry presents the reason and can retry the same ride',
      (tester) async {
    _phoneSize(tester);
    final originalMaps = maps.GoogleMapsFlutterPlatform.instance;
    maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
    addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = originalMaps);
    Get.put<TrackingHubService>(_QuietHub());
    await tester.pumpWidget(_host(const SizedBox(), realReview: true));
    await booking.refreshQuote();
    ride.currentSearchTime = DateTime.utc(2026, 11, 4);
    await ride.requestRide();
    Get.toNamed<void>(RideRoutes.negotiationQuote);
    await tester.pump();
    ride.currentSearchTime =
        ride.currentSearchTime!.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    repository.failRestart = true;
    await tester.tap(find.text('search_retry'.tr));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('تعذر إعادة الإرسال'), findsOneWidget);
    expect(find.text('search_retry'.tr), findsOneWidget);
    expect(ride.currentRideId, '42');
    expect(ride.isSearchingForDriver.value, false);
    repository.failRestart = false;
    await tester.tap(find.text('search_retry'.tr));
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.restartedPrices, [null, null]);
    expect(repository.requests, hasLength(1));
    expect(ride.isSearchingForDriver.value, true);
    expect(ride.searchRemainingSeconds.value, 60);
    await ride.cancelDriverSearch();
  });

  testWidgets('late restart acknowledgement cannot resurrect a cleared request',
      (tester) async {
    Get.put<TrackingHubService>(_QuietHub());
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    await ride.requestRide();
    repository.pendingRestart = Completer<int>();
    final retry = ride.retryDriverSearch();
    ride.prepareNewRide();
    repository.pendingRestart!.complete(1);
    await retry;
    expect(ride.currentRideId, isNull);
    expect(ride.isSearchingForDriver.value, false);
    expect(ride.isRetryingSearch.value, false);
  });

  testWidgets(
      'older initial offer snapshot cannot erase the post-join snapshot',
      (tester) async {
    final hub = Get.put<TrackingHubService>(_QuietHub()) as _QuietHub;
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    await ride.requestRide();
    hub.pendingJoin = Completer<void>();
    final initial = Completer<Map<String, Object?>>();
    final joined = Completer<Map<String, Object?>>();
    repository.detailResponses.addAll([initial, joined]);
    await ride.retryDriverSearch();
    await tester.pump();
    hub.pendingJoin!.complete();
    await tester.pump();
    const offer = DriverOffer(
        id: 'latest',
        driverName: 'السائق',
        price: 1500,
        etaMinutes: 2,
        rating: 4.5,
        vehicleSummary: 'سيارة');
    joined.complete({
      'ride': {'status': 2},
      'offers': [
        {'offer': offer}
      ]
    });
    await tester.pump();
    expect(ride.driverOffers.map((item) => item.id), ['latest']);
    initial.complete({
      'ride': {'status': 1},
      'offers': <Object?>[]
    });
    await tester.pump();
    expect(ride.driverOffers.map((item) => item.id), ['latest']);
    await ride.cancelDriverSearch();
  });

  test('cancellation repository preserves decision and never assumes safe stop',
      () async {
    final repository = ApiRideNegotiationRepository(api);
    api.response = {'id': 21, 'rideId': 42, 'rideStatus': 7, 'status': 3};
    final decision = await repository.requestCancellation('42', 'تغيير الخطة');
    expect(decision?['status'], 3);
    expect(decision?['rideStatus'], 7);
    expect(api.payload['safeStopConfirmed'], false);
    await repository.requestCancellation('42', 'تغيير الخطة',
        safeStopConfirmed: true);
    expect(api.payload['safeStopConfirmed'], true);
  });

  testWidgets(
      'search fare confirmation updates the same request once after server success',
      (tester) async {
    Get.put<TrackingHubService>(_QuietHub());
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    await ride.requestRide();
    expect(ride.canConfirmSearchPrice, isFalse);
    ride.changeSearchPrice(1);
    expect(ride.pendingSearchPrice.value, 1600);
    expect(ride.currentDraft.value!.offeredPrice, 1500);
    expect(ride.canConfirmSearchPrice, isTrue);
    repository.pendingRestart = Completer<int>();
    final confirm = ride.confirmSearchPrice();
    await ride.confirmSearchPrice();
    expect(repository.restartedPrices, [1600]);
    expect(ride.currentDraft.value!.offeredPrice, 1500);
    repository.pendingRestart!.complete(2);
    await confirm;
    expect(ride.currentRideId, '42');
    expect(repository.requests.length, 1);
    expect(ride.currentDraft.value!.offeredPrice, 1600);
    expect(ride.canConfirmSearchPrice, isFalse);
    expect(ride.searchRemainingSeconds.value, 60);
    await ride.cancelDriverSearch();
  });

  testWidgets('failed search fare change preserves the sent fare and can retry',
      (tester) async {
    Get.put<TrackingHubService>(_QuietHub());
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    await ride.requestRide();
    repository.failRestart = true;
    ride.changeSearchPrice(1);
    await ride.confirmSearchPrice();
    expect(ride.currentDraft.value!.offeredPrice, 1500);
    expect(ride.offeredPrice.value, 1500);
    expect(ride.pendingSearchPrice.value, 1600);
    expect(ride.canConfirmSearchPrice, isTrue);
    Get.closeAllSnackbars();
    await tester.pump(const Duration(seconds: 1));
    await ride.cancelDriverSearch();
  });

  for (final scenario in [
    (const Size(390, 844), false),
    (const Size(320, 568), true)
  ]) {
    testWidgets('search panel matches the requested sections on ${scenario.$1}',
        (tester) async {
      tester.view.physicalSize = scenario.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final originalMaps = maps.GoogleMapsFlutterPlatform.instance;
      maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
      addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = originalMaps);
      Get.put<TrackingHubService>(_QuietHub());
      await booking.refreshQuote();
      await ride.requestRide();
      ride.preferredPaymentMethod.value = 'wallet';
      ride.requestViewers.assignAll(List.generate(
          7, (i) => RideRequestViewer(driverId: '$i', name: 'سائق $i')));
      final boundary = GlobalKey();
      var cancelled = false;
      await tester.pumpWidget(_host(
          RepaintBoundary(
              key: boundary,
              child: RideSearchView(onCancel: () => cancelled = true)),
          theme: scenario.$2 ? AppTheme.dark : AppTheme.light));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('يشاهد 7 سائقين طلبك'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('search-confirm-price')))
              .onPressed,
          isNull);
      if (!scenario.$2)
        await _capture(tester, boundary, 'search-waiting-light');
      await tester.tap(find.byKey(const ValueKey('search-price-plus')));
      await tester.pump();
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('search-confirm-price')))
              .onPressed,
          isNotNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('search-payment-method')),
        100,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('search-sheet')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
          find.byKey(const ValueKey('search-payment-method')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-cancel')));
      expect(cancelled, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await ride.cancelDriverSearch();
    });
  }

  testWidgets('quote updates in place and discards a stale route response',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox()));
    final first = Completer<RideQuote>();
    final second = Completer<RideQuote>();
    repository.quotes.addAll([first, second]);
    final request1 = booking.refreshQuote();
    location.isRouteLoading.value = true;
    location.destination.value = const LatLng(15.40, 44.23);
    expect(booking.canSubmit, isFalse);
    location.routeDistanceMeters.value = 5000;
    location.isRouteLoading.value = false;
    final request2 = booking.refreshQuote();
    second.complete(_quote);
    await request2;
    expect(booking.canSubmit, isTrue);
    first.complete(const RideQuote(
        suggestedPrice: 300,
        minPrice: 300,
        maxPrice: 300,
        priceStep: 1,
        currency: 'YER'));
    await request1;
    expect(ride.offeredPrice.value, 1500);
    expect(Get.currentRoute, '/');
    expect(repository.lastDistance, 5);
  });

  testWidgets(
      'changing service invalidates price and prevents mismatched requests',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    expect(booking.canSubmit, isTrue);
    ride.selectedServiceKindId.value = 2;
    expect(ride.quote.value, isNull);
    expect(booking.canSubmit, isFalse);
    await booking.submit();
    expect(repository.requests, isEmpty);
  });

  testWidgets('route loading and unavailable areas cannot submit',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    location.serviceAreaAvailable.value = false;
    await booking.submit();
    expect(repository.requests, isEmpty);
    location.serviceAreaAvailable.value = true;
    location.isRouteLoading.value = true;
    await booking.submit();
    expect(repository.requests, isEmpty);
  });

  testWidgets('typing a new address invalidates its previous map point',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    location.toController.text = 'عنوان جديد لم يتم اختياره';
    location.clearRouteField(1, clearText: false);
    expect(location.toController.text, 'عنوان جديد لم يتم اختياره');
    expect(location.destination.value, isNull);
    expect(booking.canSubmit, isFalse);
    await booking.submit();
    expect(repository.requests, isEmpty);
  });

  testWidgets(
      'single submit uses the current fare and details without address-name screen',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    expect(ride.setBookingPrice('١٧٥٠'), isTrue);
    expect(ride.setBookingPrice('0'), isFalse);
    expect(ride.setBookingPrice('-2'), isFalse);
    expect(ride.setBookingPrice('10.5'), isFalse);
    location.detailsController.text = 'المدخل الجنوبي';
    ride.preferredPaymentMethod.value = 'wallet';
    repository.pendingRequest = Completer<RideSearchStartResult>();
    final submit = booking.submit();
    await booking.submit();
    expect(repository.requests, hasLength(1));
    expect(ride.bookingLocked, isTrue);
    expect(ride.setBookingPrice('2000'), isFalse);
    final draft = repository.requests.single;
    expect(draft.serviceCatalogItemId, 12);
    expect(draft.offeredPrice, 1750);
    expect(draft.destinationAddress, 'ميدان التحرير — المدخل الجنوبي');
    expect(draft.destination, 'ميدان التحرير');
    expect(draft.destinationAddressName, isEmpty);
    repository.pendingRequest!
        .complete(const RideSearchStartResult(rideId: '42', recipientCount: 2));
    await submit;
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.negotiationQuote);
    expect(ride.preferredPaymentMethod.value, 'wallet');
    expect(draft.paymentMethodCode, 'wallet');
    await booking.submit();
    expect(repository.requests, hasLength(1));
    ride.prepareNewRide();
    await tester.pump();
  });

  testWidgets('existing RideModel payload keeps fare and address contract',
      (tester) async {
    final api = _Api(SecureStorageService());
    final repo = ApiRideNegotiationRepository(api);
    await repo.createRequest(const RideRequestDraft(
      pickup: 'أ',
      destination: 'ب',
      pickupCoordinate: RideCoordinate(latitude: 15, longitude: 44),
      destinationCoordinate: RideCoordinate(latitude: 16, longitude: 45),
      serviceKindId: 1,
      serviceCatalogItemId: 12,
      offeredPrice: 1750,
      pickupAddress: 'شارع حدة',
      destinationAddress: 'ميدان التحرير — المدخل الجنوبي',
      paymentMethodCode: 'JAIB',
    ));
    expect(api.model, 'RideModel');
    expect(api.operation, 'add');
    expect(api.payload['customerPrice'], 1750);
    expect(api.payload['destinationAddress'], contains('المدخل الجنوبي'));
    expect(api.payload.containsKey('paymentMethod'), isFalse);
    expect(api.payload['paymentMethodCode'], 'JAIB');
  });

  testWidgets(
      'continue reviews price, preserves choices and searches only once',
      (tester) async {
    final originalMaps = maps.GoogleMapsFlutterPlatform.instance;
    maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
    addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = originalMaps);
    await booking.refreshQuote();
    location.detailsController.text = 'المدخل الجنوبي';
    await tester
        .pumpWidget(_host(const BookingContinueBar(), realReview: true));
    expect(find.byType(RidePaymentPreferenceButton), findsNothing);
    expect(find.text('booking_search'.tr), findsNothing);
    await tester.tap(find.text('متابعة الطلب'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(Get.currentRoute, RideRoutes.negotiationQuote);
    expect(find.byType(BookingReviewPanel), findsOneWidget);
    expect(repository.requests, isEmpty);
    expect(ride.isSearchingForDriver.value, isFalse);
    await tester.tap(find.byTooltip('review_invoice'.tr));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('تفاصيل الوصول: المدخل الجنوبي'), findsOneWidget);
    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('زيادة السعر'));
    await tester.pump();
    expect(ride.offeredPrice.value, 1600);
    expect(tester.widget<Text>(find.byKey(const ValueKey('review-fare'))).data,
        '1600 YER');
    await tester.tap(find.byTooltip('إنقاص السعر'));
    await tester.pump();
    expect(ride.offeredPrice.value, 1500);
    await tester.tap(find.byTooltip('طريقة الدفع'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('المحفظة'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(ride.preferredPaymentMethod.value, 'wallet');
    expect(repository.requests, isEmpty);
    Get.back<void>();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(Get.currentRoute, '/');
    await tester.tap(find.text('متابعة الطلب'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(ride.preferredPaymentMethod.value, 'wallet');
    expect(ride.offeredPrice.value, 1500);
    repository.pendingRequest = Completer<RideSearchStartResult>();
    await tester.tap(find.text('booking_search'.tr));
    await tester.tap(find.text('booking_search'.tr));
    await tester.pump();
    expect(repository.requests, hasLength(1));
    final draft = repository.requests.single;
    expect(draft.serviceKindId, 1);
    expect(draft.serviceCatalogItemId, 12);
    expect(draft.offeredPrice, 1500);
    expect(draft.destinationAddress, 'ميدان التحرير — المدخل الجنوبي');
    expect(ride.bookingLocked, isTrue);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'زيادة السعر'))
            .onPressed,
        isNull);
    repository.pendingRequest!
        .complete(const RideSearchStartResult(rideId: '42', recipientCount: 2));
    await tester.pump();
    expect(ride.isSearchingForDriver.value, isTrue);
    expect(find.byType(BookingReviewPanel), findsNothing);
    expect(repository.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    ride.prepareNewRide();
  });

  testWidgets('fare buttons use editable fare rules and stop at valid bounds',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.refreshQuote();
    ride.decreasePrice();
    expect(ride.offeredPrice.value, 1400);
    expect(_quote.totalForFare(ride.offeredPrice.value), 1500);
    ride.setBookingPrice('١٠٠٠');
    ride.decreasePrice();
    expect(ride.offeredPrice.value, 1000);
    expect(ride.setBookingPrice('999'), isFalse);
    ride.setBookingPrice('2000');
    ride.increasePrice();
    expect(ride.offeredPrice.value, 2000);
    expect(ride.setBookingPrice('2001'), isFalse);
    expect(ride.setBookingPrice('1000000000'), isFalse);
    expect(ride.setBookingPrice('NaN'), isFalse);
    expect(_quote.totalForFare(ride.offeredPrice.value), 2100);
  });

  testWidgets('review invalidates stale fare and retries a quote failure',
      (tester) async {
    await booking.refreshQuote();
    await tester.pumpWidget(_host(const RideMapShell(
      map: ColoredBox(color: Color(0xFFE5EBDD)),
      fitPanelToContent: true,
      panelMaxHeightFactor: .84,
      panel: BookingReviewPanel(),
      panelFooter: BookingSubmitBar(),
    )));
    location.routeDistanceMeters.value = 4000;
    final failed = Completer<RideQuote>();
    repository.quotes.add(failed);
    final pending = booking.refreshQuote();
    failed.completeError(const FormatException('تعذر حساب السعر'));
    await pending;
    await tester.pump();
    expect(find.byKey(const ValueKey('review-total')), findsNothing);
    expect(find.text('تعذر حساب السعر'), findsOneWidget);
    expect(
        tester
            .widget<AppButton>(
                find.widgetWithText(AppButton, 'booking_search'.tr))
            .onPressed,
        isNull);
    await tester.tap(find.text('إعادة حساب السعر'));
    await tester.pumpAndSettle();
    expect(booking.canSubmit, isTrue);
    expect(find.byKey(const ValueKey('review-fare')), findsOneWidget);
    expect(repository.requests, isEmpty);
  });

  testWidgets(
      'home previews a valid route and opens review once without creating a request',
      (tester) async {
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pumpAndSettle();
    final preview = Completer<void>();
    var previewCount = 0;
    final navigation = booking.continueFromHome(
        vehicle: _vehicle,
        previewRoute: () {
          previewCount++;
          return preview.future;
        });
    await tester.pump();
    await booking.continueFromHome(vehicle: _vehicle);
    expect(previewCount, 1);
    expect(Get.currentRoute, '/');
    preview.complete();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.negotiationQuote);
    expect(repository.requests, isEmpty);
    Get.back<void>();
    await tester.pumpAndSettle();
    await navigation;
    expect(booking.isOpeningHomeBooking.value, isFalse);
  });

  testWidgets(
      'home waits for the selected driving route then continues automatically',
      (tester) async {
    location.destination.value = null;
    location.routePoints.clear();
    location.onSearch = (field) async {
      location.destination.value = const LatLng(15.38, 44.21);
      location.isRouteLoading.value = true;
      return true;
    };
    await tester.pumpWidget(_host(const SizedBox()));
    final navigation = booking.continueFromHome(vehicle: _vehicle);
    await tester.pump();
    expect(location.searchedFields, [1]);
    expect(Get.currentRoute, '/');
    expect(booking.isOpeningHomeBooking.value, isTrue);
    location.routePoints
        .assignAll([location.pickup.value!, location.destination.value!]);
    location.isRouteLoading.value = false;
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.negotiationQuote);
    expect(repository.requests, isEmpty);
    Get.back<void>();
    await tester.pumpAndSettle();
    await navigation;
  });

  testWidgets(
      'cancelling home location search never resumes on a later GPS update',
      (tester) async {
    location.destination.value = null;
    location.routePoints.clear();
    location.onSearch = (_) async => false;
    await tester.pumpWidget(_host(const SizedBox()));
    await booking.continueFromHome(vehicle: _vehicle);
    expect(booking.isOpeningHomeBooking.value, isFalse);
    location.destination.value = const LatLng(15.38, 44.21);
    location.routePoints
        .assignAll([location.pickup.value!, location.destination.value!]);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, '/');
    expect(repository.requests, isEmpty);
  });

  testWidgets('home address rows edit their own field and keep arrival details',
      (tester) async {
    location.onSearch = (_) async => false;
    await tester
        .pumpWidget(_host(const SingleChildScrollView(child: BookingPanel())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-pickup')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-destination')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-route-search')));
    await tester.pumpAndSettle();
    expect(location.searchedFields, [0, 1, 1]);
    await tester.tap(find.byKey(const ValueKey('home-address-details')));
    await tester.pumpAndSettle();
    expect(find.byType(BookingDetailsSheet), findsOneWidget);
    expect(repository.requests, isEmpty);
    Get.back<void>();
    await tester.pumpAndSettle();
  });

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets('home sheet expands and collapses within bounds on $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final originalMaps = maps.GoogleMapsFlutterPlatform.instance;
      maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
      addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = originalMaps);
      ride.homeServices.assignAll(const [
        RideHomeService(
            id: 1, code: 'transport', name: 'رحلات المدينة', isDefault: true),
        RideHomeService(id: 2, code: 'delivery', name: 'التوصيل'),
        RideHomeService(id: 3, code: 'travel', name: 'سفر'),
        RideHomeService(id: 4, code: 'cargo', name: 'الشحن'),
      ]);
      location.destination.value = null;
      location.routePoints.clear();
      final boundary = GlobalKey();
      await tester.pumpWidget(_host(RepaintBoundary(
          key: boundary,
          child: MediaQuery(
              data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(size.width == 320 ? 1.4 : 1)),
              child: const LocationPickerPage(isMainShell: true)))));
      await tester.pump();
      expect(find.byKey(const ValueKey('home-pickup')), findsNothing);
      expect(find.byKey(const ValueKey('home-address-details')), findsNothing);
      expect(find.byType(BookingContinueBar), findsNothing);
      expect(find.byKey(const ValueKey('home-continue-icon')), findsOneWidget);
      final sheet = tester.widget<DraggableScrollableSheet>(
          find.byType(DraggableScrollableSheet));
      expect(sheet.controller!.size, closeTo(.64, .01));
      if (size.width == 390)
        await _capture(tester, boundary, 'home-before-route');
      await tester.drag(find.byKey(const ValueKey('home-sheet-handle')),
          const Offset(0, -550));
      await tester.pump(const Duration(seconds: 1));
      expect(sheet.controller!.size, closeTo(.90, .01));
      await tester.drag(find.byKey(const ValueKey('home-sheet-handle')),
          const Offset(0, 900));
      await tester.pump(const Duration(seconds: 1));
      expect(sheet.controller!.size * size.height, closeTo(44, 1));
      expect(find.byKey(const ValueKey('home-route-search')), findsNothing);
      if (size.width == 390)
        await _capture(tester, boundary, 'home-sheet-collapsed');
      await tester.drag(find.byKey(const ValueKey('home-sheet-handle')),
          const Offset(0, -550));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('home-route-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'review requires an explicit service and moves fare controls with selection',
      (tester) async {
    ride.catalogVehicles.assignAll([_vehicle, _secondVehicle]);
    ride.selectedVehicle.value = null;
    await tester.pumpWidget(_host(const Column(children: [
      Expanded(child: SingleChildScrollView(child: BookingReviewPanel())),
      BookingReviewFooter(),
    ])));
    booking.reviewOpened();
    await tester.pumpAndSettle();
    expect(booking.canSubmit, isFalse);
    expect(find.byTooltip('زيادة السعر'), findsNothing);
    expect(
        tester
            .widget<AppButton>(
                find.widgetWithText(AppButton, 'booking_search'.tr))
            .onPressed,
        isNull);
    expect(find.text('~ 1500 YER'), findsNWidgets(2));
    final requestsBeforeSelection = repository.quotedCatalogIds.length;
    await tester.tap(find.byKey(const ValueKey('review-service-13')));
    await tester.pumpAndSettle();
    expect(ride.selectedVehicle.value!.id, '13');
    expect(booking.canSubmit, isTrue);
    expect(ride.routeDistanceKm.value, 3);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('review-service-13')),
            matching: find.byTooltip('زيادة السعر')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-service-12')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('review-service-12')),
            matching: find.byTooltip('زيادة السعر')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('review-service-13')),
            matching: find.byTooltip('زيادة السعر')),
        findsNothing);
    expect(repository.quotedCatalogIds.length, requestsBeforeSelection);
    expect(repository.requests, isEmpty);
    booking.reviewClosed();
  });

  testWidgets('review prices ignore delayed responses after the route changes',
      (tester) async {
    ride.catalogVehicles.assignAll([_vehicle, _secondVehicle]);
    ride.selectedVehicle.value = null;
    await tester.pumpWidget(_host(const SizedBox()));
    final first = Completer<RideQuote>();
    final second = Completer<RideQuote>();
    repository.quotes.addAll([first, second]);
    final oldPrices = booking.loadReviewQuotes();
    location.routeDistanceMeters.value = 5000;
    first.complete(_quote);
    second.complete(_quote);
    await oldPrices;
    expect(booking.reviewQuotes, isEmpty);
    await booking.loadReviewQuotes();
    expect(booking.reviewQuotes.keys.toSet(), {'12', '13'});
    expect(repository.lastDistance, 5);
  });

  for (final scenario in [
    (const Size(390, 844), false),
    (const Size(390, 844), true),
    (const Size(320, 568), true)
  ]) {
    testWidgets(
        'review map sheet and pinned actions fit ${scenario.$1} dark=${scenario.$2}',
        (tester) async {
      final size = scenario.$1;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final originalMaps = maps.GoogleMapsFlutterPlatform.instance;
      maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
      addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = originalMaps);
      ride.catalogVehicles.assignAll([_vehicle, _secondVehicle]);
      ride.selectedVehicle.value = _vehicle;
      await booking.refreshQuote();
      final boundary = GlobalKey();
      await tester.pumpWidget(_host(
          RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                  data: MediaQueryData(
                      size: size,
                      textScaler:
                          TextScaler.linear(size.width == 320 ? 1.35 : 1)),
                  child: BookingReviewView(onClose: () {}))),
          theme: scenario.$2 ? AppTheme.dark : AppTheme.light));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final footerBefore = tester.getRect(find.byType(BookingReviewFooter));
      if (size.width == 390 && !scenario.$2)
        await _capture(tester, boundary, 'price-review-light');
      await tester.tap(find.byTooltip('إضافة الوجهة إلى المفضلة'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('إضافة الوجهة إلى المفضلة'), findsOneWidget);
      expect(location.destination.value, const LatLng(15.38, 44.21));
      expect(find.byType(BookingReviewRouteCard), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.drag(find.byKey(const ValueKey('review-sheet-handle')),
          const Offset(0, -550));
      await tester.pump(const Duration(seconds: 1));
      final sheet = tester.widget<DraggableScrollableSheet>(
          find.byType(DraggableScrollableSheet));
      expect(sheet.controller!.size, closeTo(.98, .01));
      expect(tester.getRect(find.byType(BookingReviewFooter)), footerBefore);
      expect(tester.takeException(), isNull);
      if (size.width == 390 && scenario.$2)
        await _capture(tester, boundary, 'price-review-dark-expanded');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'a new ride after completion accepts the new offer from the same driver with fresh identities',
      (tester) async {
    Get.put<TrackingHubService>(_QuietHub());
    await tester.pumpWidget(_host(const SizedBox()));
    const firstOffer = DriverOffer(
        id: '1838',
        driverName: 'السائق نفسه',
        vehicleSummary: 'السيارة نفسها',
        price: 1500,
        rating: 5,
        etaMinutes: 3,
    );
    const secondOffer = DriverOffer(
        id: '1839',
        driverName: 'السائق نفسه',
        vehicleSummary: 'السيارة نفسها',
        price: 1500,
        rating: 5,
        etaMinutes: 3,
    );
    repository.snapshotOffers = [firstOffer];
    await booking.refreshQuote();
    await ride.requestRide();
    await tester.pump();
    await ride.acceptOffer(ride.driverOffers.single);
    expect(ride.currentRideId, '42');
    expect(ride.acceptedOffer.value?.id, '1838');

    ride.activeRideStatus.value = 'Completed';
    ride.pendingRatingRideId.value = '42';
    ride.ratingSubmitted('42');
    ride.prepareNewRide();
    expect(ride.currentRideId, isNull);
    expect(ride.currentDraft.value, isNull);
    expect(ride.acceptedOffer.value, isNull);
    expect(ride.driverOffers, isEmpty);
    expect(ride.isRespondingToOffer.value, isFalse);

    location.pickup.value = const LatLng(15.36, 44.19);
    location.destination.value = const LatLng(15.38, 44.21);
    location.serviceAreaAvailable.value = true;
    ride.selectedServiceKindId.value = 1;
    ride.catalogVehicles.assignAll([_vehicle]);
    ride.selectedVehicle.value = _vehicle;
    repository.nextRideId = '43';
    repository.snapshotOffers = [secondOffer];
    await booking.refreshQuote();
    await ride.requestRide();
    await tester.pump();
    expect(ride.driverOffers.single.id, '1839');
    await ride.acceptOffer(ride.driverOffers.single);

    expect(repository.acceptedRequests, [('42', '1838'), ('43', '1839')]);
    expect(repository.requests, hasLength(2));
    expect(repository.requests.first.idempotencyKey, isNotEmpty);
    expect(
      repository.requests.last.idempotencyKey,
      isNot(repository.requests.first.idempotencyKey),
    );
    expect(ride.currentRideId, '43');
    expect(ride.acceptedOffer.value?.id, '1839');
    expect(ride.isDriverAssigned.value, isTrue);
    await tester.pumpWidget(const SizedBox());
    ride.prepareNewRide();
  });

  for (final autoAccept in [false, true]) {
    testWidgets(
        'matching-price acceptance uses the API only when enabled=$autoAccept',
        (tester) async {
      Get.put<TrackingHubService>(_QuietHub());
      repository.snapshotOffers = [
        const DriverOffer(
            id: 'different',
            driverName: 'سائق',
            vehicleSummary: 'سيارة',
            price: 1500.01,
            rating: 5,
            etaMinutes: 3),
        const DriverOffer(
            id: 'matching',
            driverName: 'سائق',
            vehicleSummary: 'سيارة',
            price: 1500,
            rating: 5,
            etaMinutes: 3),
      ];
      await tester.pumpWidget(_host(const SizedBox()));
      await booking.refreshQuote();
      ride.autoAcceptMatchingPrice.value = autoAccept;
      await booking.submit();
      await tester.pump();
      expect(repository.acceptedOfferIds, autoAccept ? ['matching'] : isEmpty);
      expect(repository.requests.single.offeredPrice, 1500);
      expect(ride.acceptedOffer.value?.id, autoAccept ? 'matching' : null);
      await tester.pumpWidget(const SizedBox());
      ride.prepareNewRide();
    });
  }

  testWidgets(
      'sheet motion keeps native map configuration stable until settled',
      (tester) async {
    _phoneSize(tester);
    final originalMaps = maps.GoogleMapsFlutterPlatform.instance;
    final platform = _MapPlatform();
    maps.GoogleMapsFlutterPlatform.instance = platform;
    addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = originalMaps);
    location.destination.value = null;
    location.routePoints.clear();
    await tester.pumpWidget(_host(const LocationPickerPage(isMainShell: true)));
    await tester.pump(const Duration(milliseconds: 500));
    final sheet = tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet));
    final before = platform.builds;
    for (var frame = 1; frame <= 30; frame++) {
      sheet.controller!.jumpTo(.64 - frame * .012);
      await tester.pump(const Duration(milliseconds: 16));
    }
    final during = platform.builds - before;
    await tester.pump(const Duration(milliseconds: 250));
    debugPrint(
        'MAP_BENCHMARK: 30 sheet frames, $during map rebuilds during motion, '
        '${platform.builds - before} including settled update');
    expect(during, 0);
    expect(platform.builds - before, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('service cards update the booking and keep the choice visible',
      (tester) async {
    ride.homeServices.assignAll(const [
      RideHomeService(
          id: 1, code: 'transport', name: 'توصيل مشوار', isDefault: true),
      RideHomeService(id: 2, code: 'delivery', name: 'توصيل طلبات'),
    ]);
    await booking.refreshQuote();
    await tester
        .pumpWidget(_host(const SingleChildScrollView(child: BookingPanel())));
    expect(
        tester
            .widget<BookingServiceKindsStrip>(
                find.byType(BookingServiceKindsStrip))
            .selectedId,
        1);
    await tester.tap(find.byKey(const ValueKey('home-kind-2')));
    await tester.pumpAndSettle();
    expect(ride.selectedServiceKindId.value, 2);
    expect(ride.quote.value, isNull);
    expect(
        tester
            .widget<BookingServiceKindsStrip>(
                find.byType(BookingServiceKindsStrip))
            .selectedId,
        2);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(repository.requests, isEmpty);
  });

  testWidgets('service API metadata and admin default reach the selected card',
      (tester) async {
    api.response = [
      {
        'id': 1,
        'code': 'transport',
        'nameAr': 'نوع من الخادم',
        'imageUrl': 'assets/missing-service.png',
        'description': 'وصف من الخادم',
        'isActive': true,
        'isDefault': true
      },
      {'id': 2, 'code': 'delivery', 'nameAr': 'نوع موقوف', 'isActive': false},
    ];
    ride.selectedServiceKindId.value = null;
    ride.autoStartTransport.value = false;
    final loading = ride.loadHomeServices();
    expect(ride.isHomeServicesLoading.value, isTrue);
    await loading;
    expect(ride.homeServices, hasLength(1));
    expect(ride.selectedServiceKindId.value, 1);
    expect(ride.homeServices.single.imageUrl, 'assets/missing-service.png');
    await tester
        .pumpWidget(_host(const SingleChildScrollView(child: BookingPanel())));
    await tester.pumpAndSettle();
    final strip = tester.widget<BookingServiceKindsStrip>(
        find.byType(BookingServiceKindsStrip));
    expect(strip.services.single.description, 'وصف من الخادم');
    expect(find.text('نوع موقوف'), findsNothing);
    expect(strip.selectedId, 1);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('service load failure can retry and empty results stay usable',
      (tester) async {
    api.response = 'invalid response';
    await ride.loadHomeServices();
    await tester
        .pumpWidget(_host(const SingleChildScrollView(child: BookingPanel())));
    await tester.pumpAndSettle();
    expect(
        find.text('تعذر تحميل أنواع الرحلات. حاول مرة أخرى.'), findsOneWidget);
    api.response = <Object>[];
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('home_no_services'.tr), findsOneWidget);
    expect(ride.homeServicesError.value, isEmpty);
    expect(ride.isHomeServicesLoading.value, isFalse);
    expect(repository.requests, isEmpty);
  });

  testWidgets(
      'service cards fit long Arabic details and scroll on small screens',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(RepaintBoundary(
      key: boundary,
      child: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 640), textScaler: TextScaler.linear(1.35)),
        child: BookingServiceKindsSheet(
          services: const [
            RideHomeService(
                id: 1, code: 'transport', name: 'توصيل مشوار', isDefault: true),
            RideHomeService(
                id: 2,
                code: 'delivery',
                name: 'نوع رحلة تجريبي باسم طويل',
                description:
                    'وصف تجريبي طويل لاختبار عرض التفاصيل التي تصل من الخادم دون اقتطاع النص.'),
            RideHomeService(id: 3, code: 'other', name: 'خدمة أخرى'),
          ],
          selectedId: 1,
          onSelected: (_) {},
          onClose: () {},
        ),
      ),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('النوع الافتراضي'), findsOneWidget);
    expect(find.text('تم'), findsOneWidget);
    await _capture(tester, boundary, 'service-kind-cards');
    await tester.scrollUntilVisible(find.text('خدمة أخرى'), 150);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets('booking panel fits $size with Arabic text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await booking.refreshQuote();
      final boundary = GlobalKey();
      await tester.pumpWidget(_host(RepaintBoundary(
          key: boundary,
          child: MediaQuery(
              data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(size.width == 320 ? 1.35 : 1)),
              child: const RideMapShell(
                map: ColoredBox(color: Color(0xFFE5EBDD)),
                fitPanelToContent: true,
                panelMaxHeightFactor: .75,
                panel: BookingPanel(),
                panelFooter: BookingContinueBar(),
              )))));
      await tester.pumpAndSettle();
      expect(find.text('ميدان التحرير'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width == 390) await _capture(tester, boundary, 'booking-panel');
    });
  }

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets('review invoice fits $size with Arabic and large prices',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await booking.refreshQuote();
      ride.homeServices.assignAll(const [
        RideHomeService(
            id: 1, code: 'transport', name: 'توصيل مشوار', isDefault: true)
      ]);
      final boundary = GlobalKey();
      await tester.pumpWidget(_host(RepaintBoundary(
        key: boundary,
        child: MediaQuery(
          data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(size.width == 320 ? 1.35 : 1)),
          child: const BookingPriceDetails(),
        ),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width == 390) await _capture(tester, boundary, 'booking-review');
      ride.quote.value = const RideQuote(
          suggestedPrice: 999999999,
          minPrice: 900000000,
          maxPrice: 999999999,
          priceStep: 100,
          serviceFee: 100,
          currency: 'YER');
      ride.setBookingPrice('999999999');
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('review-total'))).bottom,
          lessThan(size.height));
      expect(tester.takeException(), isNull);
      expect(find.text('1000000099 YER'), findsOneWidget);
      if (size.width == 320) {
        await _capture(tester, boundary, 'booking-review-large-text');
      }
    });
  }

  testWidgets('offer card and fare sheet fit large Arabic text and keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var accepted = 0;
    await tester.pumpWidget(_host(MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 568), textScaler: TextScaler.linear(1.35)),
      child: DriverOfferTile(
          offer: const DriverOffer(
              id: '1',
              driverName: 'اسم سائق طويل لاختبار المساحة',
              vehicleSummary: 'تويوتا كورولا بيضاء',
              price: 1750,
              rating: 4.8,
              etaMinutes: 5),
          currency: 'ر.ي',
          onAccept: () => accepted++),
    )));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('قبول'));
    expect(accepted, 1);
    await tester.pumpWidget(_host(const MediaQuery(
      data: MediaQueryData(
          size: Size(320, 568), viewInsets: EdgeInsets.only(bottom: 240)),
      child: BookingFareSheet(
          currentPrice: 1750, suggestedPrice: 1500, currency: 'ر.ي'),
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('اقترح أجرتك'), findsOneWidget);
  });
}

Widget _host(Widget child, {bool realReview = false, ThemeData? theme}) =>
    GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('ar', 'SA'),
      theme: theme ?? AppTheme.light,
      home: Scaffold(body: child),
      getPages: [
        GetPage(
            name: RideRoutes.homeTransport,
            page: () => const Scaffold(body: Text('الرئيسية'))),
        GetPage(
            name: RideRoutes.negotiationQuote,
            page: () => realReview
                ? const NegotiationQuotePage()
                : const Scaffold(body: Text('عروض'))),
        GetPage(
            name: RideRoutes.locationSearch,
            page: () => const Scaffold(body: Text('البحث عن موقع'))),
      ],
    );

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('BOOKING_SCREENSHOTS')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/booking-previews')
      ..createSync(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _QuietRide extends RideController {
  _QuietRide(RideNegotiationRepository repository, AuthSessionService session,
      {ServiceKindRepository? serviceKinds})
      : super(repository, session, null, serviceKinds);
  DateTime? currentSearchTime;
  Completer<void>? pendingNearby;
  int nearbyLoads = 0;
  @override
  DateTime get searchTime => currentSearchTime ?? super.searchTime;
  @override
  // Fixture skips network subscriptions and native marker generation.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onReady() {}
  @override
  Future<void> loadNearbyDrivers({LatLng? center}) async {
    nearbyLoads++;
    await pendingNearby?.future;
  }

  @override
  void driverFound() {
    isSearchingForDriver.value = false;
    isDriverAssigned.value = true;
  }
}

class _QuietLocation extends LocationController {
  _QuietLocation(ApiClient api, AuthSessionService session)
      : super(_Routes(), _Places(), api, session);
  @override
  // Fixture supplies locations without loading storage or native map assets.
  // ignore: must_call_super
  void onInit() {}
  final List<int> searchedFields = [];
  Future<bool> Function(int)? onSearch;
  @override
  Future<bool> startSearch({int field = 1}) {
    searchedFields.add(field);
    return onSearch?.call(field) ?? super.startSearch(field: field);
  }
}

class _Routes implements RouteRepository {
  @override
  Future<DrivingRoute> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
    bool includeSteps = false,
  }) async =>
      DrivingRoute(
        points: [origin, destination],
        distanceMeters: 3000,
        durationSeconds: 480,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MapPlatform extends maps.GoogleMapsFlutterPlatform {
  int builds = 0;
  @override
  Widget buildViewWithConfiguration(
      int creationId, ValueChanged<int> onPlatformViewCreated,
      {required maps.MapWidgetConfiguration widgetConfiguration,
      maps.MapConfiguration mapConfiguration = const maps.MapConfiguration(),
      maps.MapObjects mapObjects = const maps.MapObjects()}) {
    builds++;
    return const ColoredBox(color: Color(0xFFE5EBDD));
  }
}

class _Places implements LocationSearchRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements RideNegotiationRepository {
  int detailReads = 0;
  final detailResponses = <Completer<Map<String, Object?>>>[];
  @override
  Future<List<NearbyDriver>> getNearbyDrivers({
    required RideCoordinate pickup,
    int? serviceKindId,
    int? serviceCatalogItemId,
  }) async =>
      const [];
  @override
  Future<Map<String, Object?>?> getPendingRating() async => null;
  @override
  Future<List<RideRequestViewer>> getRequestRecipients(
          String requestId) async =>
      const [];
  final cancellationReasons = <String?>[];
  final quotes = <Completer<RideQuote>>[];
  final requests = <RideRequestDraft>[];
  final quotedCatalogIds = <int>[];
  final acceptedOfferIds = <String>[];
  final acceptedRequests = <(String, String)>[];
  String nextRideId = '42';
  List<DriverOffer> snapshotOffers = [];
  double? lastDistance;
  Completer<RideSearchStartResult>? pendingRequest;
  Completer<int>? pendingRestart;
  bool failRestart = false;
  final restartedPrices = <double?>[];
  final closedAsExhausted = <bool>[];
  @override
  Future<int> restartSearch(String requestId, {double? customerPrice}) {
    restartedPrices.add(customerPrice);
    if (failRestart) throw const FormatException('تعذر إعادة الإرسال');
    return pendingRestart?.future ?? Future.value(0);
  }

  @override
  Future<void> closeSearch(String requestId,
      {bool exhausted = false, String? reason}) async {
    closedAsExhausted.add(exhausted);
    cancellationReasons.add(reason);
  }

  @override
  Future<List<RideRequestViewer>> getRequestViewers(String requestId) async =>
      const [];
  @override
  Future<RideQuote> getQuote(
      {required int serviceKindId,
      required int serviceCatalogItemId,
      required RideCoordinate pickup,
      required RideCoordinate destination,
      double? distanceKm,
      double? durationMinutes}) async {
    lastDistance = distanceKm;
    quotedCatalogIds.add(serviceCatalogItemId);
    return quotes.isEmpty ? _quote : quotes.removeAt(0).future;
  }

  @override
  Future<RideSearchStartResult> createRequest(RideRequestDraft draft) {
    requests.add(draft);
    return pendingRequest?.future ??
        Future.value(
            RideSearchStartResult(rideId: nextRideId, recipientCount: 0));
  }

  @override
  Future<Map<String, Object?>> getRideDetail(String requestId) async {
    detailReads++;
    if (detailResponses.isNotEmpty) return detailResponses.removeAt(0).future;
    return {
      'ride': {'status': 1},
      'offers': snapshotOffers.map((offer) => {'offer': offer}).toList(),
    };
  }

  @override
  DriverOffer? mapRealtimeOffer(Map<String, Object?> event) =>
      event['offer'] as DriverOffer?;
  @override
  Future<void> acceptOffer(String requestId, String offerId) async {
    acceptedOfferIds.add(offerId);
    acceptedRequests.add((requestId, offerId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BookingGps extends GeolocatorPlatform {
  final observedAt = DateTime.now().toUtc();
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      const Stream.empty();
  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      Position(
          latitude: 15.36,
          longitude: 44.19,
          timestamp: observedAt,
          accuracy: 8,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0);
}

class _LocationAccessPlatform extends GeolocatorPlatform {
  bool enabled = false;
  int permissionRequests = 0;
  int settingsOpened = 0;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;
  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return LocationPermission.whileInUse;
  }

  @override
  Future<bool> openLocationSettings() async {
    settingsOpened++;
    return true;
  }
}

class _QuietHub extends TrackingHubService {
  _QuietHub() : super(SecureStorageService());
  Completer<void>? pendingJoin;
  @override
  Future<void> setRideSubscriptions(Iterable<int> rideIds) async {
    await pendingJoin?.future;
  }

  @override
  Future<void> clearNearbyDriverSubscription() async {}
}

class _Api extends ApiClient {
  _Api(super.storage);
  String? model;
  String? operation;
  Map<String, Object?> payload = {};
  Object response = <String, Object?>{'id': 42};
  @override
  Future<ApiResult<T>> execute<T>(
      {required String model,
      required String operation,
      Object? data,
      T Function(Object?)? parse}) async {
    this.model = model;
    this.operation = operation;
    payload = Map<String, Object?>.from(data! as Map);
    return ApiSuccess<T>(response as T);
  }
}
