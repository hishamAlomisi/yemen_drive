import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as maps;
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/controllers/payment_controller.dart';
import 'package:yemen_drive/features/ride/controllers/ride_controller.dart';
import 'package:yemen_drive/features/ride/location_selection/controllers/location_selection_controller.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/location_search_repository.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/route_repository.dart';
import 'package:yemen_drive/features/ride/negotiation/repositories/ride_negotiation_repository.dart';
import 'package:yemen_drive/features/ride/ride_routes.dart';
import 'package:yemen_drive/shared/widgets/ride_route_change_panel.dart';
import 'package:yemen_drive/shared/widgets/ride_route_destination_picker.dart';

Map<String, Object?> detail({int version = 0}) => {
      'ride': <String, Object?>{
        'id': 7,
        'status': 5,
        'routeVersion': version,
        'pickupLatitude': 15.30,
        'pickupLongitude': 44.10,
        'destinationLatitude': version == 0 ? 15.4 : 15.5,
        'destinationLongitude': version == 0 ? 44.2 : 44.3,
        'destinationDisplayName':
            version == 0 ? 'الوجهة الأصلية' : 'الوجهة المعتمدة',
        'customerPrice': version == 0 ? 1000 : 1500,
        'totalAmount': version == 0 ? 1100 : 1700,
        'waitingFee': version == 0 ? 0 : 100,
        'serviceFee': 100,
        'routeChangeFees': version == 0 ? 0 : 100,
        'routeCompletedFare': version == 0 ? 0 : 350,
      },
      'payments': <Object?>[],
    };

class _Api extends ApiClient {
  _Api() : super(SecureStorageService());
  Map<String, Object?> state = detail();
  @override
  Future<ApiResult<T>> execute<T>({
    required String model,
    required String operation,
    Object? data,
    T Function(Object?)? parse,
  }) async =>
      ApiSuccess<T>((model == 'RideModel' ? state : <String, Object?>{}) as T);
}

class _Repository implements RideNegotiationRepository {
  Map<String, Object?> state = detail();
  @override
  Future<Map<String, Object?>> getRideDetail(String requestId) async => state;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Routes implements RouteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Places implements LocationSearchRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ride extends RideController {
  _Ride(super.repository, super.session);
  @override
  // Tests explicitly restore the ride and skip network subscriptions.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onReady() {}
  @override
  void startRealTracking() {}
}

class _Location extends LocationController {
  _Location(ApiClient api, AuthSessionService session)
      : super(_Routes(), _Places(), api, session);
  @override
  // Tests supply the server snapshot without native marker assets.
  // ignore: must_call_super
  void onInit() {}
}

class _MapPlatform extends maps.GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    ValueChanged<int> onPlatformViewCreated, {
    required maps.MapWidgetConfiguration widgetConfiguration,
    maps.MapConfiguration mapConfiguration = const maps.MapConfiguration(),
    maps.MapObjects mapObjects = const maps.MapObjects(),
  }) =>
      const SizedBox.expand();
}

void main() {
  tearDown(Get.reset);

  testWidgets(
      'accepted snapshot updates destination/fare and rejects older route versions',
      (tester) async {
    Get.testMode = true;
    final api = Get.put<ApiClient>(_Api()) as _Api;
    final session = AuthSessionService(SecureStorageService(), api);
    final repository = _Repository();
    final location = Get.put<LocationController>(_Location(api, session));
    final ride = Get.put<RideController>(_Ride(repository, session));
    await tester.pumpWidget(
      GetMaterialApp(
        home: const SizedBox(),
        getPages: [
          GetPage(
              name: RideRoutes.driverLocation, page: () => const SizedBox()),
        ],
      ),
    );
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    expect(location.toController.text, 'الوجهة الأصلية');
    ride.trackingRoutePoints
        .assignAll(const [LatLng(15.3, 44.1), LatLng(15.4, 44.2)]);
    ride.trackingNextStepInstruction.value = 'تعليمات الوجهة القديمة';
    repository.state = detail(version: 1);
    await ride.refreshActiveRide(requireSuccess: true);
    expect(location.destination.value, const LatLng(15.5, 44.3));
    expect(location.toController.text, 'الوجهة المعتمدة');
    expect(ride.currentDraft.value!.destinationAddressName, 'الوجهة المعتمدة');
    expect(ride.offeredPrice.value, 1500);
    expect(ride.trackingRoutePoints, isEmpty);
    expect(location.routePoints, isEmpty);
    expect(ride.trackingNextStepInstruction.value, isEmpty);
    repository.state = detail();
    await ride.refreshActiveRide(requireSuccess: true);
    expect(location.destination.value, const LatLng(15.5, 44.3));
    expect(ride.offeredPrice.value, 1500);
    api.state = detail(version: 1);
    final payment = Get.put(PaymentController());
    await payment.loadPaymentSummary();
    expect(payment.baseFare.value, 1500);
    expect(payment.routeChangeFees.value, 100);
    expect(payment.routeCompletedFare.value, 350);
    expect(payment.totalDue.value, 1700);
    repository.state = {};
    await expectLater(
        ride.refreshActiveRide(requireSuccess: true), throwsFormatException);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'destination search selects a labeled map point without touching active ride',
      (tester) async {
    final previous = maps.GoogleMapsFlutterPlatform.instance;
    maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
    addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = previous);
    RideRouteDestination? selected;
    final queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selected = await Navigator.push<RideRouteDestination>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RideRouteDestinationPicker(
                      initialTarget: const LatLng(15.3, 44.1),
                      search: (query) async {
                        queries.add(query);
                        return const [
                          RideRouteDestination(
                              latitude: 15.5,
                              longitude: 44.3,
                              label: 'مطار صنعاء')
                        ];
                      },
                      reverseGeocode: (_) async => null,
                    ),
                  ),
                );
              },
              child: const Text('اختيار'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('اختيار'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).first, 'مطار');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(queries, ['مطار']);
    await tester.tap(find.text('مطار صنعاء'));
    await tester.pump();
    await tester.tap(find.text('عرض فاتورة هذه الوجهة'));
    await tester.pumpAndSettle();
    expect(selected?.latitude, 15.5);
    expect(selected?.longitude, 44.3);
    expect(selected?.label, 'مطار صنعاء');
    await tester.pumpWidget(const SizedBox());
  });
}
