import 'dart:async';

import 'package:get/get.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_models.dart';
import '../../../core/realtime/tracking_hub_service.dart';
import '../../../core/services/auth_session_service.dart';
import '../models/ride_models.dart';

class NotificationsController extends GetxController {
  NotificationsController(this._client, this._session, this._hub);

  final ApiClient _client;
  final AuthSessionService _session;
  final TrackingHubService _hub;
  final RxList<RideNotificationItem> items = <RideNotificationItem>[].obs;
  final RxBool isLoading = true.obs;
  final RxString loadError = ''.obs;
  int get unreadCount => items.where((item) => !item.isRead).length;
  StreamSubscription<TrackingHubEvent>? _eventSubscription;
  StreamSubscription<void>? _connectionSubscription;
  bool _loadInFlight = false;
  bool _reloadRequested = false;
  bool _initialLoadComplete = false;
  String? _notificationIdFromPush;

  @override
  void onInit() {
    super.onInit();
    final arguments = Get.arguments;
    if (arguments is Map) {
      _notificationIdFromPush = arguments['notificationId']?.toString();
    }
    _eventSubscription = _hub.events.listen((event) {
      if (event.name == 'notificationCreated') unawaited(load());
    });
    _connectionSubscription = _hub.connectionRestored.listen((_) {
      if (_initialLoadComplete) unawaited(load());
    });
    unawaited(_startRealtimeAndLoad());
  }

  Future<void> _startRealtimeAndLoad() async {
    await Future.wait<void>([
      _hub.setUserEventListening(this, true),
      load(),
    ]);
    _initialLoadComplete = true;
    final notificationId = _notificationIdFromPush;
    _notificationIdFromPush = null;
    if (notificationId != null) {
      final notification =
          items.where((item) => item.id == notificationId).firstOrNull;
      if (notification != null) await markRead(notification);
    }
  }

  Future<void> load() async {
    if (_loadInFlight) {
      _reloadRequested = true;
      return;
    }
    _loadInFlight = true;
    isLoading.value = true;
    loadError.value = '';
    try {
      do {
        _reloadRequested = false;
        await _loadOnce();
      } while (_reloadRequested && !isClosed);
    } catch (_) {
      loadError.value = 'تعذر تحميل الإشعارات. أعد المحاولة.';
    } finally {
      _loadInFlight = false;
      isLoading.value = false;
    }
  }

  Future<void> _loadOnce() async {
    if (!_session.isAuthenticated.value) {
      items.clear();
      return;
    }
    final result = await _client.execute<Object?>(
      model: 'NotificationModel',
      operation: 'list',
    );
    if (result is! ApiSuccess || result.data is! List) {
      loadError.value = 'تعذر تحميل الإشعارات. أعد المحاولة.';
      return;
    }
    items.assignAll(
      (result.data as List).whereType<Map<Object?, Object?>>().map((item) {
        final raw = Map<Object?, Object?>.from(item);
        final stamp = DateTime.tryParse('${raw['createdAtUtc'] ?? ''}');
        return RideNotificationItem(
          id: '${raw['id'] ?? ''}',
          title: '${raw['title'] ?? ''}',
          body: '${raw['body'] ?? ''}',
          timeLabel: stamp == null
              ? ''
              : '${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}',
          kind: '${raw['type'] ?? 'system'}',
          isRead: raw['isRead'] == true,
        );
      }).toList(growable: false),
    );
  }

  Future<void> markRead(RideNotificationItem item) async {
    if (item.isRead) return;
    final result = await _client.execute<Object?>(
      model: 'NotificationModel',
      operation: 'update',
      data: <String, Object?>{'id': item.id, 'isRead': true},
    );
    if (result is ApiSuccess) {
      final index = items.indexWhere((value) => value.id == item.id);
      if (index >= 0) items[index] = item.copyWith(isRead: true);
    }
  }

  Future<void> markAllRead() async {
    for (final item in items.where((item) => !item.isRead).toList()) {
      await markRead(item);
    }
  }

  @override
  void onClose() {
    _eventSubscription?.cancel();
    _connectionSubscription?.cancel();
    unawaited(_hub.setUserEventListening(this, false));
    super.onClose();
  }
}
