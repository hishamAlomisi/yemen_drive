import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as maps;
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/realtime/ride_map_route_observer.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/controllers/ride_controller.dart';
import 'package:yemen_drive/features/ride/models/ride_models.dart';
import 'package:yemen_drive/features/ride/negotiation/repositories/ride_negotiation_repository.dart';
import 'package:yemen_drive/shared/widgets/app_google_map.dart';
import 'package:yemen_drive/shared/widgets/nearby_driver_card.dart';

class _Repository implements RideNegotiationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ride extends RideController {
  _Ride()
      : super(
            _Repository(),
            AuthSessionService(
                SecureStorageService(), ApiClient(SecureStorageService())));
  final owners = <Object>{};
  @override
  // Tests isolate map route ownership from GPS and account startup.
  // ignore: must_call_super
  void onInit() {}
  @override
  void onReady() {}
  @override
  void setNearbyMapVisible(Object owner, bool visible) {
    visible ? owners.add(owner) : owners.remove(owner);
  }
}

class _MapPlatform extends maps.GoogleMapsFlutterPlatform {
  @override
  void dispose({required int mapId}) {}

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

class _InteractiveMapPlatform extends maps.MethodChannelGoogleMapsFlutter {
  final initialized = <int>{};
  int projections = 0;
  ScreenCoordinate Function(LatLng point)? projectCoordinate;
  final markerUpdates = <maps.MarkerUpdates>[];
  final cameraUpdates = <CameraUpdate>[];
  Completer<void>? cameraGate;
  int cameraInFlight = 0, maxCameraInFlight = 0;
  Future<void> _camera(CameraUpdate update) async {
    cameraUpdates.add(update);
    cameraInFlight++;
    if (cameraInFlight > maxCameraInFlight) maxCameraInFlight = cameraInFlight;
    await cameraGate?.future;
    cameraInFlight--;
  }

  @override
  Future<void> animateCamera(CameraUpdate update,
          {required int mapId, Duration? duration}) =>
      _camera(update);
  @override
  Future<void> moveCamera(CameraUpdate update, {required int mapId}) =>
      _camera(update);
  @override
  Future<void> updateMarkers(maps.MarkerUpdates updates,
      {required int mapId}) async {
    markerUpdates.add(updates);
  }

  @override
  Future<void> updateGroundOverlays(maps.GroundOverlayUpdates updates,
      {required int mapId}) async {}
  @override
  Widget buildViewWithConfiguration(
      int creationId, ValueChanged<int> onPlatformViewCreated,
      {required maps.MapWidgetConfiguration widgetConfiguration,
      maps.MapConfiguration mapConfiguration = const maps.MapConfiguration(),
      maps.MapObjects mapObjects = const maps.MapObjects()}) {
    if (initialized.add(creationId)) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              MethodChannel('plugins.flutter.io/google_maps_$creationId'),
              (_) async => null);
      scheduleMicrotask(() => onPlatformViewCreated(creationId));
    }
    return const ColoredBox(color: Colors.transparent);
  }

  @override
  Future<ScreenCoordinate> getScreenCoordinate(LatLng latLng,
      {required int mapId}) async {
    projections++;
    return projectCoordinate?.call(latLng) ??
        const ScreenCoordinate(x: 180, y: 390);
  }
}

