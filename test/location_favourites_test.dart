import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:yemen_drive/app/theme/app_theme.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/account/account_routes.dart';
import 'package:yemen_drive/features/account/favourites/controllers/favourites_controller.dart';
import 'package:yemen_drive/features/account/favourites/repositories/favourites_repository.dart';
import 'package:yemen_drive/features/account/favourites/views/favourites_view.dart';
import 'package:yemen_drive/features/account/favourites/widgets/destination_favourites.dart';
import 'package:yemen_drive/features/ride/location_selection/controllers/location_selection_controller.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/location_search_repository.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/route_repository.dart';
import 'package:yemen_drive/features/ride/widgets/ride_location_widgets.dart';
import 'package:yemen_drive/features/ride/models/ride_models.dart';

class Geo extends GeolocatorPlatform {
  bool enabled = true, allowed = true;
  int reads = 0;
  Completer<Position>? waiting;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async =>
      allowed ? LocationPermission.whileInUse : LocationPermission.denied;
  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    reads++;
    return waiting?.future ?? fix;
  }

  Position get fix => Position(
      latitude: 15.36,
      longitude: 44.19,
      timestamp: DateTime.now(),
      accuracy: 8,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0);
}

class Api extends ApiClient {
  Api() : super(SecureStorageService());
  List<Map<String, Object?>> places = [
    {
      'id': 1,
      'label': 'المنزل',
      'kind': 'home',
      'address': 'شارع المنزل',
      'latitude': 15.4,
      'longitude': 44.2
    },
    {
      'id': 2,
      'label': 'مكتب أحمد',
      'kind': 'place',
      'address': 'شارع المكتب',
      'latitude': 15.5,
      'longitude': 44.3
    },
    {
      'id': 3,
      'label': '',
      'kind': 'unnamed',
      'address': 'عنوان بلا اسم',
      'latitude': 15.6,
      'longitude': 44.4
    },
    {
      'id': 4,
      'label': 'فارغ',
      'kind': 'work',
      'address': '',
      'latitude': null,
      'longitude': null
    },
  ];
  Map<String, Object?>? saved;
  @override
  Future<ApiResult<T>> execute<T>(
      {required String model,
      required String operation,
      Object? data,
      T Function(Object?)? parse}) async {
    Object? result = <String, Object?>{};
    if (model == 'SavedPlaceModel' && operation == 'list') result = places;
    if (model == 'SavedPlaceModel' && operation == 'add') {
      saved = Map<String, Object?>.from(data! as Map);
      result = {'id': 5, ...saved!};
    }
    return ApiSuccess(result as T);
  }
}

class Routes implements RouteRepository {
  @override
  Future<DrivingRoute> getDrivingRoute(
          {required LatLng origin,
          required LatLng destination,
          bool includeSteps = false}) async =>
      DrivingRoute(
          points: [origin, destination],
          distanceMeters: 2000,
          durationSeconds: 300);
}

