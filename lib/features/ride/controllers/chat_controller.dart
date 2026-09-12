import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_models.dart';
import '../../../core/services/auth_session_service.dart';
import 'ride_controller.dart';
import '../models/ride_models.dart';

class ChatController extends GetxController {
  ChatController(this._client, this._session, this._ride);

  final ApiClient _client;
  final AuthSessionService _session;
  final RideController _ride;
  final TextEditingController messageController = TextEditingController();
  final RxList<RideChatMessage> messages = <RideChatMessage>[].obs;
  final RxBool isLoading = false.obs;
  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    loadMessages();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      loadMessages();
    });
  }

  Future<void> loadMessages() async {
    final rideId = _ride.currentRideId;
    if (rideId == null || !_session.isAuthenticated.value) {
      messages.clear();
      return;
    }
    isLoading.value = true;
    try {
      final result = await _client.execute<Object?>(
        model: 'RideMessageModel',
        operation: 'list',
        data: <String, Object?>{'rideId': rideId},
      );
      if (result is! ApiSuccess || result.data is! List) return;
      messages.assignAll((result.data as List)
          .whereType<Map>()
          .map((item) {
            final raw = Map<Object?, Object?>.from(item);
            final stamp = DateTime.tryParse('${raw['createdAtUtc'] ?? ''}');
            return RideChatMessage(
              text: '${raw['content'] ?? ''}',
              timeLabel: stamp == null
                  ? ''
                  : '${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}',
              isMine: '${raw['senderId']}' == '${_session.currentUserId.value}',
            );
          })
          .toList(growable: false));
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> sendMessage() async {
    final value = messageController.text.trim();
    if (value.isEmpty) return;
    final rideId = _ride.currentRideId;
    if (rideId == null) {
      Get.snackbar('المحادثة غير متاحة', 'اختر عرض سائق أولاً.');
      return;
    }
    final result = await _client.execute<Object?>(
      model: 'RideMessageModel',
      operation: 'add',
      data: <String, Object?>{'rideId': rideId, 'content': value},
    );
    if (result is! ApiSuccess) {
      Get.snackbar('تعذر إرسال الرسالة', 'حاول مرة أخرى.');
      return;
    }
    messageController.clear();
    await loadMessages();
  }

  @override
  void onClose() {
    messageController.dispose();
    _refreshTimer?.cancel();
    super.onClose();
  }
}