void main() {
  late _Ride ride;
  late maps.GoogleMapsFlutterPlatform previous;
  setUpAll(() async {
    final directory = Directory('build/nearby-map-test-storage')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.absolute.path);
    await GetStorage.init();
  });
  setUp(() {
    Get.testMode = true;
    previous = maps.GoogleMapsFlutterPlatform.instance;
    maps.GoogleMapsFlutterPlatform.instance = _MapPlatform();
    ride = Get.put<RideController>(_Ride()) as _Ride;
    ride.nearbyDrivers.add(const NearbyDriver(
        id: '3',
        name: 'Nearby',
        location: RideCoordinate(latitude: 15.361, longitude: 44.19),
        photoUrl: '',
        heading: 90,
        vehicleType: RideVehicleType.car,
        rating: 4));
  });
  tearDown(() {
    Get.reset();
    maps.GoogleMapsFlutterPlatform.instance = previous;
  });

  testWidgets(
      'every ordinary map gets nearby markers regardless of its camera target',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: AppGoogleMap(
            initialTarget: LatLng(16, 45), followTarget: LatLng(16.1, 45.1))));
    await tester.pump();
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.markers.single.markerId.value, 'nearby-3');
    expect(map.markers.single.position, const LatLng(15.361, 44.19));
    expect(map.markers.single.anchor, const Offset(.5, .5));
    expect(map.markers.single.rotation, 90);
    expect(map.markers.single.flat, isTrue);
    expect(map.markers.single.consumeTapEvents, isTrue);
    expect(map.markers.single.onTap, isNotNull);
    expect(ride.owners, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    expect(ride.owners, isEmpty);
  });

  testWidgets(
      'assigned-driver waiting and trip maps opt out of all unrelated nearby markers',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: AppGoogleMap(
      showNearbyDrivers: false,
      markers: {
        const Marker(
            markerId: MarkerId('assigned-driver'),
            position: LatLng(15.36, 44.19))
      },
    )));
    await tester.pump();
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.markers.map((m) => m.markerId.value), ['assigned-driver']);
    expect(ride.owners, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'covered route releases presence and returning route retains native map identity',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [rideMapRouteObserver],
      home: const AppGoogleMap(),
    ));
    await tester.pump();
    final mapElement = tester.element(find.byType(GoogleMap));
    expect(ride.owners, hasLength(1));
    navigator.currentState!.push(PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const Scaffold(body: Text('other page')),
    ));
    await tester.pump();
    await tester.pump();
    expect(ride.owners, isEmpty);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump();
    expect(ride.owners, hasLength(1));
    expect(tester.element(find.byType(GoogleMap)), same(mapElement));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'matching a driver suppresses discovery on every ordinary map and restores it for a new ride',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppGoogleMap()));
    await tester.pump();
    expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).markers, hasLength(1));
    ride.isDriverAssigned.value = true;
    ride.activeRideStatus.value = '4';
    await tester.pump();
    await tester.pump();
    expect(tester.widget<GoogleMap>(find.byType(GoogleMap)).markers, isEmpty);
    expect(ride.owners, isEmpty);
    ride.isDriverAssigned.value = false;
    ride.activeRideStatus.value = '';
    await tester.pump();
    await tester.pump();
    expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).markers, hasLength(1));
    expect(ride.owners, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'ordinary discovery map opens driver data card above projected marker and closes it',
      (tester) async {
    maps.GoogleMapsFlutterPlatform.instance = _InteractiveMapPlatform();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [rideMapRouteObserver],
        home: const AppGoogleMap()));
    await tester.pump();
    await tester.pump();
    tester.widget<GoogleMap>(find.byType(GoogleMap)).markers.single.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    await tester.pump();
    expect(find.byType(NearbyDriverCard), findsOneWidget);
    expect(find.text('Nearby'), findsOneWidget);
    expect(tester.getRect(find.byType(NearbyDriverCard)).bottom, lessThan(390));
    tester.widget<NearbyDriverCard>(find.byType(NearbyDriverCard)).onClose();
    await tester.pump();
    expect(find.byType(NearbyDriverCard), findsNothing);
    tester.widget<GoogleMap>(find.byType(GoogleMap)).markers.single.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    await tester.pump();
    expect(find.byType(NearbyDriverCard), findsOneWidget);
    navigator.currentState!.push(PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => const Scaffold(body: Text('covered'))));
    await tester.pump();
    await tester.pump();
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump();
    expect(find.byType(NearbyDriverCard), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'tracking vehicle opens assigned driver card while native location and unrelated drivers stay hidden',
      (tester) async {
    final platform = _InteractiveMapPlatform();
    maps.GoogleMapsFlutterPlatform.instance = platform;
    ride.trackedDriver.value = DriverTrackingSnapshot(
        driverId: '7',
        location: const RideCoordinate(latitude: 15.36, longitude: 44.19),
        updatedAt: DateTime.now(),
        heading: 90);
    ride.assignedDriverName.value = 'Captain';
    ride.assignedVehicleModel.value = 'Car model';
    ride.assignedPlateNumber.value = 'Plate 123';
    await tester.pumpWidget(MaterialApp(
        home: AppGoogleMap(
            showNearbyDrivers: false, markers: ride.trackingMarkers)));
    await tester.pump();
    await tester.pump();
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.markers, hasLength(1));
    expect(map.myLocationEnabled, isFalse);
    map.markers.single.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    await tester.pump();
    expect(find.text('Captain'), findsOneWidget);
    expect(find.text('Plate 123'), findsOneWidget);
    final projections = platform.projections;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(platform.projections, projections,
        reason:
            'a stationary driver card must not create a projection/rebuild loop');
    final card = tester.widget<NearbyDriverCard>(find.byType(NearbyDriverCard));
    final nativeFrames = platform.markerUpdates.length;
    for (var index = 1; index <= 20; index++) {
      ride.trackedDriver.value = DriverTrackingSnapshot(
        driverId: '7',
        location:
            RideCoordinate(latitude: 15.36 + index / 100000, longitude: 44.19),
        updatedAt: DateTime.now(),
        heading: 90,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 70));
    expect(platform.projections, greaterThan(projections));
    expect(tester.widget<NearbyDriverCard>(find.byType(NearbyDriverCard)),
        same(card),
        reason:
            'subpixel motion must reuse unchanged photo and driver details');
    platform.projectCoordinate = (point) => ScreenCoordinate(
        x: 180 + ((point.latitude - 15.36) * 10000).round(), y: 390);
    ride.trackedDriver.value = DriverTrackingSnapshot(
      driverId: '7',
      location: const RideCoordinate(latitude: 15.361, longitude: 44.19),
      updatedAt: DateTime.now(),
      heading: 90,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(platform.markerUpdates, hasLength(nativeFrames),
        reason: 'projecting an overlay must not rebuild the native map');
    ride.assignedDriverName.value = 'Updated captain';
    await tester.pump();
    expect(find.text('Updated captain'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('slow camera keeps one in flight and only the latest GPS target',
      (tester) async {
    final platform = _InteractiveMapPlatform()..cameraGate = Completer<void>();
    maps.GoogleMapsFlutterPlatform.instance = platform;
    Future<void> show(double latitude) => tester.pumpWidget(MaterialApp(
        home: AppGoogleMap(
            focusTarget: LatLng(latitude, 44.19),
            continuousFocusTarget: true)));
    await show(15.36);
    await tester.pump();
    await tester.pump();
    expect(platform.cameraUpdates, hasLength(1));
    for (var i = 1; i <= 100; i++) {
      await show(15.36 + i / 10000);
    }
    expect(platform.cameraUpdates, hasLength(1));
    platform.cameraGate!.complete();
    platform.cameraGate = null;
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    expect(platform.maxCameraInFlight, 1);
    expect(platform.cameraUpdates, hasLength(2));
    expect(platform.cameraUpdates.last.toJson(),
        CameraUpdate.newLatLngZoom(const LatLng(15.37, 44.19), 15.5).toJson());
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'panning cancels queued GPS camera moves while markers keep updating until explicit recenter',
      (tester) async {
    final platform = _InteractiveMapPlatform()..cameraGate = Completer<void>();
    maps.GoogleMapsFlutterPlatform.instance = platform;
    var interactions = 0;
    Future<void> show(double latitude, {int request = 0}) =>
        tester.pumpWidget(MaterialApp(
          home: AppGoogleMap(
            showNearbyDrivers: false,
            pauseOnUserInteraction: true,
            followRequestId: request,
            onUserInteraction: () => interactions++,
            focusTarget: LatLng(latitude, 44.19),
            continuousFocusTarget: true,
            markers: {
              Marker(
                markerId: const MarkerId('vehicle'),
                position: LatLng(latitude, 44.19),
              ),
            },
          ),
        ));
    await show(15.36);
    await tester.pump();
    await tester.pump();
    expect(platform.cameraUpdates, hasLength(1));
    await show(15.361);
    final gesture = await tester.startGesture(const Offset(200, 200));
    await gesture.moveBy(const Offset(90, 40));
    await gesture.up();
    await tester.pump();
    expect(interactions, 1);
    for (var index = 2; index <= 50; index++) {
      await show(15.36 + index / 1000);
    }
    platform.cameraGate!.complete();
    platform.cameraGate = null;
    await tester.pump(const Duration(seconds: 1));
    expect(platform.cameraUpdates, hasLength(1));
    expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .markers
            .single
            .position,
        const LatLng(15.41, 44.19));

    // Returning to the app cannot silently steal the inspected viewport.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(platform.cameraUpdates, hasLength(1));

    await show(15.41, request: 1);
    await tester.pump(const Duration(milliseconds: 250));
    expect(platform.cameraUpdates, hasLength(2));
    await show(15.42, request: 1);
    await tester.pump(const Duration(milliseconds: 250));
    expect(platform.cameraUpdates.last.toJson(),
        CameraUpdate.newLatLngZoom(const LatLng(15.42, 44.19), 15.5).toJson());
    expect(platform.maxCameraInFlight, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pinch pauses follow but camera callbacks and a tap do not',
      (tester) async {
    final platform = _InteractiveMapPlatform();
    maps.GoogleMapsFlutterPlatform.instance = platform;
    var interactions = 0;
    Future<void> show(double latitude, {int request = 0}) =>
        tester.pumpWidget(MaterialApp(
          home: AppGoogleMap(
            showNearbyDrivers: false,
            pauseOnUserInteraction: true,
            followRequestId: request,
            onUserInteraction: () => interactions++,
            focusTarget: LatLng(latitude, 44.19),
          ),
        ));
    await show(15.36);
    await tester.pump();
    await tester.pump();
    tester.widget<GoogleMap>(find.byType(GoogleMap)).onCameraMove!(
        const CameraPosition(target: LatLng(15.36, 44.19), zoom: 15.5));
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 250));
    await show(15.37);
    await tester.pump(const Duration(milliseconds: 250));
    expect(interactions, 0);
    final cameraCount = platform.cameraUpdates.length;
    final first = await tester.startGesture(const Offset(200, 200), pointer: 1);
    final second =
        await tester.startGesture(const Offset(250, 250), pointer: 2);
    await first.up();
    await second.up();
    await show(15.38);
    await tester.pump(const Duration(seconds: 1));
    expect(interactions, 1);
    expect(platform.cameraUpdates, hasLength(cameraCount));
    await show(15.38, request: 1);
    await tester.pump(const Duration(milliseconds: 250));
    expect(platform.cameraUpdates, hasLength(cameraCount + 1));
    // A second explicit request must recenter even without a new GPS sample.
    await show(15.38, request: 2);
    await tester.pump(const Duration(milliseconds: 250));
    expect(platform.cameraUpdates, hasLength(cameraCount + 2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'native map coalesces a hundred frame burst, caps submission rate and always delivers the last frame',
      (tester) async {
    final platform = _InteractiveMapPlatform();
    maps.GoogleMapsFlutterPlatform.instance = platform;
    Future<void> show(double latitude) => tester.pumpWidget(MaterialApp(
          home: AppGoogleMap(
            showNearbyDrivers: false,
            nativeFrameInterval: const Duration(milliseconds: 33),
            markers: {
              Marker(
                markerId: const MarkerId('vehicle'),
                position: LatLng(latitude, 44.19),
              ),
            },
          ),
        ));
    await show(15.36);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final initialCalls = platform.markerUpdates.length;
    for (var index = 1; index <= 100; index++) {
      await show(15.36 + index / 10000);
    }
    expect(platform.markerUpdates, hasLength(initialCalls));
    await tester.pump(const Duration(milliseconds: 34));
    expect(platform.markerUpdates, hasLength(initialCalls + 1));
    expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .markers
            .single
            .position,
        const LatLng(15.37, 44.19));

    final callsBeforeAnimation = platform.markerUpdates.length;
    for (var index = 1; index <= 60; index++) {
      await show(15.37 + index / 10000);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 34));
    expect(platform.markerUpdates.length - callsBeforeAnimation,
        lessThanOrEqualTo(30));
    expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .markers
            .single
            .position,
        const LatLng(15.376, 44.19));
    final settledCalls = platform.markerUpdates.length;
    await tester.pump(const Duration(seconds: 1));
    expect(platform.markerUpdates, hasLength(settledCalls));

    await show(15.38);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 100));
    await show(15.39);
    await tester.pump(const Duration(milliseconds: 100));
    expect(platform.markerUpdates, hasLength(settledCalls));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .markers
            .single
            .position,
        const LatLng(15.39, 44.19));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
