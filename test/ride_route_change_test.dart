import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/shared/models/ride_route_change_snapshot.dart';
import 'package:yemen_drive/shared/widgets/ride_route_change_panel.dart';

Map<String, Object?> routeSnapshot({
  String? status,
  bool mine = true,
  int id = 9,
  int version = 0,
  bool? canRequest,
  String expires = '2026-10-19T10:02:00Z',
}) =>
    {
      'rideId': 7,
      'serverNowUtc': '2026-10-19T10:00:00Z',
      'routeVersion': version,
      'canRequest': canRequest ?? (status == null || status == 'expired'),
      'history': <Object?>[],
      'request': status == null
          ? null
          : {
              'id': id,
              'status': status,
              'requestedByMe': mine,
              'canConfirm': status == 'quoted' && mine,
              'canDecide': status == 'pending' && !mine,
              'expiresAtUtc': expires,
              'newDestinationLabel': 'مطار صنعاء',
              'newDestinationLatitude': 15.476,
              'newDestinationLongitude': 44.219,
              'changeLatitude': 15.3,
              'changeLongitude': 44.1,
              'invoice': <String, Object?>{
                'previousTotal': 1100,
                'completedDistanceMeters': 1000,
                'completedFare': 250,
                'originalServiceFee': 100,
                'routeChangeFee': 100,
                'previousRouteChangeFees': 0,
                'newDistanceMeters': 4000,
                'newDurationSeconds': 600,
                'newRouteFare': 750,
                'waitingFee': 0,
                'newTotal': 1200,
                'difference': 100,
              },
            },
    };

class RouteApi extends ApiClient {
  RouteApi() : super(SecureStorageService());
  late Future<Map<String, Object?>> Function(String, Map<String, Object?>)
      handle;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<ApiResult<T>> execute<T>({
    required String model,
    required String operation,
    Object? data,
    T Function(Object?)? parse,
  }) async {
    expect(model, 'RideRouteChangeModel');
    final body = Map<String, Object?>.from(data! as Map);
    calls.add((operation, body));
    return ApiSuccess<T>(await handle(operation, body) as T);
  }
}

const destination = RideRouteDestination(
  latitude: 15.476,
  longitude: 44.219,
  label: 'مطار صنعاء',
);