class Places implements LocationSearchRepository {
  @override
  Future<LocationSearchResult?> reverseGeocode(LatLng point) async =>
      LocationSearchResult(
          title: 'الموقع الحالي',
          formattedAddress: 'شارع حدة',
          location: point);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Location extends LocationController {
  Location(Api api, AuthSessionService session)
      : super(Routes(), Places(), api, session);
  @override
  void onInit() {} // Tests avoid unrelated native avatar rendering.
}

void main() {
  late Geo geo;
  late Api api;
  late Location location;
  late AuthSessionService session;
  setUp(() {
    final original = GeolocatorPlatform.instance;
    geo = Geo();
    GeolocatorPlatform.instance = geo;
    addTearDown(() => GeolocatorPlatform.instance = original);
    api = Api();
    session = AuthSessionService(SecureStorageService(), api);
    session.isAuthenticated.value = true;
    session.currentUserId.value = 1;
    location =
        Get.put<LocationController>(Location(api, session), permanent: true)
            as Location;
  });
  tearDown(() => Get.reset());
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GetMaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        theme: AppTheme.light,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(appBar: null, body: Text('home')),
        getPages: [
          GetPage(
              name: '/route-test',
              page: () => Scaffold(
                  appBar: AppBar(
                      title: const Text('أدخل مسارك'),
                      actions: const [RouteFavouritesButton()]),
                  body: const SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: LocationSearchForm()))),
          GetPage(
              name: AccountRoutes.favourites,
              binding: BindingsBuilder(() => Get.lazyPut<FavouritesController>(
                  () => FavouritesController(ApiFavouritesRepository(api, session)))),
              page: () => const FavouritesPage()),
        ]));
    Get.toNamed<void>('/route-test');
    await tester.pumpAndSettle();
  }

  test('permission/service failure can retry and new ride can locate again',
      () async {
    expect(location.fromController.text, isEmpty);
    geo.allowed = false;
    await location.ensureInitialPickupLocation();
    expect(location.pickup.value, isNull);
    geo.allowed = true;
    await location.ensureInitialPickupLocation();
    expect(location.pickup.value, const LatLng(15.36, 44.19));
    location.resetForNewRide();
    await location.ensureInitialPickupLocation();
    expect(geo.reads, 2);
  });
  test('delayed GPS cannot replace manual pickup text or restored route',
      () async {
    geo.waiting = Completer<Position>();
    final pending = location.ensureInitialPickupLocation();
    await Future<void>.delayed(Duration.zero);
    location.clearRouteField(0);
    location.fromController.text = 'انطلاق يدوي';
    geo.waiting!.complete(geo.fix);
    await pending;
    expect(location.pickup.value, isNull);
    expect(location.fromController.text, 'انطلاق يدوي');
  });
  testWidgets(
      'screen opening chooses actual GPS pickup and focuses destination',
      (tester) async {
    await open(tester);
    expect(location.pickup.value, const LatLng(15.36, 44.19));
    expect(location.focusedRouteField.value, 1);
    expect(location.fromController.text, isNotEmpty);
    expect(location.shortcutPlaces.map((p) => p.title).toList(),
        ['مكتب أحمد', 'المنزل']);
    expect(find.widgetWithText(ActionChip, 'فارغ'), findsNothing);
    expect(find.widgetWithText(ActionChip, 'عنوان بلا اسم'), findsNothing);
    await tester.tap(find.widgetWithText(ActionChip, 'المنزل'));
    await tester.pumpAndSettle();
    expect(location.destination.value, const LatLng(15.4, 44.2));
    expect(location.pickup.value, const LatLng(15.36, 44.19));
  });
  for (final field in [0, 1]) {
    testWidgets(
        'favourites picker fills captured field $field and returns to route screen',
        (tester) async {
      await open(tester);
      await tester.tap(find.byType(TextFormField).at(field));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('route-favourites-picker')));
      await tester.pumpAndSettle();
      expect(find.text('الأماكن المفضلة'), findsOneWidget);
      await tester.tap(find.text('مكتب أحمد'));
      await tester.pumpAndSettle();
      expect(Get.currentRoute, '/route-test');
      expect(field == 0 ? location.pickup.value : location.destination.value,
          const LatLng(15.5, 44.3));
      expect(location.focusedRouteField.value, isNull);
    });
  }
  testWidgets(
      'favourites header is disabled without a focused field; save supports unnamed',
      (tester) async {
    await open(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('route-favourites-picker')))
            .onPressed,
        isNull);
    location.destination.value = const LatLng(15.6, 44.4);
    location.toController.text = 'عنوان الوجهة';
    Get.to<void>(() => const Scaffold(
        body: Center(child: SaveDestinationButton(iconOnly: true))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-destination-favourite')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بدون اسم').last);
    await tester.pumpAndSettle();
    await expectLater(find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/save-destination-favourite.png'));
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(api.saved?['kind'], 'unnamed');
    expect(api.saved?['label'], '');
    expect(api.saved?['latitude'], 15.6);
  });
}
