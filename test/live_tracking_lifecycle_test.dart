import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/realtime/tracking_hub_service.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/controllers/ride_controller.dart';
import 'package:yemen_drive/features/ride/models/ride_models.dart';
import 'package:yemen_drive/features/ride/location_selection/controllers/location_selection_controller.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/location_search_repository.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/route_repository.dart';
import 'package:yemen_drive/features/ride/negotiation/repositories/ride_negotiation_repository.dart';
import 'package:yemen_drive/shared/widgets/live_tracking_marker_icons.dart';

class _Gps extends GeolocatorPlatform {
  bool enabled = true;
  Completer<LocationPermission>? permission;
  final streams = <StreamController<Position>>[];
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async =>
      permission?.future ?? LocationPermission.whileInUse;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    final stream = StreamController<Position>();
    streams.add(stream);
    return stream.stream;
  }

  Position fix(double latitude, {DateTime? observedAt, double accuracy = 8}) =>
      Position(
          latitude: latitude,
          longitude: 44.19,
          timestamp: observedAt ?? DateTime.now(),
          accuracy: accuracy,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 20,
          headingAccuracy: 0,
          speed: 2,
          speedAccuracy: 0);
}

class _Api extends ApiClient {
  _Api() : super(SecureStorageService());
  @override
  Future<ApiResult<T>> execute<T>(
          {required String model,
          required String operation,
          Object? data,
          T Function(Object?)? parse}) async =>
      ApiSuccess<T>(null as T);
}

class _Repository implements RideNegotiationRepository {
  int status = 4;
  int detailReads = 0;
  Completer<void>? pendingDetail;
  final nearbyCenters = <RideCoordinate>[];
  List<NearbyDriver> nearbySnapshot = [];
  @override
  Future<List<NearbyDriver>> getNearbyDrivers(
      {required RideCoordinate pickup,
      int? serviceKindId,
      int? serviceCatalogItemId}) async {
    nearbyCenters.add(pickup);
    return nearbySnapshot;
  }

