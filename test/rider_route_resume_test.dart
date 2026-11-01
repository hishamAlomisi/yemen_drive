import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:yemen_drive/core/config/app_environment.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/auth/routes/auth_routes.dart';
import 'package:yemen_drive/features/ride/booking/controllers/booking_controller.dart';
import 'package:yemen_drive/features/ride/controllers/ride_controller.dart';
import 'package:yemen_drive/features/ride/home/repositories/service_kind_repository.dart';
import 'package:yemen_drive/features/ride/location_selection/controllers/location_selection_controller.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/location_search_repository.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/route_repository.dart';
import 'package:yemen_drive/features/ride/models/ride_models.dart';
import 'package:yemen_drive/features/ride/models/service_kind_models.dart';
import 'package:yemen_drive/features/ride/negotiation/repositories/ride_negotiation_repository.dart';
import 'package:yemen_drive/features/ride/ride_routes.dart';
import 'package:yemen_drive/features/ride/vehicle_selection/repositories/service_catalog_repository.dart';
import 'package:yemen_drive/features/ride/views/home_notifications_location_views.dart';

class _Storage extends SecureStorageService {
  @override
  Future<void> saveTokens(
      {required String accessToken, required String refreshToken}) async {}
  @override
  Future<void> saveAuthenticatedUserId(int userId) async {}
  @override
  Future<void> setRememberMe(bool remember) async {}
}

class _Api extends ApiClient {
  _Api() : super(_Storage());
  @override
  Future<ApiResult<T>> execute<T>(
          {required String model,
          required String operation,
          Object? data,
          T Function(Object?)? parse}) async =>
      ApiSuccess<T>(
          (model == 'SavedPlaceModel' ? <Object>[] : <String, Object?>{}) as T);
}

class _Kinds implements ServiceKindRepository {
  _Kinds(this.session);
  final AuthSessionService session;
  int reads = 0;
  Completer<List<RideHomeService>>? pending;
  @override
  Future<List<RideHomeService>> getServices() async {
    reads++;
    if (!session.isAuthenticated.value) throw const FormatException('guest');
    return pending?.future ??
        const [
          RideHomeService(
              id: 1, code: 'transport', name: 'مشوار', isDefault: true),
          RideHomeService(id: 2, code: 'delivery', name: 'توصيل'),
        ];
  }
}

class _Catalog implements ServiceCatalogRepository {
  _Catalog(this.session);
  final AuthSessionService session;
  final reads = <int>[];
  @override
  Future<List<RideVehicle>> getServices({required int serviceKindId}) async {
    reads.add(serviceKindId);
    if (!session.isAuthenticated.value) return [];
    return [
      RideVehicle(
          id: '$serviceKindId',
          name: 'خدمة',
          type: RideVehicleType.car,
          serviceKindId: serviceKindId,
          serviceCatalogItemId: serviceKindId * 10,
          arrivalMinutes: 0,
          price: 0,
          rating: 0,
          seats: 4,
          description: '')
    ];
  }
}

class _Repository implements RideNegotiationRepository {
  Completer<Map<String, Object?>?>? rating;
  @override
  Future<Map<String, Object?>?> getPendingRating() async => rating?.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ride extends RideController {
  _Ride(super.repository, super.session, super.catalog, super.kinds);
  @override
  void onReady() {}
}

class _Routes implements RouteRepository {
  @override
  Future<DrivingRoute> getDrivingRoute(
          {required LatLng origin,
          required LatLng destination,
          bool includeSteps = false}) async =>
      DrivingRoute(
          points: [origin, destination],
          distanceMeters: 3000,
          durationSeconds: 480);
}

const _pickup = LocationSearchResult(
    title: 'حدة', formattedAddress: 'شارع حدة', location: LatLng(15.36, 44.19));
const _destination = LocationSearchResult(
    title: 'التحرير',
    formattedAddress: 'ميدان التحرير',
    location: LatLng(15.38, 44.21));

class _Places implements LocationSearchRepository {
  final queries = <String>[];
  @override
  Future<List<LocationSearchResult>> search(String query) async {
    queries.add(query);
    return [query == 'حدة' ? _pickup : _destination];
  }

