import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/location_selection/controllers/location_selection_controller.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/location_search_repository.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/route_repository.dart';

class _Routes implements RouteRepository {
  final requests = <Completer<DrivingRoute>>[];
  @override
  Future<DrivingRoute> getDrivingRoute(
      {required LatLng origin,
      required LatLng destination,
      bool includeSteps = false}) {
    final request = Completer<DrivingRoute>();
    requests.add(request);
    return request.future;
  }
}

class _Places implements LocationSearchRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const start = LatLng(15.3, 44.1), end = LatLng(15.4, 44.2);
const serverError = RouteRequestException(
    statusCode: 503,
    message: 'خدمة المسارات غير مهيأة على الخادم',
    code: 'routes_not_configured');
const route = DrivingRoute(
    points: [start, end], distanceMeters: 1400, durationSeconds: 250);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Routes routes;
  late LocationController controller;
  setUp(() {
    Get.testMode = true;
    routes = _Routes();
    final storage = SecureStorageService();
    final api = ApiClient(storage);
    controller = LocationController(
        routes, _Places(), api, AuthSessionService(storage, api));
    // Keep controller unregistered: these tests exercise route requests without
    // the unrelated native marker, GPS or saved-place lifecycle.
    controller.pickup.value = start;
    controller.destination.value = end;
  });
  tearDown(() {
    if (!controller.isClosed) controller.onDelete();
    Get.reset();
  });

  testWidgets('route error stores and presents the server reason',
      (tester) async {
    await tester
        .pumpWidget(GetMaterialApp(home: const Scaffold(body: Text('route'))));
    final request = controller.retryDrivingRoute();
    routes.requests.single.completeError(serverError);
    await request;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.routeError.value, serverError.message);
    expect(controller.isRouteLoading.value, false);
    expect(find.text(serverError.message), findsOneWidget);
    Get.closeAllSnackbars();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  for (final fail in [false, true]) {
    test('reset ignores a pending route ${fail ? 'error' : 'result'}',
        () async {
      final request = controller.retryDrivingRoute();
      controller.resetForNewRide();
      if (fail) {
        routes.requests.single.completeError(serverError);
      } else {
        routes.requests.single.complete(route);
      }
      await request;
      expect(controller.pickup.value, isNull);
      expect(controller.destination.value, isNull);
      expect(controller.routePoints, isEmpty);
      expect(controller.routeError.value, isEmpty);
      expect(controller.isRouteLoading.value, false);
    });
    test(
        'disposed controller ignores a pending route ${fail ? 'error' : 'result'}',
        () async {
      final request = controller.retryDrivingRoute();
      controller.onDelete();
      if (fail) {
        routes.requests.single.completeError(serverError);
      } else {
        routes.requests.single.complete(route);
      }
      await request;
      expect(controller.routePoints, isEmpty);
      expect(controller.routeError.value, isEmpty);
    });
  }

  test('out-of-order responses cannot replace the newly selected route',
      () async {
    final oldRequest = controller.retryDrivingRoute();
    const newEnd = LatLng(15.5, 44.3);
    controller.destination.value = newEnd;
    final newRequest = controller.retryDrivingRoute();
    routes.requests[1].complete(const DrivingRoute(
        points: [start, newEnd], distanceMeters: 3200, durationSeconds: 600));
    await newRequest;
    routes.requests[0].complete(route);
    await oldRequest;
    expect(controller.routePoints, [start, newEnd]);
    expect(controller.routeDistanceMeters.value, 3200);
    expect(controller.routeDurationSeconds.value, 600);
    expect(controller.routeError.value, isEmpty);
  });
}
