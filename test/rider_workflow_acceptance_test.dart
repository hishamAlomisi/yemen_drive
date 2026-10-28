import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/realtime/tracking_hub_service.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/services/offer_arrival_notifier.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/booking/views/ride_search_view.dart';
import 'package:yemen_drive/features/ride/controllers/payment_controller.dart';
import 'package:yemen_drive/features/ride/controllers/ride_controller.dart';
import 'package:yemen_drive/features/ride/location_selection/controllers/location_selection_controller.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/location_search_repository.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/route_repository.dart';
import 'package:yemen_drive/features/ride/models/ride_models.dart';
import 'package:yemen_drive/features/ride/negotiation/repositories/ride_negotiation_repository.dart';
import 'package:yemen_drive/features/ride/ride_routes.dart';
import 'package:yemen_drive/features/ride/views/trip_communication_payment_views.dart';

class _MemoryStorage implements GetStorage {
  final values = <String, Object?>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async => values[key] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements RideNegotiationRepository {
  int status = 5;
  bool requiresRating = false;
  bool ratingReadFails = false;
  int bookingAttempts = 0;
  int cancellationAttempts = 0;
  List<DriverOffer> offers = [];
  List<RideRequestViewer> recipients = [];
  Map<String, Object?> get detail => {
        'ride': {
          'id': 7,
          'status': status,
          'customerPrice': 1000,
          'pickupLatitude': 15.3,
          'pickupLongitude': 44.1,
          'destinationLatitude': 15.4,
          'destinationLongitude': 44.2,
          'customerPaymentEnabled': false,
        },
        'requiresRating': requiresRating,
        'offers': offers.map((offer) => {'offer': offer}).toList(),
        'payments': <Object?>[],
      };
  @override
  Future<Map<String, Object?>> getRideDetail(String requestId) async => detail;
  @override
  Future<Map<String, Object?>?> findLatestOpenRide() async =>
      status == 6 || status == 7
          ? null
          : Map<String, Object?>.from(detail['ride']! as Map);
  @override
  Future<Map<String, Object?>?> getPendingRating() async {
    if (ratingReadFails) throw const FormatException('offline');
    return requiresRating
        ? {'rideId': 7, 'driverId': 2, 'driverName': 'أحمد'}
        : null;
  }

  @override
  Future<List<RideRequestViewer>> getRequestRecipients(
          String requestId) async =>
      recipients;
  @override
  Future<List<RideRequestViewer>> getRequestViewers(String requestId) async =>
      [];
  @override
  DriverOffer? mapRealtimeOffer(Map<String, Object?> event) =>
      event['offer'] as DriverOffer?;
  @override
  Future<RideSearchStartResult> createRequest(RideRequestDraft draft) async {
    bookingAttempts++;
    return const RideSearchStartResult(rideId: '99', recipientCount: 0);
  }

  @override
  Future<void> requestCancellation(String requestId, String reason) async {
    cancellationAttempts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api extends ApiClient {
  _Api(this.repository) : super(SecureStorageService());
  final _Repository repository;
  bool failRating = false;
  Map<String, Object?>? cancellation;
  final decisions = <String>[];
  @override
  Future<ApiResult<T>> execute<T>(
      {required String model,
      required String operation,
      Object? data,
      T Function(Object?)? parse}) async {
    Object? result = <String, Object?>{};
    if (model == 'RideModel') result = repository.detail;
    if (model == 'DriverRatingModel') {
      if (failRating)
        return const ApiFailure(
            ApiProblemDetails(title: 'offline', status: 503));
      repository.requiresRating = false;
    }
    if (model == 'RideCancellationRequestModel') {
      if (operation != 'get') {
        decisions.add(operation);
        cancellation?['canDecide'] = false;
        if (operation == 'accept') repository.status = 7;
      }
      result = cancellation;
    }
    return ApiSuccess<T>(result as T);
  }
}

class _Hub extends TrackingHubService {
  _Hub() : super(SecureStorageService());
  final messages = StreamController<TrackingHubEvent>.broadcast();
  final reconnects = StreamController<void>.broadcast();
  @override
  Stream<TrackingHubEvent> get events => messages.stream;
  @override
  Stream<void> get connectionRestored => reconnects.stream;
  @override
  Future<void> setRideSubscriptions(Iterable<int> rideIds) async {}
  @override
  Future<void> clearNearbyDriverSubscription() async {}
  @override
  Future<void> setUserEventListening(Object owner, bool listen) async {}
  void send(String event, [Map<String, Object?> values = const {}]) =>
      messages.add(TrackingHubEvent(event, {'rideId': 7, ...values}));
}

class _Routes implements RouteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Places implements LocationSearchRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Location extends LocationController {
  _Location(ApiClient api, AuthSessionService session)
      : super(_Routes(), _Places(), api, session);
  @override
  // Native location and maps are unrelated to the server workflow under test.
  // ignore: must_call_super
  void onInit() {}
}

class _Ride extends RideController {
  _Ride(RideNegotiationRepository repository, AuthSessionService session,
      OfferArrivalNotifier notifier)
      : super(repository, session, null, null, null, notifier);
  @override
  void onReady() {}
  @override
  void startRealTracking() {}
}

Widget _host() => GetMaterialApp(
      home: const Scaffold(body: Text('home')),
      getPages: [
        GetPage(
            name: RideRoutes.driverLocation,
            page: () => const Scaffold(body: DriverCancellationDecisionCard())),
        GetPage(
            name: RideRoutes.negotiationQuote,
            page: () => const Scaffold(body: SearchRequestRecipients())),
        GetPage(name: RideRoutes.review, page: () => const RideReviewPage()),
        GetPage(
            name: RideRoutes.rideThanks,
            page: () => const Scaffold(body: Text('rated'))),
        GetPage(
            name: RideRoutes.requestThanks,
            page: () => const Scaffold(body: Text('cancelled'))),
      ],
    );

void main() {
  late _Repository repository;
  late _Api api;
  late _Ride ride;
  late _Hub hub;
  late PaymentController payment;
  late _MemoryStorage soundStorage;
  int sounds = 0;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final directory = Directory('build/workflow-test-storage')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.absolute.path);
    await GetStorage.init();
  });
  void initialize() {
    Get.testMode = true;
    repository = _Repository();
    api = Get.put<ApiClient>(_Api(repository), permanent: true) as _Api;
    hub = Get.put<TrackingHubService>(_Hub(), permanent: true) as _Hub;
    final session = AuthSessionService(SecureStorageService(), api);
    session.isAuthenticated.value = true;
    session.currentUserId.value = 1;
    Get.put<LocationController>(_Location(api, session), permanent: true);
    soundStorage = _MemoryStorage();
    sounds = 0;
    ride = Get.put<RideController>(
        _Ride(
          repository,
          session,
          OfferArrivalNotifier(
              storage: soundStorage,
              play: () async {
                sounds++;
              }),
        ),
        permanent: true) as _Ride;
    payment = Get.put(PaymentController(), permanent: true);
  }

