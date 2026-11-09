import 'dart:async';

/// A durable invalidation is acknowledged only after interested owners finish
/// their authoritative refresh. No clock/timer polls business state while idle.
class StateChange {
  const StateChange(this.stream, this.version, this.resource, this.resourceId);
  final String stream;
  final int version;
  final String resource;
  final int resourceId;

  static StateChange? parse(Map<Object?, Object?> value) {
    if (value.containsKey('schemaVersion') && value['schemaVersion'] != 1)
      return null;
    final stream = value['stream']?.toString();
    final version = int.tryParse('${value['version']}');
    final resource = value['resource']?.toString();
    final id = int.tryParse('${value['resourceId']}');
    if (stream == null ||
        stream.isEmpty ||
        stream.length > 120 ||
        version == null ||
        version <= 0 ||
        resource == null ||
        resource.isEmpty ||
        id == null ||
        id < 0) return null;
    return StateChange(stream, version, resource, id);
  }
}

typedef StateReconciler = Future<void> Function(List<StateChange> changes);

class StateChangeCoordinator {
  StateChangeCoordinator({this.onStatusChanged});
  final void Function()? onStatusChanged;
  final Map<Object, StateReconciler> _owners = {};
  final Map<String, int> _applied = {};
  final Map<String, StateChange> _pending = {};
  Future<void>? _drainTask;
  Timer? _retry;
  bool _disposed = false;
  bool _connected = false;
  bool _replaying = false;
  bool _failed = false;
  int epoch = 0;
  int _generation = 0;
  int _generationEpoch = 0;
  final Map<String, int> _resourceEpochs = {};

  /// Unrelated resource traffic must not discard a canonical read. A transport
  /// or account reset still invalidates every resource's in-flight snapshots.
  int epochForResources(Iterable<String> resources) {
    var latest = _generationEpoch;
    for (final resource in resources) {
      final revision = _resourceEpochs[resource] ?? 0;
      if (revision > latest) latest = revision;
    }
    return latest;
  }

  bool get synchronized =>
      _connected &&
      !_replaying &&
      !_failed &&
      _pending.isEmpty &&
      _drainTask == null;
  Map<String, int> get versions => Map.unmodifiable(_applied);
  bool covers(Object owner) => _owners.containsKey(owner);
  void register(Object owner, StateReconciler reconcile) =>
      _owners[owner] = reconcile;
  void unregister(Object owner) => _owners.remove(owner);

  void observe(StateChange change) {
    if (_disposed) return;
    final known =
        _pending[change.stream]?.version ?? _applied[change.stream] ?? 0;
    if (change.version <= known) return;
    _pending[change.stream] = change;
    epoch++;
    _resourceEpochs.remove(change.resource);
    _resourceEpochs[change.resource] = epoch;
    // Known resource names are few. Unknown future contracts cannot grow this
    // cache indefinitely; eviction conservatively invalidates existing reads.
    if (_resourceEpochs.length > 128) {
      _resourceEpochs.remove(_resourceEpochs.keys.first);
      _generationEpoch = epoch;
    }
    _failed = false;
    onStatusChanged?.call();
    if (_connected && !_replaying) unawaited(flush().catchError((Object _) {}));
  }

  void disconnected() {
    _connected = false;
    _generation++;
    epoch++; // In-flight snapshots from the old connection must not apply.
    _generationEpoch = epoch;
    _retry?.cancel();
    onStatusChanged?.call();
  }

  Future<void> recover(
      Future<Map<Object?, Object?>> Function(Map<String, int>, String?)
          read) async {
    final generation = ++_generation;
    _connected = true;
    _replaying = true;
    _failed = false;
    onStatusChanged?.call();
    try {
      String? afterStream;
      while (!_disposed && _connected && generation == _generation) {
        final page = await read(Map.of(_applied), afterStream);
        if (generation != _generation) return;
        if (page['supported'] != true)
          throw StateError('Durable recovery unavailable');
        final events = page['events'];
        if (events is! List)
          throw const FormatException('Invalid state replay');
        for (final raw in events) {
          if (raw is! Map<Object?, Object?>)
            throw const FormatException('Invalid state event');
          final change = StateChange.parse(raw);
          if (change == null)
            throw const FormatException('Invalid state event');
          observe(change);
        }
        await flush();
        if (generation != _generation) return;
        if (page['hasMore'] != true) break;
        final nextStream = page['nextStream']?.toString();
        if (nextStream == null ||
            nextStream.isEmpty ||
            nextStream == afterStream) {
          throw const FormatException('State replay did not advance');
        }
        afterStream = nextStream;
      }
    } catch (_) {
      if (generation == _generation) _failed = true;
      rethrow;
    } finally {
      if (generation == _generation) {
        _replaying = false;
        onStatusChanged?.call();
      }
    }
  }

  Future<void> flush() {
    final existing = _drainTask;
    if (existing != null) return existing;
    late final Future<void> task;
    task = _drain().whenComplete(() {
      if (identical(_drainTask, task)) _drainTask = null;
      onStatusChanged?.call();
    });
    _drainTask = task;
    return task;
  }

  Future<void> _drain() async {
    // Coalesce the synchronous burst, without imposing an idle polling cadence.
    await Future<void>.delayed(Duration.zero);
    while (_pending.isNotEmpty && !_disposed && _connected) {
      final generation = _generation;
      final batch = _pending.values.toList(growable: false);
      try {
        // Independent screen reads start together so identical API requests
        // can share one in-flight response. Wait for every owner, including
        // failures, before acknowledging or starting the next version.
        await Future.wait<void>([
          for (final owner in _owners.entries.toList(growable: false))
            if (identical(_owners[owner.key], owner.value))
              Future<void>.sync(() => owner.value(batch)),
        ]);
        // An old connection's refresh cannot acknowledge a new connection's
        // state. Reconcile retained work again if recovery has already started.
        if (generation != _generation) continue;
        for (final change in batch) {
          _applied.remove(change.stream);
          _applied[change.stream] = change.version;
          // This cache only avoids redundant canonical reads. Evicted streams
          // are fully replayed next time; the cursor, never cache size, pages.
          while (_applied.length > 512) {
            _applied.remove(_applied.keys.first);
          }
          if (_pending[change.stream]?.version == change.version)
            _pending.remove(change.stream);
        }
        _failed = false;
      } catch (_) {
        _failed = true;
        _retry?.cancel();
        if (_connected && !_disposed && !_replaying) {
          _retry = Timer(const Duration(seconds: 2), () {
            if (_connected && !_disposed)
              unawaited(flush().catchError((Object _) {}));
          });
        }
        rethrow;
      }
    }
  }

  void reset() {
    disconnected();
    _applied.clear();
    _pending.clear();
    _resourceEpochs.clear();
    _failed = false;
  }

  void dispose() {
    reset();
    _owners.clear();
    _disposed = true;
  }
}
