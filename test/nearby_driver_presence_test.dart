import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/core/realtime/nearby_driver_presence.dart';
import 'package:yemen_drive/features/ride/models/ride_models.dart';

class _Harness {
  DateTime now = DateTime.utc(2026, 11, 4, 12);
  final drivers = <NearbyDriver>[].obs;
  final streams = <StreamController<Position>>[];
  final centers = <RideCoordinate>[];
  final joins = <RideCoordinate>[];
  int leaves = 0, reads = 0;
  bool online = true;
  List<NearbyDriver> snapshot = [];
  Completer<List<NearbyDriver>>? pending;
  Completer<void>? pendingJoin;
  late final presence = NearbyDriverPresence(
    drivers: drivers,
    canRequest: () => online,
    load: (center) async {
      centers.add(center);
      return pending?.future ?? snapshot;
    },
    subscribe: (center, _) async {
      joins.add(center);
      await pendingJoin?.future;
    },
    unsubscribe: () async {
      leaves++;
    },
    onDriver: (_) {},
    onChanged: () {},
    requestLocationAccess: () async => true,
    readPosition: () async {
      reads++;
      return fix(15.36);
    },
    positionStream: () {
      final stream = StreamController<Position>.broadcast(sync: true);
      streams.add(stream);
      return stream.stream;
    },
    now: () => now,
  );

