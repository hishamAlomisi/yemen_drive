import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Validates native passenger fixes independently of the driver transport.
/// An ongoing trip remains usable when remote GPS is delayed or the vehicle
/// deviates from its planned route.
abstract final class RiderVehicleLocation {
  static bool canUse({
    required Position position,
    required DateTime now,
    Position? previousPassengerPosition,
  }) {
    final age = now.toUtc().difference(position.timestamp.toUtc());
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        position.latitude.abs() > 90 ||
        position.longitude.abs() > 180 ||
        !position.accuracy.isFinite ||
        position.accuracy <= 0 ||
        position.accuracy > 35 ||
        age > const Duration(seconds: 4) ||
        age < const Duration(seconds: -2)) return false;
    final previous = previousPassengerPosition;
    if (previous != null) {
      final gap =
          position.timestamp.toUtc().difference(previous.timestamp.toUtc());
      if (gap.isNegative) return false;
      // Reacquisition after an interruption needs no remote driver anchor.
      if (gap > const Duration(seconds: 4)) return true;
      final speed = position.speed.isFinite && position.speed >= 0
          ? position.speed.clamp(0.0, 55.0)
          : 15.0;
      final previousSpeed = previous.speed.isFinite && previous.speed >= 0
          ? previous.speed.clamp(0.0, 55.0)
          : 15.0;
      final stepAllowance = gap == Duration.zero
          ? 1.0
          : (30 +
                  math.max(speed, previousSpeed) *
                      gap.inMilliseconds /
                      1000 *
                      1.5)
              .clamp(30.0, 120.0);
      if (Geolocator.distanceBetween(position.latitude, position.longitude,
              previous.latitude, previous.longitude) >
          stepAllowance) return false;
    }
    return true;
  }
}
