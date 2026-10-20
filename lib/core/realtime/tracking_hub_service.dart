import 'dart:async';

import 'package:get/get.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../config/app_environment.dart';
import '../storage/secure_storage_service.dart';

/// Owns the authenticated tracking Hub connection for an active ride.
/// Ride membership is restored after a successful automatic reconnect.
class TrackingHubEvent {
  const TrackingHubEvent(this.name, this.payload);

  final String name;
  final Map<String, Object?> payload;
}

class TrackingHubService extends GetxService {
  TrackingHubService(this._storage);

  final SecureStorageService _storage;
  final Set<int> _rideIds = <int>{};
  final Set<Object> _userEventListeners = <Object>{};
  Map<String, Object?>? _nearbyDriverSubscription;
  HubConnection? _connection;
  Future<void>? _connectTask;
  Timer? _retryTimer;
  int _connectionGeneration = 0;
  final RxBool isConnected = false.obs;
  final StreamController<TrackingHubEvent> _events =
      StreamController<TrackingHubEvent>.broadcast();
  final StreamController<void> _connectionRestored =
      StreamController<void>.broadcast();
  Future<void> Function()? onSessionRevoked;

  Stream<TrackingHubEvent> get events => _events.stream;
  Stream<void> get connectionRestored => _connectionRestored.stream;

  Future<void> setUserEventListening(Object owner, bool listen) async {
    if (listen) {
      _userEventListeners.add(owner);
      await _ensureConnected();
    } else {
      _userEventListeners.remove(owner);
    }
    if (_userEventListeners.isEmpty && _rideIds.isEmpty) {
      await disconnect();
    }
  }

  Future<void> setRideSubscriptions(Iterable<int> rideIds) async {
    final desired = rideIds.where((id) => id > 0).toSet();
    final removed = _rideIds.difference(desired);
    final added = desired.difference(_rideIds);
    _rideIds
      ..clear()
      ..addAll(desired);

    if (_rideIds.isEmpty) {
      for (final rideId in removed) {
        await _invokeIfConnected('LeaveRide', rideId);
      }
      if (_userEventListeners.isEmpty) await disconnect();
      return;
    }

    await _ensureConnected();
    if (!_isConnected) return;
    for (final rideId in removed) {
      await _invokeIfConnected('LeaveRide', rideId);
    }
    for (final rideId in added) {
      await _invokeIfConnected('JoinRide', rideId);
    }
  }

  Future<bool> publishDriverLocation(Map<String, Object?> payload) async {
    await _ensureConnected();
    final connection = _connection;
    if (connection == null ||
        connection.state != HubConnectionState.Connected) {
      return false;
    }
    try {
      await connection.invoke('PublishDriverLocation', args: <Object>[payload]);
      return true;
    } on Object {
      return false;
    }
  }

