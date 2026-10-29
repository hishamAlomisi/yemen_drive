import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as maps;
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/config/app_environment.dart';
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
import 'package:yemen_drive/features/ride/models/wallet_ride_payment.dart';
import 'package:yemen_drive/features/account/wallet/models/wallet_models.dart';
import 'package:yemen_drive/features/ride/negotiation/repositories/ride_negotiation_repository.dart';
import 'package:yemen_drive/features/ride/ride_routes.dart';
import 'package:yemen_drive/features/ride/views/trip_communication_payment_views.dart';
import 'package:yemen_drive/shared/widgets/app_button.dart';

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
  bool customerPaymentEnabled = false;
  String paymentMethodCode = 'cash';
  bool paymentRequiredBeforeStart = false;
  bool paymentCompleted = false;
  Completer<Map<String, Object?>>? pendingDetail;
  int detailReads = 0;
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
          'customerPaymentEnabled': customerPaymentEnabled,
          'paymentMethodCode': paymentMethodCode,
          'paymentRequiredBeforeStart': paymentRequiredBeforeStart,
        },
        'paymentCompleted': paymentCompleted,
        'requiresRating': requiresRating,
        'offers': offers.map((offer) => {'offer': offer}).toList(),
        'payments': <Object?>[],
      };
  @override
  Future<Map<String, Object?>> getRideDetail(String requestId) async {
    detailReads++;
    return pendingDetail?.future ?? detail;
  }

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
  Future<void> acceptOffer(String requestId, String offerId) async {
    status = 3;
    paymentRequiredBeforeStart = paymentMethodCode != 'cash';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api extends ApiClient {
  _Api(this.repository) : super(SecureStorageService()) {
    dio = Dio(BaseOptions(baseUrl: 'https://workflow.invalid/api/'))
      ..httpClientAdapter = walletAdapter;
  }
  final _Repository repository;
  final walletAdapter = _WalletAdapter();
  final cashSwitches = <Object?>[];
  bool failCashSwitch = false;
  int cashRequestAdds = 0;
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
    if (model == 'RideModel') {
      if (operation == 'update') {
        cashSwitches.add(data);
        if (failCashSwitch) {
          return const ApiFailure(
              ApiProblemDetails(title: 'تعذر اعتماد النقدي الآن', status: 409));
        }
        repository.paymentMethodCode = 'cash';
        repository.paymentRequiredBeforeStart = false;
      }
      result = repository.detail;
    }
    if (model == 'CashPaymentRequestModel' && operation == 'add') {
      cashRequestAdds++;
    }
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

class _WalletAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Map<String, Object?>? current;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'data': current}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _walletOperation(String status) => {
      'id': 88,
      'rideId': 7,
      'paymentMethodId': 8,
      'providerCode': 'Jaib',
      'providerName': 'جيب',
      'status': status,
      'nextAction': status == 'AwaitingCode' ? 'OneTimePassword' : 'None',
      'amount': 1000,
      'currency': 'YER',
      'mobile': '771234567',
      'customerIsProviderVerified': false,
    };

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

Widget _host({bool liveRidePage = false, bool livePaymentPage = false}) =>
    GetMaterialApp(
      home: const Scaffold(body: Text('home')),
      getPages: [
        GetPage(
            name: RideRoutes.driverLocation,
            page: () => liveRidePage
                ? const DriverLocationPage()
                : const Scaffold(body: DriverCancellationDecisionCard())),
        GetPage(
            name: RideRoutes.negotiationQuote,
            page: () => const Scaffold(body: SearchRequestRecipients())),
        GetPage(name: RideRoutes.review, page: () => const RideReviewPage()),
        GetPage(
            name: RideRoutes.payment,
            page: () => livePaymentPage
                ? const RidePaymentPage()
                : const Scaffold(body: Text('wallet payment'))),
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
      'accepted noncash offer requires payment and only a confirmed server cash switch unlocks the trip',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository.status = 1;
    repository.paymentMethodCode = 'JAIB';
    await tester.pumpWidget(_host(livePaymentPage: true));
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    await ride.acceptOffer(const DriverOffer(
        id: '11',
        driverName: 'أحمد',
        vehicleSummary: '',
        price: 1000,
        rating: 4,
        etaMinutes: 2));
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.payment);
    expect(ride.activePaymentMethodCode.value, 'JAIB');
    expect(ride.mandatoryPaymentPending, isTrue);
    expect(tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.payment);
    await ride.openNotificationPayload(
        {'action': 'open_ride_chat', 'rideId': '7'});
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.payment);
    expect(
        api.walletAdapter.requests.every((request) => request.method == 'GET'),
        isTrue,
        reason: 'Accepting the offer must not submit a withdrawal.');

    payment.selectMethod('cash');
    await tester.pump();
    expect(find.text('اعتماد الدفع النقدي ومتابعة الرحلة'), findsOneWidget);
    expect(ride.mandatoryPaymentPending, isTrue);
    expect(api.cashSwitches, isEmpty);
    api.failCashSwitch = true;
    await payment.pay();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.payment);
    expect(ride.mandatoryPaymentPending, isTrue);
    expect(find.text('تعذر اعتماد النقدي الآن'), findsOneWidget);
    api.failCashSwitch = false;
    await payment.pay();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.driverLocation);
    expect(ride.mandatoryPaymentPending, isFalse);
    expect(api.cashSwitches.last, {'id': '7', 'paymentMethodCode': 'cash'});
    expect(api.cashRequestAdds, 0,
        reason: 'Choosing future cash collection is not a receipt request.');
    expect(payment.paymentCompleted.value, isFalse);
  });

  workflowTest('cash offer acceptance goes directly to the active trip',
      (tester) async {
    repository.status = 1;
    await tester.pumpWidget(_host());
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    await ride.acceptOffer(const DriverOffer(
        id: '11',
        driverName: 'أحمد',
        vehicleSummary: '',
        price: 1000,
        rating: 4,
        etaMinutes: 2));
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.driverLocation);
    expect(ride.mandatoryPaymentPending, isFalse);
    expect(api.cashSwitches, isEmpty);
    expect(api.cashRequestAdds, 0);
  });

  workflowTest('a confirmed cash choice recovered over realtime exits the required payment step',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository.status = 3;
    repository.paymentMethodCode = 'wallet';
    repository.paymentRequiredBeforeStart = true;
    await tester.pumpWidget(_host(livePaymentPage: true));
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.payment);
    repository.paymentMethodCode = 'cash';
    repository.paymentRequiredBeforeStart = false;
    hub.send('rideStatusUpdated', {
      'rideStatus': 3,
      'paymentMethodCode': 'cash',
      'paymentRequiredBeforeStart': false,
    });
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.driverLocation);
    expect(ride.mandatoryPaymentPending, isFalse);
    expect(api.cashRequestAdds, 0);
    expect(payment.paymentCompleted.value, isFalse);
  });

  for (final recovery in ['startup', 'reconnect']) {
    workflowTest(
        '$recovery restores mandatory payment and its existing provider operation',
        (tester) async {
      tester.view.physicalSize = const Size(480, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      repository.status = recovery == 'startup' ? 3 : 1;
      repository.paymentMethodCode = 'JAIB';
      repository.paymentRequiredBeforeStart = recovery == 'startup';
      api.walletAdapter.current = _walletOperation('ReviewRequired');
      await tester.pumpWidget(_host(livePaymentPage: true));
      if (recovery == 'startup') {
        await ride.restoreOpenRideOnLaunch();
      } else {
        await ride.resumeOpenRide('7');
        await tester.pumpAndSettle();
        repository.status = 3;
        repository.paymentRequiredBeforeStart = true;
        hub.reconnects.add(null);
      }
      await tester.pumpAndSettle();
      expect(Get.currentRoute, RideRoutes.payment);
      expect(ride.mandatoryPaymentPending, isTrue);
      expect(payment.externalPayment.payment.value?.id, '88');
      expect(find.text('بيانات الحساب غير متاحة من مزود الدفع حالياً.'),
          findsOneWidget);
      expect(payment.paymentOptionsLocked, isTrue);
      payment.selectMethod('cash');
      await payment.confirmCashSelection();
      expect(api.cashSwitches, isEmpty);
      expect(
          api.walletAdapter.requests
              .every((request) => request.method == 'GET'),
          isTrue);
      expect(tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
          isFalse);
    });
  }

  workflowTest(
      'pretrip wallet receipt continues to tracking and stays paid after restoration',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository.status = 3;
    repository.paymentMethodCode = 'JAIB';
    repository.paymentRequiredBeforeStart = true;
    await tester.pumpWidget(_host(livePaymentPage: true));
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    repository.paymentRequiredBeforeStart = false;
    repository.paymentCompleted = true;
    api.walletAdapter.current = _walletOperation('Succeeded');
    final refreshed = payment.loadPaymentSummary();
    await tester.pumpAndSettle();
    await refreshed;
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.payment);
    expect(ride.mandatoryPaymentPending, isFalse);
    await tester.tap(find.byKey(const ValueKey('wallet-receipt-done')));
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.driverLocation);
    expect(ride.pendingRatingRideId.value, isNull);
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.driverLocation);
    expect(ride.activeRidePaymentCompleted.value, isTrue);
    expect(
        api.walletAdapter.requests.every((request) => request.method == 'GET'),
        isTrue);
  });

  workflowTest(
      'same-status payment event enables the live trip footer before its REST refresh finishes',
      (tester) async {
    final previousMaps = maps.GoogleMapsFlutterPlatform.instance;
    maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
    addTearDown(() => maps.GoogleMapsFlutterPlatform.instance = previousMaps);
    ride.hasShownTripSharePrompt = true;
    await tester.pumpWidget(_host(liveRidePage: true));
    await ride.resumeOpenRide('7');
    // The native map is deliberately absent; its loading animation need not
    // settle to exercise the actual trip footer and its navigation action.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    try {
      expect(ride.activeRideStatus.value, '5');
      expect(
          tester
              .widget<AppButton>(
                  find.widgetWithText(AppButton, 'بانتظار اكتمال الرحلة'))
              .onPressed,
          isNull);

      hub.send('rideStatusUpdated', {
        'rideId': 99,
        'rideStatus': 5,
        'customerPaymentEnabled': true,
      });
      await tester.pump();
      expect(ride.customerPaymentEnabled.value, isFalse);

      repository.customerPaymentEnabled = true;
      final pending = Completer<Map<String, Object?>>();
      repository.pendingDetail = pending;
      final readsBeforeEvent = repository.detailReads;
      hub.send('rideStatusUpdated', {
        'rideStatus': 5,
        'customerPaymentEnabled': true,
      });
      await tester.pump();
      expect(repository.detailReads, readsBeforeEvent + 1);
      expect(pending.isCompleted, isFalse);
      expect(ride.activeRideStatus.value, '5');
      expect(ride.customerPaymentEnabled.value, isTrue);
      expect(
          tester
              .widget<AppButton>(
                  find.widgetWithText(AppButton, 'متابعة إلى الدفع'))
              .onPressed,
          isNotNull);

      repository.pendingDetail = null;
      pending.complete(repository.detail);
      await tester.pump();
      await tester.tap(find.text('متابعة إلى الدفع'));
      await tester.pumpAndSettle();
      expect(Get.currentRoute, RideRoutes.payment);
    } finally {
      final pending = repository.pendingDetail;
      repository.pendingDetail = null;
      if (pending != null && !pending.isCompleted) {
        pending.complete(repository.detail);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final recovery in ['refresh', 'reconnect', 'app resume']) {
    workflowTest('missed payment event is recovered by $recovery',
        (tester) async {
      await tester.pumpWidget(_host());
      await ride.resumeOpenRide('7');
      await tester.pumpAndSettle();
      expect(ride.customerPaymentEnabled.value, isFalse);
      repository.customerPaymentEnabled = true;
      final readsBeforeRecovery = repository.detailReads;
      switch (recovery) {
        case 'refresh':
          await ride.refreshActiveRide();
        case 'reconnect':
          hub.reconnects.add(null);
        case 'app resume':
          ride.didChangeAppLifecycleState(AppLifecycleState.resumed);
      }
      await tester.pumpAndSettle();
      expect(repository.detailReads, greaterThan(readsBeforeRecovery));
      expect(ride.activeRideStatus.value, '5');
      expect(ride.customerPaymentEnabled.value, isTrue);
      expect(Get.currentRoute, RideRoutes.driverLocation);
    });
  }

  workflowTest('startup restores payment enabled during an ongoing trip',
      (tester) async {
    repository.customerPaymentEnabled = true;
    await tester.pumpWidget(_host());
    await ride.restoreOpenRideOnLaunch();
    await tester.pumpAndSettle();
    expect(ride.currentRideId, '7');
    expect(ride.activeRideStatus.value, '5');
    expect(ride.customerPaymentEnabled.value, isTrue);
    expect(Get.currentRoute, RideRoutes.driverLocation);
  });

  workflowTest(
      'supported wallets and recovered failure remain available without a selected catalog entry',
      (tester) async {
    await tester.pumpWidget(_host());
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    final oldCatalog = AppEnvironment.paymentMethods;
    addTearDown(() => AppEnvironment.paymentMethods = oldCatalog);
    AppEnvironment.paymentMethods = const [
      PaymentMethodItem(
          id: 'JAIB',
          label: 'جيب',
          subtitle: '',
          icon: Icons.wallet,
          providerCode: 'Jaib',
          paymentMethodId: 8),
      PaymentMethodItem(
          id: 'FLOOSAK',
          label: 'فلوسك',
          subtitle: '',
          icon: Icons.wallet,
          providerCode: 'Floosak',
          paymentMethodId: 4),
    ];
    for (final id in ['JAIB', 'FLOOSAK']) {
      ride.preferredPaymentMethod.value = id;
      expect(payment.selectedExternalWalletSupported, isTrue);
    }
    AppEnvironment.paymentMethods = [];
    ride.preferredPaymentMethod.value = 'cash';
    payment.externalPayment.payment.value = WalletRidePayment.fromJson({
      'id': 88,
      'rideId': 7,
      'paymentMethodId': 8,
      'providerCode': 'Jaib',
      'providerName': 'جيب',
      'amount': 1500,
      'status': 'Failed',
      'nextAction': 'None',
      'message': 'الرصيد المتاح لا يكفي لإتمام الدفع.',
      'customerIsProviderVerified': false,
    });
    payment.externalPayment.stateKnown.value = true;
    expect(payment.showExternalPayment, isTrue);
    payment.paymentCompleted.value = true;
    expect(payment.showExternalPayment, isFalse);
    payment.paymentCompleted.value = false;
    payment.dismissExternalPayment();
    expect(payment.showExternalPayment, isFalse);
    expect(payment.paymentCompleted.value, isFalse);
  });

  workflowTest(
      'completion keeps an open wallet challenge visible until receipt continue',
      (tester) async {
    await tester.pumpWidget(_host());
    await ride.resumeOpenRide('7');
    await tester.pumpAndSettle();
    Get.toNamed<void>(RideRoutes.payment);
    await tester.pumpAndSettle();
    repository.status = 6;
    repository.requiresRating = true;
    hub.send('rideStatusUpdated', {'rideStatus': 6});
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.payment);
    expect(ride.pendingRatingRideId.value, '7');
    payment.paymentCompleted.value = true;
    payment.finishPaidRide();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, RideRoutes.review);
  });

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
