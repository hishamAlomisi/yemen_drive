import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/shared/models/ride_waiting_snapshot.dart';
import 'package:yemen_drive/shared/widgets/ride_waiting_panel.dart';

Map<String, Object?> snapshot({
  bool open = false,
  bool started = false,
  bool resumePending = false,
  bool? canRequestResume,
  String? resumeDecision,
  String? resumeKey,
  String? endReason,
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
      'controlMode': 'driver',
      'canRequestResume':
          canRequestResume ?? (open && started && !resumePending),
      'resumeRequestPending': resumePending,
      'session': {
        'id': id,
        'isOpen': open,
        'startedAtUtc': started ? '2026-10-19T10:00:00Z' : null,
        'endedAtUtc': open ? null : now,
        'freeMinutes': 1,
        'pricePerMinute': 60,
        'maxFee': 50,
        'fee': fee - settled,
        'endReason': endReason,
        'resumeRequestPending': resumePending,
        'resumeRequest': resumeKey == null
            ? null
            : {'requestKey': resumeKey, 'decision': resumeDecision},
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

Future<void> mount(WidgetTester tester, {int rideId = 7}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
        body: SingleChildScrollView(
      child: RideWaitingPanel(rideId: rideId),
    )),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('legacy unstarted stop has no running clock or new charges', () {
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
}