  void workflowTest(
      String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      // Register stream listeners inside the widget test's fake-async zone.
      // Otherwise event callbacks await real-zone microtasks that pump cannot
      // drain, and assertions race the REST snapshot following the event.
      initialize();
      try {
        await body(tester);
      } finally {
        // Let any queued notices finish before disposing their overlay.
        for (var notice = 0; notice < 3; notice++) {
          await tester.pump(const Duration(seconds: 4));
          await tester.pumpAndSettle();
        }
        Get.delete<RideController>(force: true);
        Get.delete<PaymentController>(force: true);
        Get.delete<LocationController>(force: true);
        await tester.pumpWidget(const SizedBox.shrink());
        Get.reset();
        await hub.messages.close();
        await hub.reconnects.close();
      }
    });
  }

  workflowTest(
      'completion immediately opens a mandatory review without a payment button',
      (tester) async {
    await tester.pumpWidget(_host());
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    repository.status = 6;
    repository.requiresRating = true;
    hub.send('rideStatusUpdated', {'rideStatus': 6});
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.review);
    expect(find.text('تخطي الآن'), findsNothing);
    expect(tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isFalse);
    ride.prepareNewRide();
    await ride.requestRide();
    expect(ride.currentRideId, '7');
    expect(repository.bookingAttempts, 0);
    api.failRating = true;
    payment.setRating(4);
    await payment.submitReview();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(ride.pendingRatingRideId.value, '7');
    expect(Get.currentRoute, RideRoutes.review);
    api.failRating = false;
    await payment.submitReview();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.rideThanks);
    expect(ride.pendingRatingRideId.value, isNull);
    hub.send('rideStatusUpdated', {'rideStatus': 6});
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.rideThanks);
    ride.prepareNewRide();
    expect(ride.bookingLocked, isFalse);
  });

  workflowTest(
      'startup restores unsubmitted review from server and offline never permits booking',
      (tester) async {
    await tester.pumpWidget(_host());
    repository.status = 6;
    repository.requiresRating = true;
    await ride.restoreOpenRideOnLaunch();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.review);
    expect(ride.pendingRatingRideId.value, '7');
    repository.ratingReadFails = true;
    expect(await ride.ensureNoPendingRating(), isFalse);
    ride.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.review);
    expect(ride.bookingLocked, isTrue);
  });

  workflowTest(
      'arrival is separate; driver cancellation rejects without changing trip then accepts',
      (tester) async {
    await tester.pumpWidget(_host());
    repository.status = 9;
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    expect(ride.activeRideStatus.value, '9');
    expect(ride.activeRideStatus.value, isNot('5'));
    repository.status = 5;
    api.cancellation = {
      'id': 21,
      'status': 5,
      'requestedByDriver': true,
      'canDecide': true,
      'reason': 'عطل مفاجئ'
    };
    hub.send('rideCancellationUpdated');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reject-driver-cancellation')),
        findsOneWidget);
    await ride.decideDriverCancellation(accept: false);
    await tester.pumpAndSettle();
    expect(ride.activeRideStatus.value, '5');
    expect(ride.currentRideId, '7');
    expect(api.decisions, ['reject']);
    api.cancellation = {
      'id': 22,
      'status': 5,
      'requestedByDriver': true,
      'canDecide': true
    };
    // The current API also invalidates pending decisions by rebroadcasting
    // the unchanged trip status; both transports must refresh the request.
    hub.send('rideStatusUpdated', {'rideStatus': 5});
    await tester.pumpAndSettle();
    expect(ride.driverCancellationRequest.value?['id'], 22);
    hub.reconnects.add(null);
    await tester.pumpAndSettle();
    await ride.decideDriverCancellation(accept: true);
    await tester.pumpAndSettle();
    expect(ride.currentRideId, isNull);
    expect(Get.currentRoute, RideRoutes.requestThanks);
    expect(api.decisions, ['reject', 'accept']);
  });

  workflowTest('rider cancellation retains the live trip until server approval',
      (tester) async {
    await tester.pumpWidget(_host());
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    await ride.cancelActiveRide('تغيير الخطة');
    await tester.pumpAndSettle();
    expect(repository.cancellationAttempts, 1);
    expect(ride.currentRideId, '7');
    expect(ride.isDriverAssigned.value, isTrue);
    repository.status = 7;
    hub.send('rideStatusUpdated', {'rideStatus': 7});
    await tester.pumpAndSettle();
    expect(ride.currentRideId, isNull);
  });

  workflowTest(
      'only persisted recipients render and only distinct live offers sound across replay and reconnect',
      (tester) async {
    await tester.pumpWidget(_host());
    repository.status = 1;
    repository.recipients = [
      const RideRequestViewer(driverId: '2', name: 'أحمد')
    ];
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('request-recipient-2')), findsOneWidget);
    expect(sounds, 0);
    repository.recipients = [
      ...repository.recipients,
      const RideRequestViewer(driverId: '3', name: 'علي')
    ];
    hub.send('rideSearchRecipientsUpdated');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('request-recipient-3')), findsOneWidget);
    final offer = DriverOffer(
        id: '11',
        driverName: 'أحمد',
        vehicleSummary: '',
        price: 1000,
        rating: 4,
        etaMinutes: 2,
        expiresAt: DateTime.now().add(const Duration(minutes: 1)));
    hub.send('offerReceived', {'offer': offer});
    hub.send('offerReceived', {'offer': offer});
    await tester.pumpAndSettle();
    expect(ride.driverOffers, hasLength(1));
    expect(sounds, 1);
    repository.offers = [offer];
    hub.reconnects.add(null);
    await tester.pumpAndSettle();
    expect(sounds, 1);
    final nextOffer = DriverOffer(
        id: '12',
        driverName: 'علي',
        vehicleSummary: '',
        price: 1000,
        rating: 4,
        etaMinutes: 2,
        expiresAt: DateTime.now().add(const Duration(minutes: 1)));
    hub.send('offerReceived', {'offer': nextOffer});
    await tester.pumpAndSettle();
    expect(sounds, 2);
    await OfferArrivalNotifier(
        storage: soundStorage,
        play: () async {
          sounds++;
        }).announce('7', '11');
    expect(sounds, 2,
        reason:
            'A new notifier instance must preserve offer replay de-duplication.');
    final expiredOffer = DriverOffer(
        id: '13',
        driverName: 'عرض منتهٍ',
        vehicleSummary: '',
        price: 1000,
        rating: 4,
        etaMinutes: 2,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)));
    hub.send('offerReceived', {'offer': expiredOffer});
    await tester.pumpAndSettle();
    expect(ride.driverOffers.map((item) => item.id), ['11', '12']);
    expect(sounds, 2);
    hub.send('rideUnavailable');
    hub.send('offerReceived', {'offer': nextOffer});
    await tester.pumpAndSettle();
    expect(ride.driverOffers, isEmpty);
    expect(sounds, 2,
        reason: 'Closed searches must not announce late offer deliveries.');
  });
}
