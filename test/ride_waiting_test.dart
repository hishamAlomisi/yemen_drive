import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../lib/core/network/api_client.dart';
import '../lib/core/network/api_models.dart';
import '../lib/core/storage/secure_storage_service.dart';
import '../lib/shared/models/ride_waiting_snapshot.dart';
import '../lib/shared/widgets/ride_waiting_panel.dart';

Map<String, Object?> snapshot({
  bool open = false,
  bool started = false,
  bool mine = false,
  int id = 10,
  String now = '2026-10-19T10:01:30.500Z',
  double settled = 100,
  double fee = 131,
  String? deadline,
}) =>
    {
      'serverNowUtc': now,
      'waitingFreeMinutes': 1,
      'waitingPricePerMinute': 60,
      'waitingMaxFee': 150,
      'settledWaitingFee': settled,
      'waitingFee': fee,
      'baseFare': 1000,
      'serviceFee': 100,
      'totalAmount': 1100 + fee,
      'connectionDeadlineUtc': deadline,
      'canRequest': !open,
      'canDecide': open && !started && !mine,
      'requestedByMe': mine,
      'session': {
        'id': id,
        'isOpen': open,
        'startedAtUtc': started ? '2026-10-19T10:00:00Z' : null,
        'endedAtUtc': open ? null : now,
        'freeMinutes': 1,
        'pricePerMinute': 60,
        'maxFee': 50,
        'fee': fee - settled,
      },
    };

class FakeWaitingApi extends ApiClient {
  FakeWaitingApi() : super(SecureStorageService());
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
    expect(model, 'RideWaitingModel');
    final body = Map<String, Object?>.from(data! as Map);
    calls.add((operation, body));
    final result = await handle(operation, body);
    return ApiSuccess<T>(result as T);
  }
}

