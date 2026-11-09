import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

import '../../features/ride/models/ride_models.dart';

/// One GPS-centered presence feed shared by every visible discovery map.
/// Map camera/booking coordinates never enter this feed.
class NearbyDriverPresence {
  NearbyDriverPresence({
    required this.drivers,
    required this.load,
    required this.subscribe,
    required this.unsubscribe,
    required this.onDriver,
    required this.onChanged,
    required this.canRequest,
    Future<bool> Function()? requestLocationAccess,
    Future<Position> Function()? readPosition,
    Stream<Position> Function()? positionStream,
    DateTime Function()? now,
  })  : _requestLocationAccess = requestLocationAccess,
        _readPosition = readPosition ?? _currentPosition,
        _positionStream = positionStream ?? _positions,
        _now = now ?? DateTime.now;

  static const radiusMeters = 3000.0;
  static const driverFreshness = Duration(minutes: 5);
  final RxList<NearbyDriver> drivers;
  final Future<List<NearbyDriver>> Function(RideCoordinate center) load;
  final Future<void> Function(RideCoordinate center, List<NearbyDriver> drivers)
      subscribe;
  final Future<void> Function() unsubscribe;
  final void Function(NearbyDriver driver) onDriver;
  final void Function() onChanged;
  final bool Function() canRequest;
  final Future<bool> Function()? _requestLocationAccess;
  final Future<Position> Function() _readPosition;
  final Stream<Position> Function() _positionStream;
  final DateTime Function() _now;
  final Rxn<RideCoordinate> riderPosition = Rxn<RideCoordinate>();
  final Set<Object> _owners = {};
  final Map<String, NearbyDriver> _targets = {};
  final Map<String, DateTime> _seenAt = {};
  final Map<String, DateTime> _latestObservedAt = {};
  final Map<String, DateTime> _removedAt = {};
  final Map<String, int> _eventVersions = {};
  final Map<String, _DriverMotion> _motions = {};
  StreamSubscription<Position>? _gps;
  Timer? _refreshTimer;
  Timer? _motionTimer;
  int _generation = 0;
  int _eventVersion = 0;
  int _requestVersion = 0;
  bool _foreground = true;
  bool _disposed = false;
  bool _requesting = false;
  bool _refreshQueued = false;
  bool _openingGps = false;
  bool _readingPosition = false;
  bool _permissionRequested = false;
  DateTime? _positionAt;
  Position? _latestPosition;
  RideCoordinate? _queriedCenter;

  bool get active => !_disposed && _foreground && _owners.isNotEmpty;

  /// The request audit uses a recent native fix, never the editable pickup.
  /// Preserve its capture time even when the booking map has just been hidden.
  Position? get requestPosition {
    final position = _latestPosition;
    if (_disposed || !_foreground || position == null) return null;
    final age = _now().toUtc().difference(position.timestamp.toUtc());
    if (position.accuracy > 75 ||
        age > const Duration(minutes: 2) ||
        age < const Duration(seconds: -5)) return null;
    return position;
  }

  Future<bool> _locationAccess() async {
    if (_requestLocationAccess != null) return _requestLocationAccess();
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && !_permissionRequested) {
      _permissionRequested = true;
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<Position> _currentPosition() => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

  static Stream<Position> _positions() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
      );

  void setMapVisible(Object owner, bool visible) {
    final wasActive = active;
    visible ? _owners.add(owner) : _owners.remove(owner);
    _syncActivity(wasActive);
  }

  void setForeground(bool foreground) {
    final wasActive = active;
    _foreground = foreground;
    _syncActivity(wasActive);
  }

