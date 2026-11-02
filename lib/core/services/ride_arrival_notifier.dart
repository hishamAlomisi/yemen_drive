import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../network/api_client.dart';
import '../network/api_models.dart';
import '../realtime/tracking_hub_service.dart';

class ArrivalSound {
  static const _channel = MethodChannel('yemen_drive/arrival_sound');
  Timer? _fallback;
  Future<void> start() async {
    if (_fallback != null) return;
    try {
      await _channel.invokeMethod<void>('start');
    } on MissingPluginException {
      await SystemSound.play(SystemSoundType.alert);
      _fallback = Timer.periodic(const Duration(seconds: 2),
          (_) => SystemSound.play(SystemSoundType.alert));
    }
  }

  Future<void> stop() async {
    _fallback?.cancel();
    _fallback = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {/* No native player on this platform. */}
  }
}

class RideArrivalNotifier extends GetxService with WidgetsBindingObserver {
  RideArrivalNotifier(this.api, this.hub,
      {ArrivalSound? sound, GetStorage? storage, required this.userId})
      : sound = sound ?? ArrivalSound(),
        storage = storage ?? GetStorage();
  final ApiClient api;
  final TrackingHubService hub;
  final ArrivalSound sound;
  final GetStorage storage;
  final int userId;
  final view = Rxn<Map<String, Object?>>();
  final busy = false.obs;
  final pendingStops = <String, String>{};
  StreamSubscription<TrackingHubEvent>? _events;
  StreamSubscription<void>? _reconnect;
  Route<void>? _route;
  bool _foreground = true;
  int _revision = 0;
  Timer? _retry;
  String get _storageKey => 'pending_arrival_stops_$userId';
  @override
  void onInit() {
    super.onInit();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    final saved = storage.read<Map>(_storageKey);
    if (saved != null)
      pendingStops
          .addAll(saved.map((key, value) => MapEntry('$key', '$value')));
    _events = hub.events.listen((event) {
      if (event.name == 'rideArrivalUpdated') {
        final id = int.tryParse('${event.payload['rideId']}');
        if (id != null) unawaited(refresh(id));
      }
      if (event.name == 'rideStatusUpdated' &&
          '${event.payload['rideId']}' == '${view.value?['rideId']}' &&
          ('${event.payload['rideStatus']}' != '9' ||
              event.payload['passengerBoardedAtUtc'] != null)) {
        ++_revision;
        unawaited(_dismiss());
      }
    });
    _reconnect = hub.connectionRestored.listen((_) {
      unawaited(_retryStops());
      final id = int.tryParse('${view.value?['rideId']}');
      if (id != null) unawaited(refresh(id));
    });
    unawaited(hub.setForeground(_foreground));
    unawaited(_retryStops());
  }

  Future<Map<String, Object?>> _call(
      String operation, Map<String, Object?> data) async {
    final result = await api.execute<Object?>(
        model: 'RideArrivalModel', operation: operation, data: data);
    if (result is ApiFailure) throw result.problem;
    if (result is! ApiSuccess || result.data is! Map)
      throw const FormatException('تعذر تحديث تنبيه الوصول.');
    return Map<String, Object?>.from(result.data as Map);
  }

  Future<void> refresh(int rideId) async {
    final revision = ++_revision;
    try {
      final current = await _call('get', {'rideId': rideId});
      if (revision != _revision) return;
      if (current['arrived'] != true ||
          (current['acknowledged'] == true && current['alertActive'] != true)) {
        await _dismiss();
        return;
      }
      view.value = current;
      if (!_foreground) return;
      if (pendingStops['$rideId'] == '${current['alertId']}') {
        unawaited(_retryStops());
        return;
      }
      if (current['alertActive'] == true) {
        try {
          await sound.start();
        } on Object {/* Keep the visible alert when audio is unavailable. */}
      }
      _present();
    } on Object {/* Reconnect recovers the persisted server alert. */}
  }

  void _present() {
    final context = Get.overlayContext;
    if (_route != null || context == null || view.value == null) return;
    final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Obx(() {
              final current = view.value;
              if (current == null) return const SizedBox.shrink();
              final ringing = current['alertActive'] == true;
              final content = Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                    ringing
                        ? Icons.notifications_active_rounded
                        : Icons.local_taxi_rounded,
                    size: 76,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                const Text('يمن درايف',
                    style:
                        TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                Text('${current['driverName']} وصل وينتظرك',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 12),
                const Text('السائق في نقطة الانطلاق. يرجى التوجه إليه.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                    key: const ValueKey('acknowledge-arrival'),
                    onPressed: busy.value ? null : acknowledge,
                    child:
                        Text(ringing ? 'إيقاف التنبيه' : 'شاهدت إشعار الوصول')),
              ]);
              return PopScope(
                  canPop: false,
                  child: ringing
                      ? Scaffold(
                          key: const ValueKey('arrival-fullscreen-alert'),
                          body: SafeArea(
                              child: Center(
                                  child: SingleChildScrollView(
                                      padding: const EdgeInsets.all(24),
                                      child: content))))
                      : AlertDialog(
                          key: const ValueKey('arrival-confirmation-card'),
                          content: SingleChildScrollView(child: content)));
            }));
    _route = route;
    unawaited(Navigator.of(context, rootNavigator: true).push(route).then((_) {
      if (identical(_route, route)) _route = null;
    }));
  }

  Future<void> acknowledge() async {
    final current = view.value;
    if (current == null || busy.value) return;
    busy.value = true;
    final id = '${current['rideId']}';
    final alertId =
        current['alertActive'] == true ? '${current['alertId']}' : '';
    pendingStops[id] = alertId;
    await _dismiss();
    try {
      await storage.write(_storageKey, pendingStops);
    } on Object {/* Retain the pending receipt in memory. */}
    await _retryStops();
    busy.value = false;
  }

  Future<void> _retryStops() async {
    for (final entry in pendingStops.entries.toList()) {
      try {
        await _call(entry.value.isEmpty ? 'acknowledge' : 'stop', {
          'rideId': int.parse(entry.key),
          if (entry.value.isNotEmpty) 'alertId': entry.value
        });
        pendingStops.remove(entry.key);
      } on ApiProblemDetails catch (error) {
        if (const {
          'arrival_not_active',
          'arrival_alert_changed',
          'ride_access_denied',
          'ride_not_found'
        }.contains(error.code)) pendingStops.remove(entry.key);
      } on Object {/* Keep the acknowledgement through connection loss. */}
    }
    try {
      await storage.write(_storageKey, pendingStops);
    } on Object {/* The in-memory queue still retries. */}
    _retry?.cancel();
    if (pendingStops.isNotEmpty)
      _retry =
          Timer(const Duration(seconds: 20), () => unawaited(_retryStops()));
  }

  Future<void> _dismiss() async {
    await sound.stop();
    view.value = null;
    final route = _route;
    _route = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    unawaited(hub.setForeground(_foreground));
    if (!_foreground) {
      unawaited(sound.stop());
      return;
    }
    unawaited(_retryStops());
    final id = int.tryParse('${view.value?['rideId']}');
    if (id != null) unawaited(refresh(id));
  }

  @override
  void onClose() {
    _events?.cancel();
    _reconnect?.cancel();
    _retry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_dismiss());
    super.onClose();
  }
}
