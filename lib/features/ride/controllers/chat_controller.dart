import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_models.dart';
import '../../../core/realtime/tracking_hub_service.dart';
import '../../../core/services/auth_session_service.dart';
import 'ride_controller.dart';
import '../models/ride_models.dart';

class ChatController extends GetxController {
  ChatController(this._client, this._session, this._ride, this._hub);

  static const int _pageSize = 50;

  final ApiClient _client;
  final AuthSessionService _session;
  final RideController _ride;
  final TrackingHubService _hub;
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final RxList<RideChatMessage> messages = <RideChatMessage>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isLoadingOlder = false.obs;
  final RxBool hasOlderMessages = false.obs;
  final RxBool isSending = false.obs;

  StreamSubscription<TrackingHubEvent>? _eventSubscription;
  StreamSubscription<void>? _connectionSubscription;
  bool _latestLoadInFlight = false;

  @override
  void onInit() {
    super.onInit();
    _eventSubscription = _hub.events.listen(_handleHubEvent);
    _connectionSubscription = _hub.connectionRestored.listen((_) {
      unawaited(loadMessages());
    });
    unawaited(loadMessages());
  }

  Future<void> loadMessages() async {
    final rideId = int.tryParse(_ride.currentRideId ?? '');
    if (rideId == null || !_session.isAuthenticated.value) {
      messages.clear();
      hasOlderMessages.value = false;
      return;
    }
    if (_latestLoadInFlight) return;
    _latestLoadInFlight = true;
    if (messages.isEmpty) isLoading.value = true;
    try {
      final result = await _client.execute<Object?>(
        model: 'RideMessageModel',
        operation: 'list',
        data: <String, Object?>{'rideId': rideId, 'pageSize': _pageSize},
      );
      if (result is! ApiSuccess || result.data is! List) return;
      final page = (result.data as List)
          .whereType<Map<Object?, Object?>>()
          .map((item) => _parseMessage(Map<Object?, Object?>.from(item)))
          .whereType<RideChatMessage>()
          .toList(growable: false);
      if (messages.isEmpty || !hasOlderMessages.value) {
        hasOlderMessages.value = page.length == _pageSize;
      }
      _upsertMessages(page, scrollToBottom: messages.isEmpty || _isAtBottom);
    } catch (_) {
      if (messages.isEmpty) {
        Get.snackbar('تعذر تحميل المحادثة', 'تحقق من الاتصال وحاول مجدداً.');
      }
    } finally {
      _latestLoadInFlight = false;
      isLoading.value = false;
    }
  }

  Future<void> loadOlderMessages() async {
    final rideId = int.tryParse(_ride.currentRideId ?? '');
    if (rideId == null || messages.isEmpty || isLoadingOlder.value) return;
    final oldest = messages.first;
    isLoadingOlder.value = true;
    try {
      final result = await _client.execute<Object?>(
        model: 'RideMessageModel',
        operation: 'list',
        data: <String, Object?>{
          'rideId': rideId,
          'pageSize': _pageSize,
          'beforeId': oldest.id,
          'beforeCreatedAtUtc': oldest.createdAtUtc,
        },
      );
      if (result is! ApiSuccess || result.data is! List) return;
      final page = (result.data as List)
          .whereType<Map<Object?, Object?>>()
          .map((item) => _parseMessage(Map<Object?, Object?>.from(item)))
          .whereType<RideChatMessage>()
          .toList(growable: false);
      _upsertMessages(page);
      hasOlderMessages.value = page.length == _pageSize;
    } catch (_) {
      Get.snackbar('تعذر تحميل رسائل أقدم', 'تحقق من الاتصال وحاول مجدداً.');
    } finally {
      isLoadingOlder.value = false;
    }
  }

  RideChatMessage? _parseMessage(Map<Object?, Object?> raw) {
    final id = int.tryParse('${raw['id'] ?? ''}');
    final senderId = int.tryParse('${raw['senderId'] ?? ''}');
    final createdAtUtc = raw['createdAtUtc']?.toString();
    if (id == null || senderId == null || createdAtUtc == null) return null;
    final stamp = DateTime.tryParse(createdAtUtc)?.toLocal();
    return RideChatMessage(
      id: id,
      createdAtUtc: createdAtUtc,
      text: '${raw['content'] ?? ''}',
      timeLabel: stamp == null
          ? ''
          : '${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}',
      isMine: senderId == _session.currentUserId.value,
    );
  }

  void _handleHubEvent(TrackingHubEvent event) {
    if (event.name != 'rideMessageCreated') return;
    final rideId = int.tryParse('${event.payload['rideId'] ?? ''}');
    if (rideId != int.tryParse(_ride.currentRideId ?? '')) return;
    final message = _parseMessage(Map<Object?, Object?>.from(event.payload));
    if (message != null) {
      _upsertMessages(<RideChatMessage>[message],
          scrollToBottom: messages.isEmpty || _isAtBottom);
    }
  }

  bool get _isAtBottom =>
      !scrollController.hasClients ||
      scrollController.position.maxScrollExtent -
              scrollController.position.pixels <=
          120;

  void _upsertMessages(
    Iterable<RideChatMessage> incoming, {
    bool scrollToBottom = false,
  }) {
    final byId = <int, RideChatMessage>{
      for (final message in messages) message.id: message,
    };
    for (final message in incoming) {
      byId[message.id] = message;
    }
    final sorted = byId.values.toList()
      ..sort((left, right) {
        final timeOrder = DateTime.parse(left.createdAtUtc)
            .compareTo(DateTime.parse(right.createdAtUtc));
        return timeOrder != 0 ? timeOrder : left.id.compareTo(right.id);
      });
    messages.assignAll(sorted);
    if (scrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> sendMessage() async {
    final value = messageController.text.trim();
    if (value.isEmpty || isSending.value) return;
    final rideId = int.tryParse(_ride.currentRideId ?? '');
    if (rideId == null) {
      Get.snackbar('المحادثة غير متاحة', 'اختر عرض سائق أولاً.');
      return;
    }
    isSending.value = true;
    try {
      final result = await _client.execute<Object?>(
        model: 'RideMessageModel',
        operation: 'add',
        data: <String, Object?>{'rideId': rideId, 'content': value},
      );
      if (result is! ApiSuccess || result.data is! Map) {
        Get.snackbar('تعذر إرسال الرسالة', 'حاول مرة أخرى.');
        return;
      }
      final message =
          _parseMessage(Map<Object?, Object?>.from(result.data as Map));
      if (message == null) {
        Get.snackbar('تعذر إرسال الرسالة', 'استجابة الخادم غير مكتملة.');
        return;
      }
      _upsertMessages(<RideChatMessage>[message], scrollToBottom: true);
      messageController.clear();
    } catch (_) {
      Get.snackbar('تعذر إرسال الرسالة', 'تحقق من الاتصال وحالة الرحلة.');
    } finally {
      isSending.value = false;
    }
  }

  @override
  void onClose() {
    messageController.dispose();
    scrollController.dispose();
    unawaited(_eventSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    super.onClose();
  }
}
