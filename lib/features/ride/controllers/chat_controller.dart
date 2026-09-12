import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/ride_models.dart';

class ChatController extends GetxController {
  final TextEditingController messageController = TextEditingController();
  final RxList<RideChatMessage> messages = <RideChatMessage>[
    const RideChatMessage(
      text: 'مرحباً، أنا في طريقي إليك الآن.',
      timeLabel: '12:34',
      isMine: false,
    ),
    const RideChatMessage(
      text: 'أهلاً بك، أنا أمام البوابة الرئيسية.',
      timeLabel: '12:35',
      isMine: true,
    ),
  ].obs;

  void sendMessage() {
    final value = messageController.text.trim();
    if (value.isEmpty) return;
    messages.add(RideChatMessage(text: value, timeLabel: 'الآن', isMine: true));
    messageController.clear();
  }

  @override
  void onClose() {
    messageController.dispose();
    super.onClose();
  }
}