Future<void> mount(WidgetTester tester,
    {int rideId = 7, bool driver = true}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
        body: SingleChildScrollView(
      child: RideWaitingPanel(rideId: rideId, isDriver: driver),
    )),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('pending consent has no running clock or new charges', () {
    final value = RideWaitingSnapshot(snapshot(open: true, fee: 100));
    expect(value.elapsedSeconds(const Duration(minutes: 1)), 0);
    expect(value.waitingFee(const Duration(minutes: 1)), 100);
    expect(value.totalAmount(const Duration(minutes: 1)), 1200);
  });

  test('free minute and fractional-second rounding match server billing', () {
    final free = RideWaitingSnapshot(snapshot(
      open: true,
      started: true,
      now: '2026-10-19T10:00:59.999Z',
      fee: 100,
    ));
    expect(free.waitingFee(Duration.zero), 100);
    final active = RideWaitingSnapshot(snapshot(open: true, started: true));
    expect(active.waitingFee(Duration.zero), 131);
    expect(active.elapsedSeconds(Duration.zero), 90);
    expect(active.totalAmount(Duration.zero), 1231);
  });

  test('all stops respect the remaining cap and local projection freezes', () {
    final active = RideWaitingSnapshot(snapshot(open: true, started: true));
    expect(active.waitingFee(const Duration(hours: 1)), 146);
    expect(active.elapsedSeconds(const Duration(hours: 1)), 105);
    final capped = RideWaitingSnapshot(snapshot(
      open: true,
      started: true,
      now: '2026-10-19T10:05:00Z',
      fee: 150,
    ));
    expect(capped.waitingFee(Duration.zero), 150);
  });

  test('connection deadline freezes time and closed session uses server fees',
      () {
    final active = RideWaitingSnapshot(snapshot(
      open: true,
      started: true,
      deadline: '2026-10-19T10:01:35Z',
    ));
    expect(active.waitingFee(const Duration(seconds: 15)), 135);
    expect(active.elapsedSeconds(const Duration(seconds: 15)), 95);
    final closed = RideWaitingSnapshot(snapshot(settled: 131));
    expect(closed.waitingFee(const Duration(hours: 1)), 131);
    expect(closed.totalAmount(const Duration(hours: 1)), 1231);
    expect(() => RideWaitingSnapshot({}), throwsFormatException);
  });

  tearDown(Get.reset);

  testWidgets('driver request waits for consent, then resumes and settles',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    var state = snapshot(fee: 100);
    api.handle = (operation, body) async {
      if (operation == 'add') {
        expect(body['rideId'], 7);
        expect(
            body['requestKey'],
            matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            )));
        state = snapshot(open: true, mine: true, fee: 100);
      }
      if (operation == 'update') {
        expect(body['sessionId'], 10);
        state = snapshot(settled: 131);
      }
      return state;
    };
    await mount(tester);
    await tester.tap(find.text('توقف بطلب الراكب'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.$1 == 'add'), isEmpty);
    await tester.tap(find.text('إرسال الطلب'));
    await tester.pumpAndSettle();
    expect(find.text('طلب انتظار بانتظار الموافقة'), findsOneWidget);
    expect(find.text('استئناف الرحلة وإيقاف الانتظار'), findsNothing);
    state = snapshot(open: true, started: true, mine: true);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('1:30'), findsOneWidget);
    await tester.tap(find.text('استئناف الرحلة وإيقاف الانتظار'));
    await tester.pumpAndSettle();
    expect(find.text('الإجمالي الحالي: 1231 ر.ي'), findsOneWidget);
    expect(api.calls.where((c) => c.$1 == 'update'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('recipient consent starts waiting and passenger cannot resume',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    var state = snapshot(open: true, fee: 100);
    api.handle = (operation, body) async {
      if (operation == 'accept') {
        expect(body['sessionId'], 10);
        state = snapshot(open: true, started: true);
      }
      return state;
    };
    await mount(tester, driver: false);
    await tester.tap(find.text('مراجعة وموافقة'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.$1 == 'accept'), isEmpty);
    await tester.tap(find.text('أوافق على بدء الانتظار'));
    await tester.pumpAndSettle();
    expect(find.text('1:30'), findsOneWidget);
    expect(find.text('استئناف الرحلة وإيقاف الانتظار'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('approval dialog cannot approve a replacement session',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    var state = snapshot(open: true, fee: 100);
    api.handle = (_, body) async => state;
    await mount(tester);
    await tester.tap(find.text('مراجعة وموافقة'));
    await tester.pumpAndSettle();
    state = snapshot(open: true, id: 11, fee: 100);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    await tester.tap(find.text('أوافق على بدء الانتظار'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.$1 == 'accept'), isEmpty);
    expect(
        find.text('تغيرت حالة الانتظار. راجع الحالة المحدثة.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late reply for previous ride is ignored', (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    final old = Completer<Map<String, Object?>>();
    api.handle = (_, body) => body['rideId'] == 7
        ? old.future
        : Future.value(snapshot(open: true, mine: true, fee: 100));
    await mount(tester);
    await mount(tester, rideId: 8);
    old.complete(snapshot(open: true, started: true));
    await tester.pumpAndSettle();
    expect(find.text('طلب انتظار بانتظار الموافقة'), findsOneWidget);
    expect(find.text('1:30'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid response offers retry without crashing', (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    api.handle = (_, body) async => {};
    await mount(tester);
    expect(find.text('تعذرت مزامنة الانتظار. أعد المحاولة.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mine in [true, false]) {
    testWidgets(
        mine
            ? 'requester can withdraw without fees'
            : 'recipient can reject without fees', (tester) async {
      final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
      var state = snapshot(open: true, mine: mine, fee: 100);
      final operation = mine ? 'cancel' : 'reject';
      api.handle = (action, body) async {
        if (action == operation) {
          expect(body['sessionId'], 10);
          state = snapshot(fee: 100);
        }
        return state;
      };
      await mount(tester);
      await tester.tap(find.text(mine ? 'سحب طلب الانتظار' : 'رفض'));
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c.$1 == operation), hasLength(1));
      expect(find.text('طلب انتظار بانتظار الموافقة'), findsNothing);
      expect(find.text('الإجمالي الحالي: 1200 ر.ي'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('an uncertain request retries with the same idempotency key',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    api.handle = (action, body) async {
      if (action == 'add') throw StateError('connection lost');
      return snapshot(fee: 100);
    };
    await mount(tester);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('توقف بطلب الراكب'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إرسال الطلب'));
      await tester.pumpAndSettle();
    }
    final calls = api.calls.where((c) => c.$1 == 'add').toList();
    expect(calls, hasLength(2));
    expect(calls[0].$2['requestKey'], calls[1].$2['requestKey']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a read started before acceptance cannot replace its result',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    var state = snapshot(open: true, fee: 100);
    Completer<Map<String, Object?>>? read;
    api.handle = (action, body) async {
      if (action == 'accept') {
        state = snapshot(open: true, started: true);
        return state;
      }
      return read == null ? state : read.future;
    };
    await mount(tester);
    read = Completer<Map<String, Object?>>();
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('مراجعة وموافقة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أوافق على بدء الانتظار'));
    await tester.pumpAndSettle();
    read.complete(snapshot(open: true, fee: 100));
    await tester.pumpAndSettle();
    expect(find.text('1:30'), findsOneWidget);
    expect(find.text('طلب انتظار بانتظار الموافقة'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
