import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String appNotificationRenderer = 'app';

NotificationDetails brandedNotificationDetails(String title, String body) =>
    NotificationDetails(
      android: AndroidNotificationDetails(
        'yemendrive_alerts',
        'إشعارات يمن درايف',
        channelDescription: 'تحديثات الرحلات والدفع والحساب',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_yemendrive',
        color: const Color(0xFF174C43),
        largeIcon: const DrawableResourceAndroidBitmap('ic_brand_notification'),
        category: AndroidNotificationCategory.status,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      ),
    );

bool isCurrentAppOtp(
  Map<String, dynamic> data,
  String clientType, {
  DateTime? now,
}) {
  final expires = DateTime.tryParse('${data['expiresAtUtc'] ?? ''}');
  return data['clientType'] == clientType &&
      '${data['challengeId'] ?? ''}'.trim().isNotEmpty &&
      '${data['purpose'] ?? ''}'.trim().isNotEmpty &&
      expires != null &&
      expires.isAfter((now ?? DateTime.now()).toUtc());
}

/// Legacy notification envelopes are displayed by FCM itself. Only opted-in
/// data messages reach this renderer, which avoids displaying them twice.
Future<void> showBrandedBackgroundNotification(
  RemoteMessage message, {
  required String clientType,
  FlutterLocalNotificationsPlugin? notifications,
}) async {
  if (message.notification != null ||
      message.data['notificationRenderer'] != appNotificationRenderer ||
      message.data['action'] == 'open_ride_offer') {
    return;
  }
  if (message.data['action'] == 'test_otp' &&
      !isCurrentAppOtp(message.data, clientType)) {
    return;
  }
  if (message.data['title'] == null && message.data['body'] == null) return;
  final title = message.data['title']?.toString() ?? 'يمن درايف';
  final body = message.data['body']?.toString() ?? '';
  if (title.trim().isEmpty && body.trim().isEmpty) return;
  final plugin = notifications ?? FlutterLocalNotificationsPlugin();
  if (notifications == null) {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_yemendrive'),
      ),
    );
  }
  await plugin.show(
    id: int.tryParse('${message.data['notificationId'] ?? ''}') ??
        (message.messageId?.hashCode ?? message.hashCode),
    title: title,
    body: body,
    notificationDetails: brandedNotificationDetails(title, body),
    payload: jsonEncode(message.data),
  );
}
