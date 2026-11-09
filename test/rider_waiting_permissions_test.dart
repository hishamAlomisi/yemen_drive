import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/shared/models/ride_waiting_snapshot.dart';
import 'ride_waiting_test.dart' show FakeWaitingApi, snapshot, mount;

void main() {
  tearDown(Get.reset);

  test('resume permissions require an active driver-controlled stop', () {
    expect(
        RideWaitingSnapshot(snapshot(open: true, started: true))
            .canRequestResume,
        isTrue);
    expect(
        RideWaitingSnapshot(snapshot(open: true, canRequestResume: true))
            .canRequestResume,
        isFalse);
    expect(
        RideWaitingSnapshot(snapshot(started: true, canRequestResume: true))
            .canRequestResume,
        isFalse);
    expect(
        RideWaitingSnapshot(snapshot(
                open: true,
                started: true,
                resumePending: true,
                canRequestResume: true))
            .canRequestResume,
        isFalse);
    final oldServer = snapshot(open: true, started: true)
      ..remove('controlMode');
    expect(RideWaitingSnapshot(oldServer).canRequestResume, isFalse);
    expect(
        RideWaitingSnapshot(
                snapshot(open: true, started: true, canRequestResume: false))
            .canRequestResume,
        isFalse);
  });

  testWidgets('rider requests resume without stopping clock or settling fees',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    var state = snapshot(open: true, started: true);
    api.handle = (operation, body) async {
      if (operation == 'request_resume') {
        expect(body['rideId'], 7);
        expect(body['sessionId'], 10);
        expect(
            body['requestKey'],
            matches(RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')));
        state = snapshot(
            open: true,
            started: true,
            resumePending: true,
            resumeKey: body['requestKey'] as String);
      }
      return state;
    };
    await mount(tester);
    expect(find.text('الرحلة متوقفة'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
    expect(find.textContaining('المهلة المجانية لكل توقف: 1 دقيقة'),
        findsOneWidget);
    expect(find.textContaining('بعدها 60 ر.ي للدقيقة'), findsOneWidget);
    await tester.tap(find.text('طلب استئناف الرحلة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('بانتظار موافقة السائق'), findsOneWidget);
    expect(find.text('طلب استئناف الرحلة'), findsNothing);
    expect(find.text('الإجمالي الحالي: 1231 ر.ي'), findsOneWidget);
    expect(
        RideWaitingSnapshot(state).elapsedSeconds(const Duration(seconds: 1)),
        91);
    state = {
      ...state,
      'serverNowUtc': '2026-10-19T10:01:31.500Z',
      'waitingFee': 132,
      'totalAmount': 1232,
    };
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('1:31'), findsOneWidget);
    expect(api.calls.where((c) => c.$1 != 'get').map((c) => c.$1),
        ['request_resume']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rider ignores driver and legacy stop approval permissions',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    final state = snapshot(open: true, started: true)
      ..addAll({
        'canStart': true,
        'canRequest': true,
        'canDecide': true,
        'canDecideResume': true,
        'canResume': true,
        'requestedByMe': true
      });
    api.handle = (_, body) async => state;
    await mount(tester);
    for (final title in [
      'توقف بطلب الراكب',
      'بدء التوقف',
      'مراجعة وموافقة',
      'أوافق على بدء الانتظار',
      'رفض',
      'سحب طلب الانتظار',
      'استئناف الرحلة وإيقاف الانتظار'
    ]) {
      expect(find.text(title), findsNothing);
    }
    expect(find.text('طلب استئناف الرحلة'), findsOneWidget);
    expect(api.calls.where((c) => c.$1 != 'get'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  final unavailable = <String, Map<String, Object?>>{
    'legacy unstarted stop': snapshot(open: true, canRequestResume: true),
    'closed stop': snapshot(started: true, canRequestResume: true),
    'permission denied':
        snapshot(open: true, started: true, canRequestResume: false),
    'pending request': snapshot(
        open: true, started: true, resumePending: true, canRequestResume: true),
  };
  for (final entry in unavailable.entries) {
    testWidgets('${entry.key} offers no rider resume action', (tester) async {
      final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
      api.handle = (_, body) async => entry.value;
      await mount(tester);
      expect(find.text('طلب استئناف الرحلة'), findsNothing);
      expect(api.calls.where((c) => c.$1 != 'get'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('driver resume clears pending request and uses server fees',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    var state = snapshot(
        open: true, started: true, resumePending: true, resumeKey: 'old');
    api.handle = (_, body) async => state;
    await mount(tester);
    expect(find.textContaining('بانتظار موافقة السائق'), findsOneWidget);
    state = snapshot(
        settled: 131,
        started: true,
        canRequestResume: true,
        endReason: 'driver_resumed');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('بانتظار موافقة السائق'), findsNothing);
    expect(find.text('طلب استئناف الرحلة'), findsNothing);
    expect(find.text('استأنف السائق الرحلة وانتهى الانتظار.'), findsOneWidget);
    expect(find.text('الإجمالي الحالي: 1231 ر.ي'), findsOneWidget);
    expect(api.calls.where((c) => c.$1 != 'get'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('uncertain resume request retries its same idempotency key',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    api.handle = (operation, body) async {
      if (operation == 'request_resume') throw StateError('connection lost');
      return snapshot(open: true, started: true);
    };
    await mount(tester);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('طلب استئناف الرحلة'));
      await tester.pumpAndSettle();
    }
    final calls = api.calls.where((c) => c.$1 == 'request_resume').toList();
    expect(calls, hasLength(2));
    expect(calls[0].$2['requestKey'], calls[1].$2['requestKey']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rider may request again with a new key after driver rejects',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    var state = snapshot(open: true, started: true);
    api.handle = (operation, body) async {
      if (operation == 'request_resume')
        state = snapshot(
            open: true,
            started: true,
            resumePending: true,
            resumeKey: body['requestKey'] as String);
      return state;
    };
    await mount(tester);
    await tester.tap(find.text('طلب استئناف الرحلة'));
    await tester.pumpAndSettle();
    final firstKey = api.calls
        .firstWhere((c) => c.$1 == 'request_resume')
        .$2['requestKey'] as String;
    state = snapshot(
        open: true,
        started: true,
        resumeDecision: 'rejected',
        resumeKey: firstKey);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('لم يوافق السائق'), findsOneWidget);
    await tester.tap(find.text('طلب استئناف الرحلة'));
    await tester.pumpAndSettle();
    final requests = api.calls.where((c) => c.$1 == 'request_resume').toList();
    expect(requests, hasLength(2));
    expect(requests.last.$2['requestKey'], isNot(firstKey));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an older read cannot overwrite a successful resume request',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    var state = snapshot(open: true, started: true);
    Completer<Map<String, Object?>>? read;
    api.handle = (operation, body) {
      if (operation == 'request_resume') {
        state = snapshot(
            open: true,
            started: true,
            resumePending: true,
            resumeKey: body['requestKey'] as String);
        return Future.value(state);
      }
      return read?.future ?? Future.value(state);
    };
    await mount(tester);
    read = Completer<Map<String, Object?>>();
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.text('طلب استئناف الرحلة'));
    await tester.pumpAndSettle();
    read.complete(snapshot(open: true, started: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('بانتظار موافقة السائق'), findsOneWidget);
    expect(find.text('طلب استئناف الرحلة'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late resume reply for a previous ride is ignored',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    final pending = Completer<Map<String, Object?>>();
    api.handle = (operation, body) => operation == 'request_resume'
        ? pending.future
        : Future.value(snapshot(open: true, started: true));
    await mount(tester);
    await tester.tap(find.text('طلب استئناف الرحلة'));
    await tester.pump();
    await mount(tester, rideId: 8);
    pending.complete(snapshot(open: true, started: true, resumePending: true));
    await tester.pumpAndSettle();
    expect(find.text('طلب استئناف الرحلة'), findsOneWidget);
    expect(find.textContaining('بانتظار موافقة السائق'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid snapshot offers retry without crashing', (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    api.handle = (_, body) async => {};
    await mount(tester);
    expect(find.text('تعذرت مزامنة الانتظار. أعد المحاولة.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed synchronization disables resume requests',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    var failReads = false;
    api.handle = (_, body) async =>
        failReads ? <String, Object?>{} : snapshot(open: true, started: true);
    await mount(tester);
    failReads = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final button = tester.widget<OutlinedButton>(find.ancestor(
      of: find.text('طلب استئناف الرحلة'),
      matching: find.byType(OutlinedButton),
    ));
    expect(button.onPressed, isNull);
    await tester.tap(find.text('طلب استئناف الرحلة'));
    await tester.pump();
    expect(api.calls.where((c) => c.$1 != 'get'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('double tap does not issue another resume request while busy',
      (tester) async {
    final api = Get.put<ApiClient>(FakeWaitingApi()) as FakeWaitingApi;
    final request = Completer<Map<String, Object?>>();
    api.handle = (operation, body) => operation == 'request_resume'
        ? request.future
        : Future.value(snapshot(open: true, started: true));
    await mount(tester);
    await tester.tap(find.text('طلب استئناف الرحلة'));
    await tester.pump();
    await tester.tap(find.text('طلب استئناف الرحلة'));
    await tester.pump();
    expect(api.calls.where((c) => c.$1 == 'request_resume'), hasLength(1));
    request.complete(snapshot(open: true, started: true, resumePending: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
