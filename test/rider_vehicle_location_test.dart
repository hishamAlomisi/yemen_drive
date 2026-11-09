import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yemen_drive/features/ride/models/rider_vehicle_location.dart';
import 'package:yemen_drive/features/ride/models/tracked_driver_motion.dart';

void main() {
  final now = DateTime.utc(2026, 11, 6, 20);
  Position fix({double latitude = 15.361, double accuracy = 8, int age = 0}) =>
      Position(
          latitude: latitude,
          longitude: 44.19,
          timestamp: now.subtract(Duration(seconds: age)),
          accuracy: accuracy,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 1,
          speed: 12,
          speedAccuracy: 1);
  bool eligible(Position position, {Position? previous}) =>
      RiderVehicleLocation.canUse(
          position: position, now: now, previousPassengerPosition: previous);
  test('fresh precise local fix needs no driver identity or planned route', () {
    expect(eligible(fix()), isTrue);
    expect(eligible(fix(latitude: 15.38)), isTrue);
  });
  test('poor, stale, future and invalid fixes are rejected', () {
    for (final point in [
      fix(accuracy: 36),
      fix(accuracy: double.nan),
      fix(age: 5),
      fix(age: -3),
      fix(latitude: double.nan),
      fix(latitude: 91)
    ]) {
      expect(eligible(point), isFalse);
    }
  });
  test('continuous motion rejects jumps and reversed timestamps', () {
    final previous = fix(age: 1);
    expect(eligible(fix(latitude: 15.3612), previous: previous), isTrue);
    expect(eligible(fix(latitude: 15.38), previous: previous), isFalse);
    expect(eligible(fix(age: 2), previous: previous), isFalse);
  });
  test('GPS reacquisition needs no fresh driver anchor', () {
    expect(eligible(fix(latitude: 15.38), previous: fix(age: 10)), isTrue);
  });
  test(
      'local animation fills a second while remote transport catches up sooner',
      () {
    expect(TrackedDriverMotion.localDuration(const Duration(seconds: 1)),
        const Duration(seconds: 1));
    expect(TrackedDriverMotion.duration(const Duration(seconds: 1)),
        const Duration(milliseconds: 650));
    expect(TrackedDriverMotion.localDuration(const Duration(seconds: 3)),
        const Duration(seconds: 1));
    expect(TrackedDriverMotion.localDuration(const Duration(milliseconds: 20)),
        const Duration(milliseconds: 120));
  });
}