  @override
  Future<LocationSearchResult?> reverseGeocode(LatLng point) async => null;
}

void main() {
  late AuthSessionService session;
  late _Kinds kinds;
  late _Catalog catalog;
  late _Repository repository;
  late RideController ride;
  late LocationController location;
  late BookingController booking;
  late _Places places;

  setUpAll(() async {
    AppEnvironment.configure(baseUrl: 'https://resume.invalid/api');
    final directory = Directory('build/resume-test-storage')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.absolute.path);
    await GetStorage.init();
  });
  setUp(() {
    Get.testMode = true;
    final api = Get.put<ApiClient>(_Api());
    session = Get.put(AuthSessionService(_Storage(), api));
    kinds = _Kinds(session);
    catalog = _Catalog(session);
    repository = _Repository();
    ride = Get.put<RideController>(_Ride(repository, session, catalog, kinds));
    places = _Places();
    location = Get.put(LocationController(_Routes(), places, api, session));
    booking = Get.put(BookingController(ride, location));
  });
  tearDown(Get.reset);

  Future<void> signIn(WidgetTester tester) async {
    await session.activate(
        accessToken: 'test', refreshToken: 'test', remember: false, userId: 1);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'sign-in preserves the awaited pickup/destination flow and enters fare review',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: RideRoutes.homeTransport,
      getPages: [
        GetPage(
            name: RideRoutes.homeTransport,
            page: () => const Scaffold(body: Text('home'))),
        GetPage(
            name: RideRoutes.locationSearch,
            page: () => const LocationSearchPage()),
        GetPage(
            name: AuthRoutes.signIn,
            page: () => const Scaffold(body: Text('sign in'))),
        GetPage(
            name: RideRoutes.negotiationQuote,
            page: () => const Scaffold(body: Text('fare review'))),
      ],
    ));
    final flow = booking.continueFromHome(editField: 0);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'حدة');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, AuthRoutes.signIn);
    expect(booking.isOpeningHomeBooking.value, isTrue);
    await signIn(tester);
    session.continueAfterAuthentication();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.locationSearch);
    expect(places.queries, ['حدة']);
    await location.selectSearchResult(_pickup);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.locationSearch);
    expect(location.activeField.value, 1);
    await location.selectSearchResult(_destination);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.negotiationQuote);
    expect(ride.selectedServiceKindId.value, 1);
    expect(ride.vehicles.single.serviceKindId, 1);
    expect(location.hasDrivingRoute, isTrue);
    Get.back<void>();
    await tester.pumpAndSettle();
    await flow;
    expect(booking.isOpeningHomeBooking.value, isFalse);
  });

  testWidgets(
      'login reloads a previously failed guest catalog without a manual service choice',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await signIn(tester);
    expect(kinds.reads, greaterThanOrEqualTo(2));
    expect(ride.selectedServiceKindId.value, 1);
    expect(ride.homeServiceIndex.value, 0);
    expect(ride.vehicles.single.serviceCatalogItemId, 10);
  });

  testWidgets(
      'late default loading preserves a manual choice and fills its missing catalog',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    ride.selectedServiceKindId.value = 2;
    ride.homeServiceIndex.value = 1;
    await signIn(tester);
    expect(ride.selectedServiceKindId.value, 2);
    expect(ride.vehicles.single.serviceKindId, 2);
  });

  testWidgets(
      'default selection deferred by rating check recovers when the check completes',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    session.isAuthenticated.value = true;
    repository.rating = Completer();
    final check = ride.ensureNoPendingRating();
    await tester.pumpAndSettle();
    expect(ride.checkingPendingRating.value, isTrue);
    expect(ride.selectedServiceKindId.value, isNull);
    repository.rating!.complete(null);
    await check;
    await tester.pumpAndSettle();
    expect(ride.selectedServiceKindId.value, 1);
    expect(ride.vehicles.single.serviceKindId, 1);
  });
}