  void _syncActivity(bool wasActive) {
    if (active == wasActive) return;
    if (!active) {
      _stop();
      return;
    }
    final generation = ++_generation;
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _prune();
      if (_gps == null) unawaited(_openGps(generation));
      if (_positionAt == null ||
          _now().toUtc().difference(_positionAt!) >
              const Duration(seconds: 45)) {
        unawaited(_readFix(generation));
      }
      unawaited(refresh());
    });
    unawaited(_openGps(generation));
  }

  Future<void> _openGps(int generation) async {
    if (_openingGps || !active || generation != _generation || _gps != null) {
      return;
    }
    _openingGps = true;
    try {
      if (!await _locationAccess() || !active || generation != _generation)
        return;
      // Subscribe before reading the one-shot sample, so a slow first fix
      // cannot discard movement that the native stream has already delivered.
      _gps = _positionStream().listen(
        (position) {
          if (active && generation == _generation) acceptPosition(position);
        },
        onError: (Object _) {
          if (generation != _generation) return;
          unawaited(_gps?.cancel());
          _gps = null;
        },
        onDone: () {
          if (generation == _generation) _gps = null;
        },
      );
      await _readFix(generation);
    } on Object {
      // The visible-map timer retries permission/provider setup after recovery.
    } finally {
      _openingGps = false;
      if (active && generation != _generation && _gps == null) {
        unawaited(_openGps(_generation));
      }
    }
  }

  Future<void> _readFix(int generation) async {
    if (_readingPosition || !active || _gps == null) return;
    _readingPosition = true;
    try {
      final position =
          await _readPosition().timeout(const Duration(seconds: 9));
      if (active && generation == _generation) acceptPosition(position);
    } on Object {
      // Keep using the native stream when a one-shot fix is unavailable.
    } finally {
      _readingPosition = false;
      if (active && generation != _generation) unawaited(_readFix(_generation));
    }
  }

  void acceptPosition(Position position) {
    if (!active || !_validCoordinates(position.latitude, position.longitude)) {
      return;
    }
    final timestamp = position.timestamp.toUtc();
    final age = _now().toUtc().difference(timestamp);
    if (!position.accuracy.isFinite ||
        position.accuracy <= 0 ||
        position.accuracy > 500 ||
        age > const Duration(minutes: 2) ||
        age < const Duration(seconds: -30) ||
        (_positionAt != null && timestamp.isBefore(_positionAt!))) return;
    _positionAt = timestamp;
    _latestPosition = position;
    final center = RideCoordinate(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    riderPosition.value = center;
    _prune();
    if (_queriedCenter == null || _distance(_queriedCenter!, center) >= 50) {
      _requestVersion++;
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    final center = riderPosition.value;
    if (!active ||
        !canRequest() ||
        center == null ||
        _positionAt == null ||
        _now().toUtc().difference(_positionAt!) > const Duration(minutes: 2)) {
      _prune();
      return;
    }
    if (_requesting) {
      _refreshQueued = true;
      return;
    }
    _requesting = true;
    _queriedCenter = center;
    final generation = _generation;
    final version = ++_requestVersion;
    final eventVersion = _eventVersion;
    try {
      final snapshot = await load(center).timeout(const Duration(seconds: 12));
      if (!active || generation != _generation || version != _requestVersion) {
        return;
      }
      final next = {for (final driver in snapshot) driver.id: driver};
      // An event received after this HTTP read started wins over its snapshot,
      // including an unavailable tombstone that must not reappear.
      for (final id in _eventVersions.keys.toList()) {
        if (_eventVersions[id]! <= eventVersion) continue;
        final current = _targets[id];
        current == null ? next.remove(id) : next[id] = current;
      }
      for (final id in _targets.keys.toList()) {
        if (!next.containsKey(id)) {
          _removedAt[id] = _now().toUtc();
          _remove(id);
        }
      }
      for (final driver in next.values) {
        _acceptDriver(driver, fromSnapshot: true);
      }
      _prune();
      // REST visibility must never wait for a slow or disconnected Hub join.
      unawaited(subscribe(center, _targets.values.toList())
          .catchError((Object _) {}));
    } on Object {
      // Keep fresh markers through a brief outage. Missing/offline drivers are
      // removed by the next canonical read, removal event or freshness timer.
      _prune();
    } finally {
      _requesting = false;
      if (_refreshQueued && active) {
        _refreshQueued = false;
        unawaited(refresh());
      }
    }
  }

  void receiveDriver(NearbyDriver driver) {
    if (!active) return;
    final observedAt = driver.observedAt;
    final latest = _latestObservedAt[driver.id];
    final removedAt = _removedAt[driver.id];
    if ((latest != null && observedAt != null && !observedAt.isAfter(latest)) ||
        (removedAt != null &&
            (observedAt == null || !observedAt.isAfter(removedAt)))) return;
    _eventVersions[driver.id] = ++_eventVersion;
    _acceptDriver(driver);
  }

  void removeDriver(String id) {
    if (!active) return;
    _eventVersions[id] = ++_eventVersion;
    _removedAt[id] = _now().toUtc();
    _remove(id);
  }

  void _acceptDriver(NearbyDriver driver, {bool fromSnapshot = false}) {
    final timestamp = driver.observedAt?.toUtc() ?? _now().toUtc();
    final previous = _targets[driver.id];
    final latest = _latestObservedAt[driver.id];
    if (latest != null && timestamp.isBefore(latest)) return;
    _latestObservedAt[driver.id] = timestamp;
    if (fromSnapshot) _removedAt.remove(driver.id);
    if (!_isVisible(driver) ||
        _now().toUtc().difference(timestamp) > driverFreshness ||
        timestamp.difference(_now().toUtc()) > const Duration(seconds: 30)) {
      _remove(driver.id);
      return;
    }
    _targets[driver.id] = driver;
    _seenAt[driver.id] = timestamp;
    final index = drivers.indexWhere((item) => item.id == driver.id);
    final current = index < 0 ? null : drivers[index];
    final gap = driver.observedAt != null && previous?.observedAt != null
        ? driver.observedAt!.difference(previous!.observedAt!).inMilliseconds
        : 1200;
    if (current == null ||
        gap > 10000 ||
        _distance(current.location, driver.location) > 250) {
      _motions.remove(driver.id);
      _display(driver);
    } else if (_distance(current.location, driver.location) > .5) {
      _motions[driver.id] = _DriverMotion(current, driver, _now(),
          Duration(milliseconds: gap.clamp(300, 1500)));
      _motionTimer ??=
          Timer.periodic(const Duration(milliseconds: 40), (_) => _tick());
    } else {
      _motions.remove(driver.id);
      _display(driver);
    }
    onDriver(driver);
  }

  void _tick() {
    for (final entry in _motions.entries.toList()) {
      final motion = entry.value;
      final t = (_now().difference(motion.startedAt).inMilliseconds /
              motion.duration.inMilliseconds)
          .clamp(0.0, 1.0);
      _display(t >= 1 ? motion.to : motion.frame(t));
      if (t >= 1) _motions.remove(entry.key);
    }
    if (_motions.isEmpty) {
      _motionTimer?.cancel();
      _motionTimer = null;
    }
  }

  void _display(NearbyDriver driver) {
    final index = drivers.indexWhere((item) => item.id == driver.id);
    index < 0 ? drivers.add(driver) : drivers[index] = driver;
    onChanged();
  }

  void _remove(String id) {
    _targets.remove(id);
    _seenAt.remove(id);
    _motions.remove(id);
    drivers.removeWhere((driver) => driver.id == id);
    onChanged();
  }

  bool _isVisible(NearbyDriver driver) {
    final center = riderPosition.value;
    return center != null &&
        driver.isAvailable &&
        _validCoordinates(
            driver.location.latitude, driver.location.longitude) &&
        _distance(center, driver.location) <= radiusMeters;
  }

  void _prune() {
    for (final driver in _targets.values.toList()) {
      if (!_isVisible(driver) ||
          _now().toUtc().difference(_seenAt[driver.id]!) > driverFreshness) {
        _remove(driver.id);
      }
    }
  }

  void reset() {
    _requestVersion++;
    _targets.clear();
    _seenAt.clear();
    _latestObservedAt.clear();
    _removedAt.clear();
    _eventVersions.clear();
    _motions.clear();
    _motionTimer?.cancel();
    _motionTimer = null;
    drivers.clear();
    onChanged();
    if (active) unawaited(refresh());
  }

  void _stop() {
    _generation++;
    _requestVersion++;
    _queriedCenter = null;
    _refreshQueued = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    unawaited(_gps?.cancel());
    _gps = null;
    reset();
    unawaited(unsubscribe().catchError((Object _) {}));
  }

  void dispose() {
    _disposed = true;
    _owners.clear();
    _stop();
  }

  static bool _validCoordinates(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      (latitude != 0 || longitude != 0);

  static double _distance(RideCoordinate a, RideCoordinate b) =>
      Geolocator.distanceBetween(
          a.latitude, a.longitude, b.latitude, b.longitude);
}

class _DriverMotion {
  const _DriverMotion(this.from, this.to, this.startedAt, this.duration);
  final NearbyDriver from;
  final NearbyDriver to;
  final DateTime startedAt;
  final Duration duration;

  NearbyDriver frame(double progress) {
    final a = from.heading, b = to.heading;
    final heading = a == null || b == null
        ? b ?? a
        : (a + (((b - a + 540) % 360) - 180) * progress + 360) % 360;
    return NearbyDriver(
      id: to.id,
      name: to.name,
      photoUrl: to.photoUrl,
      vehicleType: to.vehicleType,
      rating: to.rating,
      vehicleModel: to.vehicleModel,
      plateNumber: to.plateNumber,
      completedTrips: to.completedTrips,
      isAvailable: to.isAvailable,
      observedAt: to.observedAt,
      heading: heading,
      location: RideCoordinate(
        latitude: from.location.latitude +
            (to.location.latitude - from.location.latitude) * progress,
        longitude: from.location.longitude +
            (to.location.longitude - from.location.longitude) * progress,
      ),
    );
  }
}
