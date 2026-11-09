import 'dart:math' as math;

import 'ride_models.dart';

/// A short catch-up window keeps the live symbol near the newest actual fix.
/// No extrapolation is used after an interruption or while the car is stopped.
abstract final class TrackedDriverMotion {
  static Duration duration(Duration sampleGap) => Duration(
      milliseconds: (sampleGap.inMilliseconds * .65).round().clamp(120, 650));

  /// Native navigation samples arrive every second. Fill that interval while
  /// keeping the remote transport's shorter catch-up window independent.
  static Duration localDuration(Duration sampleGap) =>
      Duration(milliseconds: sampleGap.inMilliseconds.clamp(120, 1000));

  static double? heading(
      DriverTrackingSnapshot? previous, DriverTrackingSnapshot next) {
    // The driver transport only includes a bearing when movement is reliable.
    // It also covers valid one-meter simulation steps and slow turns.
    final supplied = _validHeading(next.heading);
    if (supplied != null) return supplied;
    if (previous == null || previous.driverId != next.driverId) {
      return null;
    }
    final from = previous.location;
    final to = next.location;
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final deltaLng = (to.longitude - from.longitude) * math.pi / 180;
    final north = (lat2 - lat1) * 6371000;
    final east = deltaLng * math.cos((lat1 + lat2) / 2) * 6371000;
    final distance = math.sqrt(north * north + east * east);
    // Without a bearing, do not turn the marker on small position noise.
    if (distance >= 5) {
      final y = math.sin(deltaLng) * math.cos(lat2);
      final x = math.cos(lat1) * math.sin(lat2) -
          math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
      return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    }
    return _validHeading(previous.heading);
  }

  static double? _validHeading(double? value) =>
      value != null && value.isFinite && value >= 0 && value < 360
          ? value
          : null;
}