  /// Sends an authenticated passenger GPS sample for the current active ride.
  /// The server validates the ride ownership, status, timestamp, accuracy,
  /// and movement before forwarding it to the assigned driver and operations.
  Future<bool> publishPassengerLocation(Map<String, Object?> payload) async {
    await _ensureConnected();
    final connection = _connection;
    if (connection == null ||
        connection.state != HubConnectionState.Connected) {
      return false;
    }
    try {
      await connection.invoke(
        'PublishPassengerLocation',
        args: <Object>[payload],
      );
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> setNearbyDriverSubscription({
    required int? serviceKindId,
    required int? serviceCatalogItemId,
    required double pickupLatitude,
    required double pickupLongitude,
    required int radiusMeters,
    required Iterable<int> initialDriverIds,
  }) async {
    _nearbyDriverSubscription = <String, Object?>{
      'serviceKindId': serviceKindId,
      'serviceCatalogItemId': serviceCatalogItemId,
      'pickupLatitude': pickupLatitude,
      'pickupLongitude': pickupLongitude,
      'radiusMeters': radiusMeters,
      'initialDriverIds': initialDriverIds.toSet().take(50).toList(),
    };
    await _ensureConnected();
    await _joinNearbyDriverSubscription(_connection);
  }

  Future<void> clearNearbyDriverSubscription() async {
    _nearbyDriverSubscription = null;
    final connection = _connection;
    if (connection == null ||
        connection.state != HubConnectionState.Connected) {
      return;
    }
    try {
      await connection.invoke('LeaveNearbyDrivers');
    } on Object {
      // Leaving a map subscription must not disrupt the ride screen.
    }
  }

  Future<void> disconnect() async {
    _connectionGeneration++;
    _userEventListeners.clear();
    _retryTimer?.cancel();
    _retryTimer = null;
    _rideIds.clear();
    final connection = _connection;
    _connection = null;
    isConnected.value = false;
    if (connection != null &&
        connection.state != HubConnectionState.Disconnected) {
      try {
        await connection.stop();
      } on Object {
        // A failed or already-closed transport should not block sign-out.
      }
    }
  }

  bool get _isConnected => _connection?.state == HubConnectionState.Connected;

  Future<void> _ensureConnected() async {
    if (_isConnected) return;
    final pending = _connectTask;
    if (pending != null) {
      await pending;
      return;
    }

    final task = _startConnection();
    _connectTask = task;
    try {
      await task;
    } finally {
      if (identical(_connectTask, task)) _connectTask = null;
    }
  }

  Future<void> _startConnection() async {
    final generation = _connectionGeneration;
    final url = AppEnvironment.signalRHubUrl.trim();
    if (url.isEmpty) return;

    final connection = HubConnectionBuilder()
        .withUrl(
      url,
      options: HttpConnectionOptions(
        accessTokenFactory: () async => await _storage.accessToken ?? '',
      ),
    )
        .withAutomaticReconnect(
      retryDelays: <int>[0, 2000, 10000, 30000],
    ).build();
    _connection = connection;
    connection.on('sessionRevoked', (_) {
      unawaited(_handleSessionRevoked());
    });
    for (final eventName in <String>[
      'rideAvailable',
      'rideUnavailable',
      'offerReceived',
      'offerUpdated',
      'rideRequestViewed',
      'rideStatusUpdated',
      'rideMessageCreated',
      'paymentUpdated',
      'cashApprovalUpdated',
      'notificationCreated',
      'driverLocationUpdated',
      'passengerLocationUpdated',
      'nearbyDriverLocationUpdated',
      'nearbyDriverAvailabilityChanged',
    ]) {
      connection.on(eventName, (arguments) {
        if (arguments == null || arguments.isEmpty) return;
        final rawPayload = arguments.first;
        if (rawPayload is! Map) return;
        final payload = <String, Object?>{};
        rawPayload.forEach((key, value) {
          if (key != null) payload[key.toString()] = value;
        });
        _events.add(TrackingHubEvent(eventName, payload));
      });
    }
    connection.onreconnecting(({Exception? error}) {
      isConnected.value = false;
    });
    connection.onreconnected(({String? connectionId}) {
      isConnected.value = true;
      unawaited(_restoreSubscriptionsAndNotify(connection));
    });
    connection.onclose(({Exception? error}) {
      isConnected.value = false;
      if (identical(_connection, connection)) {
        _connection = null;
        _scheduleReconnect();
      }
    });

    try {
      await connection.start();
      if (generation != _connectionGeneration) {
        await connection.stop();
        return;
      }
      _retryTimer?.cancel();
      _retryTimer = null;
      isConnected.value = connection.state == HubConnectionState.Connected;
      if (_isConnected) await _restoreSubscriptionsAndNotify(connection);
    } on Object {
      if (identical(_connection, connection)) _connection = null;
      isConnected.value = false;
      _scheduleReconnect();
    }
  }

  Future<void> _restoreRideSubscriptions(HubConnection connection) async {
    if (!identical(_connection, connection) ||
        connection.state != HubConnectionState.Connected) {
      return;
    }
    for (final rideId in _rideIds.toList(growable: false)) {
      try {
        await connection.invoke('JoinRide', args: <Object>[rideId]);
      } on Object {
        // Reconnecting the transport must not interrupt the ride screen.
      }
    }
  }

  Future<void> _restoreSubscriptionsAndNotify(HubConnection connection) async {
    await _restoreRideSubscriptions(connection);
    await _joinNearbyDriverSubscription(connection);
    if (identical(_connection, connection) &&
        connection.state == HubConnectionState.Connected) {
      _connectionRestored.add(null);
    }
  }

  Future<void> _joinNearbyDriverSubscription(
    HubConnection? connection,
  ) async {
    final subscription = _nearbyDriverSubscription;
    if (subscription == null ||
        connection == null ||
        connection.state != HubConnectionState.Connected) {
      return;
    }
    try {
      await connection.invoke(
        'JoinNearbyDrivers',
        args: <Object>[subscription],
      );
    } on Object {
      // The REST nearby-driver snapshot stays visible if the map join fails.
    }
  }

  Future<void> _invokeIfConnected(String method, int rideId) async {
    final connection = _connection;
    if (connection == null ||
        connection.state != HubConnectionState.Connected) {
      return;
    }
    try {
      await connection.invoke(method, args: <Object>[rideId]);
    } on Object {
      // Live updates are supplemental; REST snapshots remain available.
    }
  }

  Future<void> _handleSessionRevoked() async {
    final handler = onSessionRevoked;
    if (handler != null) {
      await handler();
    } else {
      await disconnect();
    }
  }

  void _scheduleReconnect() {
    if (_rideIds.isEmpty && _userEventListeners.isEmpty) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 15), () {
      if (_rideIds.isNotEmpty || _userEventListeners.isNotEmpty) {
        unawaited(_ensureConnected());
      }
    });
  }
}