  Position fix(double latitude, {DateTime? observedAt, double accuracy = 8}) => Position(
        latitude: latitude,
        longitude: 44.19,
        timestamp: observedAt ?? now,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  NearbyDriver driver(
          {String id = '3',
          double latitude = 15.361,
          int age = 0,
          double heading = 0,
          bool available = true}) =>
      NearbyDriver(
        id: id,
        name: 'driver $id',
        location: RideCoordinate(latitude: latitude, longitude: 44.19),
        photoUrl: '',
        vehicleType: RideVehicleType.car,
        rating: 4.8,
        observedAt: now.subtract(Duration(seconds: age)),
        heading: heading,
        isAvailable: available,
      );

  Future<void> close() async {
    presence.dispose();
    for (final stream in streams) {
      await stream.close();
    }
  }
}

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  void presenceTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await h.close();
      }
    });
  }

  presenceTest(
      'request GPS preserves capture time and omits stale or imprecise samples',
      (tester) async {
    h.presence.setMapVisible('review', true);
    await tester.pump();
    expect(h.presence.requestPosition!.latitude, 15.36);
    final observed = h.presence.requestPosition!.timestamp;
    h.presence.setMapVisible('review', false);
    expect(h.presence.requestPosition!.timestamp, observed);
    h.now = h.now.add(const Duration(seconds: 121));
    expect(h.presence.requestPosition, isNull);
    h.presence.setMapVisible('review', true);
    await tester.pump();
    h.presence.acceptPosition(h.fix(15.361, accuracy: 100));
    expect(h.presence.requestPosition, isNull);
    h.presence.acceptPosition(h.fix(15.362,
        observedAt: h.now.add(const Duration(seconds: 6))));
    expect(h.presence.requestPosition, isNull);
    h.presence.setForeground(false);
    expect(h.presence.requestPosition, isNull);
  });

  presenceTest(
      'first visible map reads actual GPS and shows REST markers without waiting for Hub',
      (tester) async {
    h.snapshot = [h.driver()];
    h.pendingJoin = Completer<void>();
    h.presence.setMapVisible('home', true);
    await tester.pump();
    expect(h.drivers.single.id, '3');
    expect(h.centers.single.latitude, 15.36);
    expect(h.joins.single.latitude, 15.36);
    expect(h.streams, hasLength(1));
    h.pendingJoin!.complete();
  });

  presenceTest(
      'map owners share GPS, hidden routes stop it, and returning map reloads',
      (tester) async {
    h.snapshot = [h.driver()];
    h.presence.setMapVisible('home', true);
    h.presence.setMapVisible('review', true);
    await tester.pump();
    expect(h.streams, hasLength(1));
    h.presence.setMapVisible('home', false);
    expect(h.drivers, hasLength(1));
    h.presence.setMapVisible('review', false);
    expect(h.drivers, isEmpty);
    expect(h.leaves, 1);
    h.snapshot = [h.driver(id: '4')];
    h.presence.setMapVisible('home', true);
    await tester.pump();
    expect(h.streams, hasLength(2));
    expect(h.drivers.single.id, '4');
  });

  presenceTest(
      'HTTP failure recovers by periodic canonical read and removes absent drivers',
      (tester) async {
    h.snapshot = [h.driver()];
    h.presence.setMapVisible('map', true);
    await tester.pump();
    h.online = false;
    h.snapshot = [h.driver(id: '4')];
    await h.presence.refresh();
    expect(h.drivers.single.id, '3');
    h.online = true;
    h.now = h.now.add(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 15));
    expect(h.drivers.single.id, '4');
  });

  presenceTest('movement supersedes a pending old-center query',
      (tester) async {
    h.pending = Completer<List<NearbyDriver>>();
    h.presence.setMapVisible('map', true);
    await tester.pump();
    final pending = h.pending!;
    h.pending = null;
    h.now = h.now.add(const Duration(seconds: 2));
    h.snapshot = [h.driver(id: '4', latitude: 15.372)];
    h.streams.single.add(h.fix(15.371));
    pending.complete([h.driver(id: 'old', latitude: 15.36)]);
    await tester.pump();
    expect(h.centers.last.latitude, 15.371);
    expect(h.drivers.single.id, '4');
  });

  presenceTest(
      'late response after map closes never restores drivers or subscription',
      (tester) async {
    h.pending = Completer<List<NearbyDriver>>();
    h.presence.setMapVisible('map', true);
    await tester.pump();
    h.presence.setMapVisible('map', false);
    h.pending!.complete([h.driver()]);
    await tester.pump();
    expect(h.drivers, isEmpty);
    expect(h.joins, isEmpty);
  });

  presenceTest('removal event wins over a snapshot already in flight',
      (tester) async {
    h.snapshot = [h.driver()];
    h.presence.setMapVisible('map', true);
    await tester.pump();
    h.pending = Completer<List<NearbyDriver>>();
    final refresh = h.presence.refresh();
    h.presence.removeDriver('3');
    h.pending!.complete([h.driver()]);
    await refresh;
    expect(h.drivers, isEmpty);
    h.presence.receiveDriver(h.driver());
    expect(h.drivers, isEmpty,
        reason: 'a delayed location cannot undo removal');
    h.pending = null;
    h.now = h.now.add(const Duration(seconds: 2));
    h.snapshot = [h.driver(age: 2)];
    await h.presence.refresh();
    expect(h.drivers.single.id, '3',
        reason: 'a later canonical snapshot can confirm availability again');
  });

  presenceTest(
      'new driver fixes interpolate only between received coordinates and reject older targets',
      (tester) async {
    h.snapshot = [h.driver(heading: 350)];
    h.presence.setMapVisible('map', true);
    await tester.pump();
    h.now = h.now.add(const Duration(seconds: 2));
    h.presence.receiveDriver(h.driver(latitude: 15.362, heading: 10));
    h.presence.receiveDriver(h.driver(latitude: 15.35, age: 1));
    expect(h.drivers.single.location.latitude, 15.361);
    h.now = h.now.add(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 750));
    expect(h.drivers.single.location.latitude, closeTo(15.3615, .00001));
    expect(h.drivers.single.heading, closeTo(0, .01));
    h.now = h.now.add(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 750));
    expect(h.drivers.single.location.latitude, 15.362);
    h.now = h.now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(h.drivers.single.location.latitude, 15.362,
        reason: 'no extrapolation after the last actual GPS sample');
  });

  presenceTest('out-of-radius, unavailable, and stale drivers are removed',
      (tester) async {
    h.snapshot = [
      h.driver(),
      h.driver(id: 'far', latitude: 16),
      h.driver(id: 'old', age: 301),
      h.driver(id: 'off', available: false)
    ];
    h.presence.setMapVisible('map', true);
    await tester.pump();
    expect(h.drivers.map((e) => e.id), ['3']);
    h.now = h.now.add(const Duration(seconds: 2));
    h.presence.receiveDriver(h.driver(latitude: 16));
    expect(h.drivers, isEmpty);
    h.presence.receiveDriver(h.driver(id: 'fresh'));
    expect(h.drivers, hasLength(1));
    h.online = false;
    h.now = h.now.add(const Duration(minutes: 6));
    await tester.pump(const Duration(seconds: 15));
    expect(h.drivers, isEmpty);
  });

  presenceTest(
      'background suspends discovery and stationary GPS is refreshed on return',
      (tester) async {
    h.snapshot = [h.driver()];
    h.presence.setMapVisible('map', true);
    await tester.pump();
    h.presence.setForeground(false);
    h.now = h.now.add(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 45));
    expect(h.centers, hasLength(1));
    h.snapshot = [h.driver(id: 'new')];
    h.presence.setForeground(true);
    await tester.pump();
    expect(h.drivers.single.id, 'new');
    final reads = h.reads;
    h.now = h.now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 60));
    expect(h.reads, greaterThan(reads));
  });
}
