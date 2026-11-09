import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../config/app_environment.dart';
import '../storage/secure_storage_service.dart';
import '../network/api_client.dart';
import '../services/startup_connection_service.dart';
import 'state_change_coordinator.dart';

/// Owns the authenticated tracking Hub connection for an active ride.
/// Ride membership is restored after a successful automatic reconnect.
class TrackingHubEvent {
  const TrackingHubEvent(this.name, this.payload);

  final String name;
  final Map<String, Object?> payload;
}

class TrackingHubService extends GetxService {
  final math.Random _retryRandom = math.Random();
  void _invalidatePendingReads() {
    if (Get.isRegistered<ApiClient>())
      Get.find<ApiClient>().invalidatePendingReads();
  }

  TrackingHubService(this._storage) {
    stateChanges = StateChangeCoordinator(onStatusChanged: () {
      isStateSynchronized.value =
          supportsStateRecovery.value && stateChanges.synchronized;
    });
  }

  final SecureStorageService _storage;
  StreamSubscription<void>? _apiRecovery;
  Worker? _apiAvailabilityWorker;
  final Set<int> _rideIds = <int>{};
  final Set<Object> _userEventListeners = <Object>{};
  Map<String, Object?>? _nearbyDriverSubscription;
  HubConnection? _connection;
  bool _foreground = true;
  bool get _hasInterest =>
      _rideIds.isNotEmpty ||
      _userEventListeners.isNotEmpty ||
      _nearbyDriverSubscription != null;
  StartupConnectionService? get _availability =>
      Get.isRegistered<StartupConnectionService>()
          ? Get.find<StartupConnectionService>()
          : null;

  @override
  void onInit() {
    super.onInit();
    final availability = _availability;
    if (availability != null) {
      _apiRecovery = availability.recovered.listen((_) {
        unawaited(reconnectAfterApiRecovery());
      });
      _apiAvailabilityWorker =
          ever(availability.runtimeUnavailable, (bool unavailable) {
        if (unavailable) {
          unawaited(_suspendForApiOutage());
        }
      });
    }
  }

  Future<void> _suspendForApiOutage() async {
    // Keep subscriptions and state cursors, but stop SignalR's internal retries.
    _connectionGeneration++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stateRecoveryRetry?.cancel();
    _stateRecoveryTask = null;
    _connectTask = null;
    stateChanges.disconnected();
    final previous = _connection;
    _connection = null;
    isConnected.value = false;
    if (previous != null) {
      try {
        await previous.stop().timeout(const Duration(seconds: 3));
      } on Object {
        /* The gate remains closed until an explicit retry succeeds. */
      }
    }
  }

  Future<void> setForeground(bool foreground) async {
    final resumed = foreground && !_foreground;
    _foreground = foreground;
    if (!foreground) {
      stateChanges.disconnected();
      _stateRecoveryTask = null;
    }
    if (_connection?.state != HubConnectionState.Connected) {
      if (resumed && _hasInterest) await _ensureConnected();
      return;
    }
    try {
      await _connection!.invoke('SetForeground', args: <Object>[foreground]);
    } on Object {/* Reconnect restores presence. */}
    if (resumed) await recoverState();
  }

  Future<void>? _connectTask;
  Timer? _retryTimer;
  int _connectionGeneration = 0;
  final RxBool isConnected = false.obs;
  final RxBool supportsStateRecovery = false.obs;
  final RxBool isStateSynchronized = false.obs;
  late final StateChangeCoordinator stateChanges;
  Future<void>? _stateRecoveryTask;
  Timer? _stateRecoveryRetry;
  final StreamController<TrackingHubEvent> _events =
      StreamController<TrackingHubEvent>.broadcast();
  final StreamController<void> _connectionRestored =
      StreamController<void>.broadcast();
  Future<void> Function()? onSessionRevoked;

  Stream<TrackingHubEvent> get events => _events.stream;
  Stream<void> get connectionRestored => _connectionRestored.stream;

  Future<Map<String, Object?>?> watchRideMap(int rideId) async {
    await _ensureConnected();
    final connection = _connection;
    if (connection?.state != HubConnectionState.Connected || !_foreground)
      return null;
    try {
      final result =
          await connection!.invoke('WatchRideMap', args: <Object>[rideId]);
      if (!identical(_connection, connection) ||
          result is! Map ||
          result['enabled'] != true) return null;
      final location = result['location'];
      return location is Map ? Map<String, Object?>.from(location) : null;
    } on Object {
      return null;
    }
  }

