import 'dart:async';

import 'package:get/get.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_models.dart';
import '../../../core/services/auth_session_service.dart';
import '../models/ride_models.dart';

class NotificationsController extends GetxController {
  NotificationsController(this._client, this._session);

  final ApiClient _client;
  final AuthSessionService _session;
  final RxList<RideNotificationItem> items = <RideNotificationItem>[].obs;
  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => load());
  }

  Future<void> load() async {
    if (!_session.isAuthenticated.value) {
      items.clear();
      return;
    }
    final result = await _client.execute<Object?>(
      model: 'NotificationModel',
      operation: 'list',
    );
    if (result is! ApiSuccess || result.data is! List) return;
    items.assignAll((result.data as List).whereType<Map>().map((item) {
      final raw = Map<Object?, Object?>.from(item);
      final stamp = DateTime.tryParse('${raw['createdAtUtc'] ?? ''}');
      return RideNotificationItem(
        id: '${raw['id'] ?? ''}',
        title: '${raw['title'] ?? ''}',
        body: '${raw['body'] ?? ''}',
        timeLabel: stamp == null ? '' : '${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}',
        kind: '${raw['type'] ?? 'system'}',
        isRead: raw['isRead'] == true,
      );
    }).toList(growable: false));
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
    _refreshTimer?.cancel();
    super.onClose();
  }
}
