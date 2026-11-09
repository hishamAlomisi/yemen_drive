import 'dart:async';

import 'package:get/get.dart';

import '../services/startup_connection_service.dart';
import 'state_change_coordinator.dart';
import 'tracking_hub_service.dart';

/// A discarded snapshot is retried by the durable owner, never acknowledged.
class StateSnapshotSuperseded implements Exception {
  const StateSnapshotSuperseded();
}

/// Ties durable recovery to a screen's lifetime. The callback must complete only
/// after canonical data has been applied, and throw on failure or busy work.
class RealtimeStateBinding {
  RealtimeStateBinding({
    required this.owner,
    required Set<String> resources,
    required bool Function(StateChange) accepts,
    required Future<void> Function() refresh,
  }) : _resources = Set.unmodifiable(resources) {
    if (Get.isRegistered<StartupConnectionService>()) {
      _apiRecovery = Get.find<StartupConnectionService>().recovered.listen((_) {
        _queueRefresh(refresh);
      });
    }
    if (!Get.isRegistered<TrackingHubService>()) return;
    final hub = _hub = Get.find<TrackingHubService>();
    hub.stateChanges.register(owner, (changes) async {
      if (!_disposed && changes.any(accepts)) await refresh();
    });
    _legacyEvents = hub.events.listen((event) {
      // Older deployments emit semantic events without durable state cursors.
      // GPS packets must not trigger business-state reloads.
      final resources = switch (event.name) {
        'rideStatusUpdated' ||
        'rideArrivalUpdated' ||
        'rideCancellationUpdated' ||
        'rideRouteChangeUpdated' =>
          const {'ride'},
        'paymentUpdated' || 'cashApprovalUpdated' => const {'ride', 'wallet'},
        'notificationCreated' => const {'account'},
        _ => const <String>{},
      };
      if (hub.supportsStateRecovery.value) return;
      for (final resource in resources.intersection(_resources)) {
        final id =
            resource == 'ride' ? int.tryParse('${event.payload['rideId']}') : 0;
        if (id != null && accepts(StateChange('legacy', 1, resource, id))) {
          _legacyEpoch++;
          _queueRefresh(refresh);
          break;
        }
      }
    });
    _transportRecovery = hub.connectionRestored.listen((_) {
      if (!hub.supportsStateRecovery.value) _queueRefresh(refresh);
    });
    unawaited(hub.setUserEventListening(owner, true));
  }

  final Object owner;
  final Set<String> _resources;
  TrackingHubService? _hub;
  StreamSubscription<void>? _apiRecovery;
  StreamSubscription<TrackingHubEvent>? _legacyEvents;
  StreamSubscription<void>? _transportRecovery;
  Timer? _refreshTimer;
  Future<void>? _refreshTask;
  bool _refreshAgain = false;
  int _legacyEpoch = 0;
  bool _disposed = false;
  int get epoch =>
      (_hub?.stateChanges.epochForResources(_resources) ?? 0) + _legacyEpoch;
  bool get synchronized =>
      _hub?.isStateSynchronized.value == true &&
      _hub?.stateChanges.covers(owner) == true;

  void _queueRefresh(Future<void> Function() refresh) {
    if (_disposed) return;
    _refreshAgain = true;
    if (_refreshTask != null || _refreshTimer != null) return;
    // Merge notifications delivered in one burst. At most one follow-up is
    // retained while a slow read is running, rather than one per notification.
    _refreshTimer = Timer(const Duration(milliseconds: 100), () {
      _refreshTimer = null;
      if (_disposed) return;
      _refreshAgain = false;
      var failed = false;
      late final Future<void> task;
      task = refresh().catchError((Object _) {
        failed = true;
      }).whenComplete(() {
        if (identical(_refreshTask, task)) _refreshTask = null;
        if (_disposed) return;
        if (failed) {
          if (Get.isRegistered<StartupConnectionService>() &&
              Get.find<StartupConnectionService>().runtimeUnavailable.value) {
            // The shared recovery signal restarts this owner once. Avoid a
            // private retry loop for each mounted panel during an API outage.
            _refreshAgain = true;
            return;
          }
          _refreshTimer = Timer(const Duration(seconds: 2), () {
            _refreshTimer = null;
            _queueRefresh(refresh);
          });
        } else if (_refreshAgain) {
          _queueRefresh(refresh);
        }
      });
      _refreshTask = task;
    });
  }

  void verify(int startedAt) {
    if (_disposed || epoch != startedAt) throw const StateSnapshotSuperseded();
  }

  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    unawaited(_apiRecovery?.cancel());
    unawaited(_legacyEvents?.cancel());
    unawaited(_transportRecovery?.cancel());
    _hub?.stateChanges.unregister(owner);
    final hub = _hub;
    if (hub != null) unawaited(hub.setUserEventListening(owner, false));
  }
}