  @override
  Future<Map<String, Object?>> getRideDetail(String requestId) async {
    detailReads++;
    await pendingDetail?.future;
    return {
      'ride': {
        'id': 7,
        'status': status,
        'pickupLatitude': 15.36,
        'pickupLongitude': 44.19,
        'destinationLatitude': 15.4,
        'destinationLongitude': 44.2,
        'customerPrice': 1000
      },
      'requiresRating': false,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Hub extends TrackingHubService {
  _Hub() : super(SecureStorageService());
  final changes = StreamController<TrackingHubEvent>.broadcast();
  final reconnects = StreamController<void>.broadcast();
  Completer<void>? join;
  bool publishResult = true;
  final sent = <Map<String, Object?>>[];
  final nearbyCenters = <LatLng>[];
  int nearbyLeaves = 0;
  @override
  Future<void> setNearbyDriverSubscription(
      {required int? serviceKindId,
      required int? serviceCatalogItemId,
      required double pickupLatitude,
      required double pickupLongitude,
      required int radiusMeters,
      Iterable<int> initialDriverIds = const []}) async {
    nearbyCenters.add(LatLng(pickupLatitude, pickupLongitude));
  }

  @override
  Future<void> clearNearbyDriverSubscription() async {
    nearbyLeaves++;
  }

  @override
  Stream<TrackingHubEvent> get events => changes.stream;
  @override
  Stream<void> get connectionRestored => reconnects.stream;
  @override
  Future<void> setUserEventListening(Object owner, bool listen) async {}
  @override
  Future<void> setRideSubscriptions(Iterable<int> ids) async {
    if (ids.isNotEmpty) await join?.future;
  }

  @override
  Future<bool> publishPassengerLocation(Map<String, Object?> payload) async {
    sent.add(payload);
    return publishResult;
  }

  @override
  Future<void> setForeground(bool foreground) async {}
}

class _Ride extends RideController {
  _Ride(super.repository, super.session);
  @override
  void onReady() {}
  @override
  void openActiveRide() {}
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
  // The booking markers use their fallback bitmap in this native GPS test.
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  late _Gps gps;
  late GeolocatorPlatform previousGps;
  late _Hub hub;
  late _Repository repository;
  late RideController ride;
  late LocationController location;
  setUpAll(() async {
    final directory = Directory('build/live-tracking-test-storage')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.absolute.path);
    await GetStorage.init();
  });
  setUp(() {
    Get.testMode = true;
    previousGps = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = gps = _Gps();
    final api = Get.put<ApiClient>(_Api());
    final session = AuthSessionService(SecureStorageService(), api);
    session.isAuthenticated.value = true;
    session.currentUserId.value = 1;
    hub = Get.put<TrackingHubService>(_Hub()) as _Hub;
    location = Get.put<LocationController>(_Location(api, session));
    repository = _Repository();
    ride = Get.put<RideController>(_Ride(repository, session));
  });
  tearDown(() async {
    Get.delete<RideController>(force: true);
    for (final stream in gps.streams) {
      await stream.close();
    }
    await hub.changes.close();
    await hub.reconnects.close();
    GeolocatorPlatform.instance = previousGps;
    Get.reset();
  });

  testWidgets(
      'local GPS starts while Hub join is blocked and avatar moves without changing pickup',
      (tester) async {
    hub.join = Completer<void>();
    await ride.resumeOpenRide('7');
    await tester.pump();
    expect(gps.streams, hasLength(1));
    gps.streams.single.add(gps.fix(15.361));
    await tester.pump();
    final passenger = ride.trackedPassenger.value!;
    final markers = location.liveTripMarkers(
        passengerPosition: LatLng(passenger.latitude, passenger.longitude));
    expect(
        markers
            .singleWhere((m) => m.markerId.value == 'tracked-passenger')
            .position,
        const LatLng(15.361, 44.19));
    expect(markers.singleWhere((m) => m.markerId.value == 'pickup').position,
        const LatLng(15.36, 44.19));
    expect(location.pickup.value, const LatLng(15.36, 44.19));
    final assignedMarkers = location.liveTripMarkers(
      passengerPosition: LatLng(passenger.latitude, passenger.longitude),
      hasTrackedDriver: true,
    );
    expect(
        assignedMarkers.where((m) => m.markerId.value == 'tracked-passenger'),
        isEmpty);
    expect(assignedMarkers.any((m) => m.markerId.value == 'pickup'), isTrue);
    gps.streams.single.add(gps.fix(15.362));
    await tester.pump();
    expect(ride.trackedPassenger.value!.latitude, 15.362);
    hub.join!.complete();
    await tester.pump();
    Get.delete<RideController>(force: true);
  });

  testWidgets(
      'nearby discovery ignores edited pickup and refreshes canonical markers after reconnect',
      (tester) async {
    location.pickup.value = const LatLng(16, 45);
    final owner = Object();
    ride.setNearbyMapVisible(owner, true);
    await tester.pump();
    repository.nearbySnapshot = [
      NearbyDriver(
        id: '3',
        name: 'nearby',
        location: const RideCoordinate(latitude: 15.362, longitude: 44.19),
        photoUrl: '',
        vehicleType: RideVehicleType.car,
        rating: 4,
        observedAt: DateTime.now().toUtc(),
      )
    ];
    gps.streams.single.add(gps.fix(15.361));
    await tester.pump();
    expect(repository.nearbyCenters.single.latitude, 15.361);
    expect(hub.nearbyCenters.single, const LatLng(15.361, 44.19));
    expect(ride.nearbyDrivers.single.id, '3');
    await ride.loadNearbyDrivers(center: const LatLng(17, 46));
    expect(repository.nearbyCenters.last.latitude, 15.361);
    expect(location.pickup.value, const LatLng(16, 45));
    repository.nearbySnapshot = [];
    await tester.runAsync(() async {
      hub.reconnects.add(null);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(repository.nearbyCenters, hasLength(3));
    expect(ride.nearbyDrivers, isEmpty);
    ride.setNearbyMapVisible(owner, false);
    await tester.pump();
  });

  testWidgets('native stream failure restarts GPS and preserves new samples',
      (tester) async {
    await ride.resumeOpenRide('7');
    await tester.pump();
    gps.streams.single.addError(StateError('provider unavailable'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(gps.streams, hasLength(2));
    gps.streams.last.add(gps.fix(15.363));
    await tester.pump();
    expect(ride.trackedPassenger.value!.latitude, 15.363);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'resuming after location service enabled starts stream without restarting ride',
      (tester) async {
    gps.enabled = false;
    await ride.resumeOpenRide('7');
    await tester.pump();
    expect(gps.streams, isEmpty);
    gps.enabled = true;
    ride.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(gps.streams, hasLength(1));
  });

  testWidgets(
      'ending ride while permission read is pending cannot resurrect GPS',
      (tester) async {
    gps.permission = Completer<LocationPermission>();
    await ride.resumeOpenRide('7');
    await tester.pump();
    repository.status = 6;
    await ride.refreshActiveRide(requireSuccess: true);
    gps.permission!.complete(LocationPermission.whileInUse);
    await tester.pump();
    expect(gps.streams, isEmpty);
  });

  testWidgets(
      'failed passenger send retries latest fix instead of dropping movement',
      (tester) async {
    hub.publishResult = false;
    await ride.resumeOpenRide('7');
    await tester.pump();
    gps.streams.single.add(gps.fix(15.361));
    await tester.pump();
    expect(hub.sent, hasLength(1));
    gps.streams.single.add(gps.fix(15.362));
    await tester.pump();
    hub.publishResult = true;
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 3100)));
    await tester.pump(const Duration(seconds: 3));
    expect(hub.sent.last['latitude'], 15.362);
    expect(ride.passengerLocationError.value, isNull);
  });

  testWidgets(
      'older passenger fixes cannot replace the visible or pending location',
      (tester) async {
    hub.publishResult = false;
    await ride.resumeOpenRide('7');
    await tester.pump();
    final now = DateTime.now();
    gps.streams.single.add(
        gps.fix(15.361, observedAt: now.subtract(const Duration(seconds: 2))));
    await tester.pump();
    gps.streams.single.add(
        gps.fix(15.362, observedAt: now.subtract(const Duration(seconds: 1))));
    await tester.pump();
    gps.streams.single.add(
        gps.fix(15.35, observedAt: now.subtract(const Duration(seconds: 2))));
    gps.streams.single.add(
        gps.fix(15.2, observedAt: now.subtract(const Duration(seconds: 40))));
    gps.streams.single
        .add(gps.fix(15.4, observedAt: now.add(const Duration(seconds: 10))));
    await tester.pump();
    expect(ride.trackedPassenger.value!.latitude, 15.362);
    hub.publishResult = true;
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 3100)));
    await tester.pump(const Duration(seconds: 3));
    expect(hub.sent.last['latitude'], 15.362);
  });

  testWidgets(
      'approximate passenger GPS explains why sharing awaits a precise fix',
      (tester) async {
    await ride.resumeOpenRide('7');
    await tester.pump();
    gps.streams.single.add(gps.fix(15.361, accuracy: 300));
    await tester.pump();
    expect(ride.trackedPassenger.value!.latitude, 15.361);
    expect(ride.passengerLocationApproximate.value, isTrue);
    expect(hub.sent, isEmpty);
    gps.streams.single.add(gps.fix(15.36, accuracy: 0));
    await tester.pump();
    expect(ride.trackedPassenger.value!.latitude, 15.361);
    gps.streams.single.add(gps.fix(15.362));
    await tester.pump();
    expect(ride.passengerLocationApproximate.value, isFalse);
    expect(hub.sent.single['latitude'], 15.362);
  });

  testWidgets(
      'driver fixes update marker and phase switches icon with true bearing',
      (tester) async {
    await ride.resumeOpenRide('7');
    await tester.pump();
    final now = DateTime.now().toUtc();
    Map<String, Object?> sample(int seconds, double latitude) => {
          'rideId': 7,
          'driverId': 3,
          'latitude': latitude,
          'longitude': 44.18,
          'bearing': 90,
          'observedAtUtc':
              now.add(Duration(seconds: seconds)).toIso8601String(),
        };
    ride.applyMapWatchSnapshot(sample(0, 15.34));
    final approaching = ride.trackingMarkers.single;
    expect(approaching.position, const LatLng(15.34, 44.18));
    expect(approaching.rotation, 90);
    repository.status = 5;
    hub.changes.add(const TrackingHubEvent(
        'rideStatusUpdated', {'rideId': 7, 'rideStatus': 5}));
    await tester.pump();
    expect(ride.trackingMarkers, isEmpty);
    gps.streams.single.add(gps.fix(15.34));
    await tester.pump();
    final inTrip = ride.trackingMarkers.single;
    expect(inTrip.consumeTapEvents, isTrue);
    expect(inTrip.infoWindow, InfoWindow.noText);
    expect(inTrip.icon, isNot(approaching.icon));
    ride.applyMapWatchSnapshot(sample(3, 15.341));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(ride.trackingMarkers.single.position, const LatLng(15.34, 44.19));
    ride.applyMapWatchSnapshot(sample(1, 15.33));
    await tester.pump();
    expect(ride.latestDriverGpsSample!.location.latitude, 15.341);
    Get.delete<RideController>(force: true);
  });

  testWidgets(
      'assigned driver rejects an older target before the next frame and turns by the shortest angle',
      (tester) async {
    await ride.resumeOpenRide('7');
    await tester.pump();
    final now = DateTime.now().toUtc();
    Map<String, Object?> sample(int seconds, double latitude, double heading) =>
        {
          'rideId': 7,
          'driverId': 3,
          'latitude': latitude,
          'longitude': 44.18,
          'bearing': heading,
          'observedAtUtc':
              now.add(Duration(seconds: seconds)).toIso8601String(),
        };
    ride.applyMapWatchSnapshot(sample(0, 15.34, 350));
    ride.applyMapWatchSnapshot(sample(2, 15.341, 10));
    ride.applyMapWatchSnapshot(sample(1, 15.339, 180));
    expect(ride.latestDriverGpsSample!.location.latitude, 15.341);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 325));
    expect(ride.displayedVehicle!.location.latitude, closeTo(15.3405, .00001));
    expect(ride.displayedVehicle!.heading, closeTo(0, .01));
    await tester.pump(const Duration(milliseconds: 325));
    expect(ride.trackedDriver.value!.location.latitude, 15.341);
    await tester.pump(const Duration(seconds: 3));
    expect(ride.trackedDriver.value!.location.latitude, 15.341);
  });

  testWidgets(
      'assigned driver snaps across long outages and large jumps instead of inventing travel',
      (tester) async {
    await ride.resumeOpenRide('7');
    await tester.pump();
    final now = DateTime.now().toUtc();
    Map<String, Object?> sample(int seconds, double latitude) => {
          'rideId': 7,
          'driverId': 3,
          'latitude': latitude,
          'longitude': 44.18,
          'observedAtUtc':
              now.add(Duration(seconds: seconds)).toIso8601String(),
        };
    ride.applyMapWatchSnapshot(sample(0, 15.34));
    ride.applyMapWatchSnapshot(sample(11, 15.341));
    expect(ride.trackedDriver.value!.location.latitude, 15.341);
    ride.applyMapWatchSnapshot(sample(12, 15.35));
    expect(ride.trackedDriver.value!.location.latitude, 15.35);
    await tester.pump(const Duration(seconds: 2));
    expect(ride.trackedDriver.value!.location.latitude, 15.35);
  });

  testWidgets('phase icons rasterize without any icon-font dependency',
      (tester) async {
    final descriptors = await tester.runAsync(() async => [
          await LiveTrackingMarkerIcons.build(inProgress: false),
          await LiveTrackingMarkerIcons.build(inProgress: true),
        ]);
    expect(descriptors, hasLength(2));
    expect(descriptors![0], isNot(descriptors[1]));
  });

  testWidgets(
      'approaching car uses remote GPS then boarded vehicle follows precise local GPS separately',
      (tester) async {
    await ride.resumeOpenRide('7');
    await tester.pump();
    ride.trackingRoutePoints
        .assignAll([const LatLng(15.36, 44.19), const LatLng(15.4, 44.19)]);
    final remoteTime = DateTime.now().toUtc();
    ride.applyMapWatchSnapshot({
      'rideId': 7,
      'driverId': 3,
      'latitude': 15.361,
      'longitude': 44.19,
      'bearing': 0,
      'observedAtUtc': remoteTime.toIso8601String()
    });
    gps.streams.single.add(gps.fix(15.3614));
    await tester.pump();
    expect(ride.displayedVehicle!.location.latitude, 15.361);
    expect(ride.trackedPassenger.value!.latitude, 15.3614);
    expect(ride.vehicleUsesPassengerGps.value, isFalse);
    repository.status = 5;
    await ride.refreshActiveRide();
    gps.streams.single.add(gps.fix(15.3615));
    await tester.pump();
    expect(ride.vehicleUsesPassengerGps.value, isTrue);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 700));
    expect(ride.displayedVehicle!.location.latitude, closeTo(15.3615, .000001));
    expect(ride.latestDriverGpsSample!.location.latitude, 15.361);
    expect(ride.latestDriverGpsSample!.updatedAt, remoteTime);
    expect(ride.trackingMarkers, hasLength(1));
    expect(ride.trackingMarkers.single.position.latitude,
        closeTo(15.3615, .000001));
    gps.streams.single.add(gps.fix(15.38, accuracy: 90));
    await tester.pump();
    expect(ride.vehicleUsesPassengerGps.value, isFalse);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 700));
    expect(ride.displayedVehicle!.location.latitude, 15.3615);
    expect(ride.trackedPassenger.value!.latitude, 15.38);
    Get.delete<RideController>(force: true);
  });

  testWidgets(
      'local navigation expiry retains the last local fix without adopting remote GPS',
      (tester) async {
    repository.status = 5;
    await ride.resumeOpenRide('7');
    await tester.pump();
    ride.applyMapWatchSnapshot({
      'rideId': 7,
      'driverId': 3,
      'latitude': 15.361,
      'longitude': 44.19,
      'bearing': 0,
      'observedAtUtc': DateTime.now().toUtc().toIso8601String()
    });
    gps.streams.single.add(gps.fix(15.3614));
    await tester.pump();
    expect(ride.vehicleUsesPassengerGps.value, isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(ride.vehicleUsesPassengerGps.value, isFalse);
    await tester.pump(const Duration(milliseconds: 700));
    expect(ride.displayedVehicle!.location.latitude, 15.3614);
    expect(ride.trackedPassenger.value!.latitude, 15.3614);
    Get.delete<RideController>(force: true);
  });

  testWidgets('local GPS recovers after expiry while remote GPS remains stale',
      (tester) async {
    repository.status = 5;
    await ride.resumeOpenRide('7');
    await tester.pump();
    ride.trackingRoutePoints
        .assignAll([const LatLng(15.36, 44.19), const LatLng(15.4, 44.19)]);
    final driverTime =
        DateTime.now().toUtc().subtract(const Duration(seconds: 29));
    ride.applyMapWatchSnapshot({
      'rideId': 7,
      'driverId': 3,
      'latitude': 15.361,
      'longitude': 44.19,
      'bearing': 0,
      'observedAtUtc': driverTime.toIso8601String()
    });
    gps.streams.single.add(gps.fix(15.3613));
    await tester.pump();
    expect(ride.vehicleUsesPassengerGps.value, isTrue);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1200)));
    gps.streams.single.add(gps.fix(15.3614));
    await tester.pump();
    expect(ride.vehicleUsesPassengerGps.value, isTrue);
    expect(ride.latestDriverGpsSample!.updatedAt, driverTime);
    await tester.pump(const Duration(seconds: 5));
    expect(ride.vehicleUsesPassengerGps.value, isFalse);
    gps.streams.single.add(gps.fix(15.3615));
    await tester.pump();
    expect(ride.vehicleUsesPassengerGps.value, isTrue);
    ride.applyMapWatchSnapshot({
      'rideId': 7,
      'driverId': 3,
      'latitude': 15.3614,
      'longitude': 44.19,
      'bearing': 0,
      'observedAtUtc': DateTime.now().toUtc().toIso8601String()
    });
    expect(ride.vehicleUsesPassengerGps.value, isTrue);
    ride.prepareNewRide();
    expect(ride.vehicleUsesPassengerGps.value, isFalse);
    expect(ride.displayedVehicle, isNull);
    expect(ride.trackedPassenger.value, isNull);
    Get.delete<RideController>(force: true);
  });

  testWidgets(
      'successive one-second local fixes keep vehicle moving through the full interval',
      (tester) async {
    repository.status = 5;
    await ride.resumeOpenRide('7');
    await tester.pump();
    final now = DateTime.now().toUtc();
    ride.applyMapWatchSnapshot({
      'rideId': 7,
      'driverId': 3,
      'latitude': 15.361,
      'longitude': 44.19,
      'bearing': 0,
      'observedAtUtc': now.toIso8601String()
    });
    gps.streams.single.add(gps.fix(15.3614, observedAt: now));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 700));
    expect(ride.displayedVehicle!.location.latitude, closeTo(15.3614, .000001));
    gps.streams.single
        .add(gps.fix(15.3615, observedAt: now.add(const Duration(seconds: 1))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 800));
    expect(ride.vehicleUsesPassengerGps.value, isTrue);
    expect(ride.displayedVehicle!.location.latitude, greaterThan(15.36147));
    expect(ride.displayedVehicle!.location.latitude, lessThan(15.3615));
    await tester.pump(const Duration(milliseconds: 200));
    expect(ride.displayedVehicle!.location.latitude, closeTo(15.3615, .000001));
    expect(ride.latestDriverGpsSample!.location.latitude, 15.361);
    Get.delete<RideController>(force: true);
  });
  testWidgets(
      'ongoing trip starts locally with no driver GPS and ignores remote jumps',
      (tester) async {
    repository.status = 5;
    await ride.resumeOpenRide('7');
    await tester.pump();
    expect(ride.latestDriverGpsSample, isNull);
    expect(ride.displayedVehicle, isNull);
    gps.streams.single.add(gps.fix(15.37));
    await tester.pump();
    expect(ride.vehicleUsesPassengerGps.value, isTrue);
    expect(ride.displayedVehicle!.location.latitude, 15.37);
    ride.applyMapWatchSnapshot({
      'rideId': 7,
      'driverId': 3,
      'latitude': 16.0,
      'longitude': 45.0,
      'observedAtUtc': DateTime.now().toUtc().toIso8601String()
    });
    await tester.pump(const Duration(seconds: 1));
    expect(ride.displayedVehicle!.location.latitude, 15.37);
    expect(ride.latestVehicleGpsSample!.location.latitude, 15.37);
    expect(ride.latestDriverGpsSample!.location.latitude, 16);
    Get.delete<RideController>(force: true);
  });
  testWidgets(
      'long route geometry stays fixed across vehicle frames and changes with same-length reroute',
      (tester) async {
    await ride.resumeOpenRide('7');
    await tester.pump();
    final now = DateTime.now().toUtc();
    ride.trackingRoutePoints.assignAll(
        List.generate(3000, (i) => LatLng(15.36 + i * .00001, 44.19)));
    ride.applyMapWatchSnapshot({
      'rideId': 7,
      'driverId': 3,
      'latitude': 15.361,
      'longitude': 44.19,
      'observedAtUtc': now.toIso8601String()
    });
    await tester.pump();
    ride.applyMapWatchSnapshot({
      'rideId': 7,
      'driverId': 3,
      'latitude': 15.3612,
      'longitude': 44.19,
      'observedAtUtc': now.add(const Duration(seconds: 1)).toIso8601String()
    });
    await tester.pump();
    final points = ride.remainingTrackingRoutePoints;
    final lines = ride.trackingPolylines;
    final before = ride.displayedVehicle!.location.latitude;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(identical(ride.remainingTrackingRoutePoints, points), isTrue);
      expect(identical(ride.trackingPolylines, lines), isTrue);
    }
    expect(ride.displayedVehicle!.location.latitude, greaterThan(before));
    ride.trackingRoutePoints.assignAll(
        List.generate(3000, (i) => LatLng(15.36 + i * .00001, 44.1901)));
    expect(identical(ride.trackingPolylines, lines), isFalse);
    final replacement = ride.remainingTrackingRoutePoints;
    expect(replacement.last.longitude, 44.1901);
    location.pickup.value = null;
    expect(
        ride.trackingPolylines
            .where((p) => p.polylineId.value == 'selected-route'),
        isEmpty);
    Get.delete<RideController>(force: true);
  });

  testWidgets(
      'local trip keeps smooth bounded frames on a high refresh display and delivers the final fix',
      (tester) async {
    repository.status = 5;
    hub.publishResult = false;
    await ride.resumeOpenRide('7');
    await tester.pump();
    final now = DateTime.now().toUtc();
    gps.streams.single.add(gps.fix(15.37, observedAt: now));
    await tester.pump();
    var frames = 0;
    final updates = ever(ride.trackedVehicle, (_) => frames++);
    gps.streams.single
        .add(gps.fix(15.3701, observedAt: now.add(const Duration(seconds: 1))));
    await tester.pump();
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(frames, inInclusiveRange(15, 31));
    expect(ride.displayedVehicle!.location.latitude, greaterThan(15.37005));
    // The animation clock starts at its first display tick.
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      ride.displayedVehicle!.location.latitude,
      closeTo(15.3701, .0000001),
    );
    expect(ride.latestVehicleGpsSample!.location.latitude, 15.3701);
    expect(ride.vehicleUsesPassengerGps.value, isTrue);
    updates.dispose();
    Get.delete<RideController>(force: true);
  });

  testWidgets(
      'state bursts share reads while GPS and unrelated messages never reload ride',
      (tester) async {
    await ride.resumeOpenRide('7');
    await tester.pump();
    final baseline = repository.detailReads;
    repository.pendingDetail = Completer<void>();
    for (var i = 0; i < 100; i++) {
      hub.changes.add(TrackingHubEvent('rideArrivalUpdated', {'rideId': 7}));
    }
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 130)));
    await tester.pump();
    expect(repository.detailReads, baseline + 1);
    for (var i = 0; i < 100; i++) {
      hub.changes
          .add(TrackingHubEvent('rideRouteChangeUpdated', {'rideId': 7}));
      hub.changes.add(TrackingHubEvent('chatMessageCreated', {'rideId': 7}));
    }
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 130)));
    await tester.pump();
    expect(repository.detailReads, baseline + 1);
    final pending = repository.pendingDetail!;
    repository.pendingDetail = null;
    repository.status = 5;
    pending.complete();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    expect(repository.detailReads, baseline + 2);
    expect(ride.activeRideStatus.value, '5');
    for (var i = 0; i < 100; i++) {
      hub.changes.add(TrackingHubEvent('driverLocationUpdated', {
        'rideId': 7,
        'driverId': 3,
        'latitude': 15.361,
        'longitude': 44.19,
        'observedAtUtc': DateTime.now().toUtc().toIso8601String()
      }));
      hub.changes.add(TrackingHubEvent('chatMessageCreated', {'rideId': 7}));
    }
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 130)));
    await tester.pump();
    expect(repository.detailReads, baseline + 2);
    Get.delete<RideController>(force: true);
  });
}