  Future<void> leaveRideMap(int rideId) =>
      _invokeIfConnected('LeaveRideMap', rideId);

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
    final generation = _connectionGeneration;
    try {
      await _ensureConnected().timeout(const Duration(seconds: 4));
      if (generation != _connectionGeneration) return false;
      final connection = _connection;
      if (connection?.state == HubConnectionState.Connected) {
        await connection!.invoke('PublishPassengerLocation',
            args: <Object>[payload]).timeout(const Duration(seconds: 5));
        return generation == _connectionGeneration;
      }
    } on Object {/* A blocked Hub must not prevent the HTTP GPS fallback. */}
    if (generation != _connectionGeneration || !Get.isRegistered<ApiClient>())
      return false;
    try {
      final response = await Get.find<ApiClient>().dio.post<Object?>(
            'tracking/passenger-location',
            data: payload,
            options: Options(
                sendTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5)),
          );
      final body = response.data;
      return generation == _connectionGeneration &&
          body is Map &&
          body['success'] == true &&
          body['data'] is Map &&
          (body['data'] as Map)['accepted'] == true;
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
    _nearbyDriverSubscription = null;
    _stateRecoveryRetry?.cancel();
    _stateRecoveryTask = null;
    supportsStateRecovery.value = false;
    stateChanges.reset();
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
    if (isClosed ||
        !_foreground ||
        _availability?.runtimeUnavailable.value == true) return;
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
    final current = _connection;
    if (current != null && current.state != HubConnectionState.Disconnected)
      return;
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
      retryDelays: <int>[
        0,
        1500 + _retryRandom.nextInt(1001),
        8000 + _retryRandom.nextInt(4001),
        24000 + _retryRandom.nextInt(12001),
      ],
    ).build();
    _connection = connection;
    connection.on('stateChanged', (arguments) {
      if (!identical(_connection, connection) ||
          arguments == null ||
          arguments.isEmpty) return;
      final payload = arguments.first;
      if (payload is! Map) return;
      final change = StateChange.parse(payload);
      if (change != null) {
        _invalidatePendingReads();
        supportsStateRecovery.value = true;
        stateChanges.observe(change);
      } else {
        stateChanges.disconnected();
        _stateRecoveryTask = null;
        unawaited(recoverState());
      }
    });
    connection.on('sessionRevoked', (_) {
      if (!identical(_connection, connection)) return;
      unawaited(_handleSessionRevoked());
    });
    for (final eventName in <String>[
      'rideAvailable',
      'rideUnavailable',
      'offerReceived',
      'offerUpdated',
      'rideRequestViewed',
      'rideSearchRecipientsUpdated',
      'rideCancellationUpdated',
      'rideArrivalUpdated',
      'rideRouteChangeUpdated',
      'rideStatusUpdated',
      'rideMessageCreated',
      'rideMessageUpdated',
      'paymentUpdated',
      'cashApprovalUpdated',
      'notificationCreated',
      'driverLocationUpdated',
      'passengerLocationUpdated',
      'nearbyDriverLocationUpdated',
      'nearbyDriverAvailabilityChanged',
    ]) {
      connection.on(eventName, (arguments) {
        if (!identical(_connection, connection)) return;
        if (arguments == null || arguments.isEmpty) return;
        final rawPayload = arguments.first;
        if (rawPayload is! Map) return;
        final payload = <String, Object?>{};
        rawPayload.forEach((key, value) {
          if (key != null) payload[key.toString()] = value;
        });
        if (!const {
          'driverLocationUpdated',
          'passengerLocationUpdated',
          'nearbyDriverLocationUpdated',
          'nearbyDriverAvailabilityChanged',
        }.contains(eventName)) _invalidatePendingReads();
        _events.add(TrackingHubEvent(eventName, payload));
      });
    }
    connection.onreconnecting(({Exception? error}) {
      if (!identical(_connection, connection)) return;
      isConnected.value = false;
      stateChanges.disconnected();
      _stateRecoveryTask = null;
      final availability = _availability;
      if (availability != null) unawaited(availability.checkNow());
    });
    connection.onreconnected(({String? connectionId}) {
      if (!identical(_connection, connection)) return;
      isConnected.value = true;
      unawaited(_restoreSubscriptionsAndNotify(connection));
    });
    connection.onclose(({Exception? error}) {
      if (identical(_connection, connection)) {
        isConnected.value = false;
        stateChanges.disconnected();
        _stateRecoveryTask = null;
        _connection = null;
        _scheduleReconnect();
        final availability = _availability;
        if (availability != null) unawaited(availability.checkNow());
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
      if (!identical(_connection, connection) ||
          generation != _connectionGeneration) return;
      _connection = null;
      isConnected.value = false;
      stateChanges.disconnected();
      _scheduleReconnect();
      final availability = _availability;
      if (availability != null) unawaited(availability.checkNow());
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
    await setForeground(_foreground);
    await _restoreRideSubscriptions(connection);
    await _joinNearbyDriverSubscription(connection);
    if (identical(_connection, connection) &&
        connection.state == HubConnectionState.Connected) {
      _invalidatePendingReads();
      _connectionRestored.add(null);
      await recoverState();
    }
  }

  /// Recovery is feature detected. Older servers retain existing REST fallback.
  Future<void> recoverState() {
    final existing = _stateRecoveryTask;
    if (existing != null) return existing;
    late final Future<void> task;
    task = _recoverState().whenComplete(() {
      if (identical(_stateRecoveryTask, task)) _stateRecoveryTask = null;
    });
    _stateRecoveryTask = task;
    return task;
  }

  Future<void> _recoverState() async {
    final connection = _connection;
    final generation = _connectionGeneration;
    if (!_foreground || connection?.state != HubConnectionState.Connected)
      return;
    try {
      await stateChanges.recover((versions, afterStream) async {
        final result = await connection!.invoke('ReplayStateChanges',
            args: <Object>[versions, afterStream ?? '']);
        if (!identical(_connection, connection) ||
            generation != _connectionGeneration ||
            !_foreground) {
          throw StateError('State recovery connection changed');
        }
        if (result is! Map) throw const FormatException('Invalid state replay');
        supportsStateRecovery.value = result['supported'] == true;
        if (result['supported'] == true &&
            result['events'] is List &&
            (result['events'] as List).isNotEmpty) _invalidatePendingReads();
        return Map<Object?, Object?>.from(result);
      });
      _stateRecoveryRetry?.cancel();
    } on Object {
      // Recovery failure never certifies freshness. Retry this failed work while
      // retaining legacy fallback, without introducing a business-state poll.
      if (identical(_connection, connection) &&
          generation == _connectionGeneration) {
        isStateSynchronized.value = false;
        _stateRecoveryRetry?.cancel();
        if (supportsStateRecovery.value && _foreground) {
          _stateRecoveryRetry = Timer(
              const Duration(seconds: 3), () => unawaited(recoverState()));
        }
      }
    }
    isStateSynchronized.value =
        supportsStateRecovery.value && stateChanges.synchronized;
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
    if (!_foreground || isClosed || !_hasInterest) return;
    _retryTimer?.cancel();
    _retryTimer =
        Timer(Duration(milliseconds: 12000 + _retryRandom.nextInt(6001)), () {
      if (_foreground && !isClosed && _hasInterest) {
        unawaited(_ensureConnected());
      }
    });
  }

  /// The backend may restart after SignalR exhausts its automatic retry list.
  /// Replace only the transport, retaining ride and screen subscriptions.
  Future<void> reconnectAfterApiRecovery() async {
    if (isClosed || !_foreground) return;
    _connectionGeneration++;
    _retryTimer?.cancel();
    _stateRecoveryRetry?.cancel();
    _stateRecoveryTask = null;
    _connectTask = null;
    stateChanges.disconnected();
    final previous = _connection;
    _connection = null;
    isConnected.value = false;
    if (previous != null) {
      try {
        await previous.stop().timeout(const Duration(seconds: 3));
      } on Object {/* A dead transport must not prevent a new connection. */}
    }
    if (!isClosed && _hasInterest) await _ensureConnected();
  }

  @override
  void onClose() {
    _apiRecovery?.cancel();
    _apiAvailabilityWorker?.dispose();
    unawaited(disconnect());
    stateChanges.dispose();
    unawaited(_events.close());
    unawaited(_connectionRestored.close());
    super.onClose();
  }
}
