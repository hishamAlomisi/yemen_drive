import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/controllers/ride_controller.dart';
import 'package:yemen_drive/features/ride/controllers/route_deviation_controller.dart';
import 'package:yemen_drive/features/ride/models/route_deviation_status.dart';
import 'package:yemen_drive/features/ride/negotiation/repositories/ride_negotiation_repository.dart';

class _RideRepository implements RideNegotiationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeviationRepository implements RouteDeviationRepository {
  int checks = 0;
  int reports = 0;
  Future<RouteDeviationStatus>? pendingReport;
  RouteDeviationStatus status = const RouteDeviationStatus(
    available: true,
    isDeviating: true,
    distanceMeters: 26,
    direction: 'شرق',
    routeVersion: '1',
  );
  RouteDeviationStatus reportResult = const RouteDeviationStatus(
    available: true,
    isDeviating: true,
    distanceMeters: 26,
    direction: 'شرق',
    routeVersion: '1',
    accepted: true,
  );
  @override
  Future<RouteDeviationStatus> check(String rideId) async {
    checks++;
    return status;
  }

  @override
  Future<RouteDeviationStatus> report(String rideId) async {
    reports++;
    if (pendingReport != null) return await pendingReport!;
    return reportResult;
  }
}

void main() {
  late RideController ride;
  late _DeviationRepository repository;
  late RouteDeviationController controller;
  Future<void> start(WidgetTester tester) async {
    Get.testMode = true;
    await tester
        .pumpWidget(const GetMaterialApp(home: Scaffold(body: Text('Trip'))));
    await tester.pump();
    final storage = SecureStorageService();
    ride = RideController(
        _RideRepository(), AuthSessionService(storage, ApiClient(storage)));
    ride.chatRideId.value = '7';
    ride.activeRideStatus.value = '5';
    repository = _DeviationRepository();
    controller = Get.put(RouteDeviationController(repository, ride));
    await tester.pumpAndSettle();
  }

  tearDown(Get.reset);

  testWidgets(
      'automatic warning gives distance and direction; safe does not submit a report',
      (tester) async {
    await start(tester);
    expect(find.text('تنبيه انحراف عن المسار'), findsOneWidget);
    expect(find.textContaining('26 متر باتجاه شرق'), findsOneWidget);
    await tester.tap(find.text('نعم، المسار آمن'));
    await tester.pumpAndSettle();
    expect(repository.reports, 0);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('تنبيه انحراف عن المسار'), findsNothing);
    expect(repository.reports, 0);
    Get.delete<RouteDeviationController>(force: true);
  });

  testWidgets(
      'report button submits once then shows accepted status without ending trip',
      (tester) async {
    await start(tester);
    await tester.tap(find.text('لا، الإبلاغ عن انحراف المسار'));
    await tester.pumpAndSettle();
    expect(repository.reports, 1);
    expect(find.text('تم قبول بلاغ انحراف المسار'), findsOneWidget);
    expect(ride.activeRideStatus.value, '5');
    await tester.tap(find.text('متابعة الرحلة'));
    await tester.pumpAndSettle();
    Get.delete<RouteDeviationController>(force: true);
  });

  testWidgets(
      'manual report honors server revalidation instead of reporting on-route driver',
      (tester) async {
    await start(tester);
    await tester.tap(find.text('نعم، المسار آمن'));
    await tester.pumpAndSettle();
    repository.reportResult = const RouteDeviationStatus(
        available: true,
        isDeviating: false,
        distanceMeters: 8,
        direction: '',
        routeVersion: '1',
        message: 'الرحلة ما زالت تسير في مسارها.');
    final task = controller.reportFromSafety();
    await tester.pumpAndSettle();
    expect(find.text('لا يوجد انحراف يستدعي البلاغ'), findsOneWidget);
    expect(find.text('الرحلة ما زالت تسير في مسارها.'), findsOneWidget);
    expect(find.text('تم قبول بلاغ انحراف المسار'), findsNothing);
    await tester.tap(find.text('متابعة الرحلة'));
    await tester.pumpAndSettle();
    await task;
    Get.delete<RouteDeviationController>(force: true);
  });

  testWidgets('ending the ride closes pending warning and stops polling',
      (tester) async {
    await start(tester);
    final checks = repository.checks;
    ride.activeRideStatus.value = '6';
    await tester.pumpAndSettle();
    expect(find.text('تنبيه انحراف عن المسار'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    expect(repository.checks, checks);
    Get.delete<RouteDeviationController>(force: true);
  });

  testWidgets(
      'verified return to route closes the old warning without acknowledging it',
      (tester) async {
    await start(tester);
    repository.status = const RouteDeviationStatus(
        available: true,
        isDeviating: false,
        distanceMeters: 6,
        direction: 'شرق',
        routeVersion: '1');
    await controller.checkNow();
    await tester.pumpAndSettle();
    expect(find.text('تنبيه انحراف عن المسار'), findsNothing);
    expect(repository.reports, 0);
    repository.status = const RouteDeviationStatus(
        available: true,
        isDeviating: true,
        distanceMeters: 32,
        direction: 'شرق',
        routeVersion: '1');
    await controller.checkNow();
    await tester.pumpAndSettle();
    expect(find.textContaining('32 متر باتجاه شرق'), findsOneWidget);
    Get.delete<RouteDeviationController>(force: true);
  });

  testWidgets(
      'approved new route replaces pending warning with the current distance and direction',
      (tester) async {
    await start(tester);
    repository.status = const RouteDeviationStatus(
        available: true,
        isDeviating: true,
        distanceMeters: 48,
        direction: 'جنوب',
        routeVersion: '2');
    await controller.checkNow();
    await tester.pumpAndSettle();
    expect(find.textContaining('26 متر باتجاه شرق'), findsNothing);
    expect(find.textContaining('48 متر باتجاه جنوب'), findsOneWidget);
    expect(find.text('تنبيه انحراف عن المسار'), findsOneWidget);
    expect(repository.reports, 0);
    Get.delete<RouteDeviationController>(force: true);
  });

  testWidgets(
      'current warning updates in place and unavailable data removes the old assertion',
      (tester) async {
    await start(tester);
    repository.status = const RouteDeviationStatus(
        available: true,
        isDeviating: true,
        distanceMeters: 35,
        direction: 'غرب',
        routeVersion: '1');
    await controller.checkNow();
    await tester.pumpAndSettle();
    expect(find.textContaining('35 متر باتجاه غرب'), findsOneWidget);
    expect(find.textContaining('26 متر باتجاه شرق'), findsNothing);
    repository.status = const RouteDeviationStatus(
        available: false,
        isDeviating: false,
        distanceMeters: 0,
        direction: '',
        routeVersion: '1');
    await controller.checkNow();
    await tester.pumpAndSettle();
    expect(find.text('تنبيه انحراف عن المسار'), findsNothing);
    expect(find.textContaining('الرحلة ما زالت'), findsNothing);
    Get.delete<RouteDeviationController>(force: true);
  });

  testWidgets(
      'late failed report cannot open a stale dialog after the ride ends',
      (tester) async {
    await start(tester);
    await tester.tap(find.text('نعم، المسار آمن'));
    await tester.pumpAndSettle();
    final pending = Completer<RouteDeviationStatus>();
    repository.pendingReport = pending.future;
    final task = controller.reportFromSafety();
    ride.activeRideStatus.value = '6';
    pending.completeError(StateError('late domain failure'));
    await task;
    await tester.pumpAndSettle();
    expect(find.text('تعذر إرسال البلاغ'), findsNothing);
    expect(find.text('متابعة الرحلة'), findsNothing);
    Get.delete<RouteDeviationController>(force: true);
  });
}