Future<void> mountRoute(
  WidgetTester tester, {
  Future<void> Function()? changed,
  bool isDriver = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RideRouteChangePanel(
            rideId: 7,
            isDriver: isDriver,
            selectDestination: () async => destination,
            onRouteChanged: changed,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  testWidgets('rider never receives approval controls from a stale server role',
      (tester) async {
    final api = Get.put<ApiClient>(RouteApi()) as RouteApi;
    api.handle = (_, __) async =>
        routeSnapshot(status: 'pending', mine: false, canRequest: false);
    await mountRoute(tester);
    expect(find.text('مراجعة الفاتورة والموافقة'), findsNothing);
    expect(find.text('رفض تغيير الوجهة'), findsNothing);
    expect(
        api.calls.where((call) => call.$1 == 'accept' || call.$1 == 'reject'),
        isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  test('rejects wrong rides and missing or nonfinite financial fields', () {
    expect(
      () => RideRouteChangeSnapshot(
        routeSnapshot()..['rideId'] = 8,
        expectedRideId: 7,
      ),
      throwsFormatException,
    );
    final raw = routeSnapshot(status: 'quoted');
    final request = raw['request']! as Map<String, Object?>;
    final invoice = request['invoice']! as Map<String, Object?>;
    invoice.remove('newTotal');
    expect(
      () => RideRouteChangeSnapshot(raw, expectedRideId: 7),
      throwsFormatException,
    );
    invoice['newTotal'] = double.nan;
    expect(
      () => RideRouteChangeSnapshot(raw, expectedRideId: 7),
      throwsFormatException,
    );
    invoice['newTotal'] = 900;
    invoice['difference'] = -200;
    expect(
      RideRouteChangeSnapshot(raw, expectedRideId: 7)
          .request!
          .invoice['difference'],
      -200,
    );
  });

  testWidgets(
      'quote and invoice precede submission; only acceptance refreshes ride',
      (tester) async {
    final api = Get.put<ApiClient>(RouteApi()) as RouteApi;
    var state = routeSnapshot();
    var refreshed = 0;
    api.handle = (operation, body) async {
      if (operation == 'quote') {
        expect(body.keys.toSet(), {
          'rideId',
          'requestKey',
          'newDestinationLatitude',
          'newDestinationLongitude',
          'newDestinationLabel',
        });
        expect(
          body['requestKey'],
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
        state = routeSnapshot(status: 'quoted');
      }
      if (operation == 'add') {
        expect(body, {'rideId': 7, 'requestId': 9});
        state = routeSnapshot(status: 'pending');
      }
      return state;
    };
    await mountRoute(
      tester,
      changed: () async {
        refreshed++;
      },
    );
    await tester.tap(find.text('اختيار وجهة جديدة وعرض الفاتورة'));
    await tester.pumpAndSettle();
    expect(find.text('فاتورة تغيير الوجهة'), findsOneWidget);
    expect(find.text('الإجمالي الجديد: 1200 ر.ي'), findsOneWidget);
    expect(api.calls.where((c) => c.$1 == 'add'), isEmpty);
    expect(refreshed, 0);
    await tester.tap(find.text('أوافق وأرسل الطلب'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.$1 == 'add'), hasLength(1));
    expect(refreshed, 0);
    state = routeSnapshot(status: 'accepted', version: 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(refreshed, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(refreshed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('driver can approve incoming pending when requesting is disabled',
      (tester) async {
    final api = Get.put<ApiClient>(RouteApi()) as RouteApi;
    var state =
        routeSnapshot(status: 'pending', mine: false, canRequest: false);
    api.handle = (operation, body) async {
      if (operation == 'accept') {
        state = routeSnapshot(status: 'accepted', mine: false, version: 1);
      }
      return state;
    };
    await mountRoute(tester, isDriver: true);
    expect(find.text('اختيار وجهة جديدة وعرض الفاتورة'), findsNothing);
    await tester.tap(find.text('مراجعة الفاتورة والموافقة'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.$1 == 'accept'), isEmpty);
    await tester.tap(find.text('أوافق على الوجهة والفاتورة'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.$1 == 'accept'), hasLength(1));
    expect(api.calls.last.$2, {'rideId': 7, 'requestId': 9});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'replacement or expired quote cannot be accepted from an old dialog',
      (tester) async {
    final api = Get.put<ApiClient>(RouteApi()) as RouteApi;
    var state = routeSnapshot(status: 'pending', mine: false);
    api.handle = (_, body) async => state;
    await mountRoute(tester, isDriver: true);
    await tester.tap(find.text('مراجعة الفاتورة والموافقة'));
    await tester.pumpAndSettle();
    state = routeSnapshot(status: 'pending', mine: false, id: 10);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أوافق على الوجهة والفاتورة'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.$1 == 'accept'), isEmpty);
    state = routeSnapshot(
      status: 'pending',
      mine: false,
      expires: '2026-10-19T09:59:00Z',
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'مراجعة الفاتورة والموافقة'),
    );
    expect(button.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'uncertain quote reuses its key and stale read cannot undo mutation',
      (tester) async {
    final api = Get.put<ApiClient>(RouteApi()) as RouteApi;
    var attempts = 0;
    var state = routeSnapshot();
    Completer<Map<String, Object?>>? delayed;
    api.handle = (operation, body) async {
      if (operation == 'quote') {
        if (++attempts == 1) throw Exception('connection lost');
        state = routeSnapshot(status: 'quoted');
      }
      if (operation == 'get' && delayed != null) return delayed.future;
      return state;
    };
    await mountRoute(tester);
    await tester.tap(find.text('اختيار وجهة جديدة وعرض الفاتورة'));
    await tester.pumpAndSettle();
    delayed = Completer<Map<String, Object?>>();
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('اختيار وجهة جديدة وعرض الفاتورة'));
    await tester.pumpAndSettle();
    final quotes = api.calls.where((c) => c.$1 == 'quote').toList();
    expect(quotes, hasLength(2));
    expect(quotes[0].$2['requestKey'], quotes[1].$2['requestKey']);
    delayed.complete(routeSnapshot());
    delayed = null;
    await tester.pumpAndSettle();
    expect(find.text('فاتورة تغيير الوجهة'), findsOneWidget);
    await tester.tap(find.text('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('مراجعة الفاتورة والموافقة'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('initial accepted version restores the ride and fits 320px RTL',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = Get.put<ApiClient>(RouteApi()) as RouteApi;
    api.handle =
        (_, body) async => routeSnapshot(status: 'accepted', version: 2);
    var refreshed = 0;
    await mountRoute(
      tester,
      changed: () async {
        refreshed++;
      },
    );
    expect(refreshed, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
