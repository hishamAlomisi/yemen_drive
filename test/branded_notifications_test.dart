import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_drive/core/services/branded_notifications.dart';

class _Notifications extends Fake implements FlutterLocalNotificationsPlugin {
  final shown = <Map<String, Object?>>[];
  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shown.add({
      'id': id,
      'title': title,
      'body': body,
      'details': notificationDetails,
      'payload': payload,
    });
  }
}

void main() {
  final now = DateTime.now().toUtc();
  Map<String, dynamic> data({String? action}) => {
        'notificationId': '42',
        'notificationRenderer': 'app',
        'title': 'يمن درايف',
        'body': 'رسالة جديدة',
        if (action != null) 'action': action,
      };

  test(
      'background data notification uses both app icons and retains tap routing',
      () async {
    final plugin = _Notifications();
    final payload = {...data(action: 'open_ride_chat'), 'rideId': '7'};
    await showBrandedBackgroundNotification(
      RemoteMessage(data: payload),
      clientType: 'customer',
      notifications: plugin,
    );
    final shown = plugin.shown.single;
    final android = (shown['details'] as NotificationDetails).android!;
    expect(android.icon, 'ic_stat_yemendrive');
    expect(
      (android.largeIcon as DrawableResourceAndroidBitmap).data,
      'ic_brand_notification',
    );
    expect(android.channelId, 'yemendrive_alerts');
    expect(shown['id'], 42);
    expect(shown['body'], 'رسالة جديدة');
    final decoded =
        jsonDecode(shown['payload'] as String) as Map<String, dynamic>;
    expect(decoded['rideId'], '7');
    expect(decoded['action'], 'open_ride_chat');
  });

  test('legacy FCM notification is not displayed again by background handler',
      () async {
    final plugin = _Notifications();
    await showBrandedBackgroundNotification(
      RemoteMessage(
        data: data(),
        notification: const RemoteNotification(title: 'Already displayed'),
      ),
      clientType: 'customer',
      notifications: plugin,
    );
    expect(plugin.shown, isEmpty);
  });

  test('unmarked data and metadata-only messages remain silent', () async {
    final plugin = _Notifications();
    await showBrandedBackgroundNotification(
      const RemoteMessage(data: {'title': 'Unmarked'}),
      clientType: 'customer',
      notifications: plugin,
    );
    await showBrandedBackgroundNotification(
      const RemoteMessage(data: {'notificationRenderer': 'app'}),
      clientType: 'customer',
      notifications: plugin,
    );
    expect(plugin.shown, isEmpty);
  });

  test('ride offers remain exclusive to the verified availability renderer',
      () async {
    final plugin = _Notifications();
    await showBrandedBackgroundNotification(
      RemoteMessage(data: data(action: 'open_ride_offer')),
      clientType: 'customer',
      notifications: plugin,
    );
    expect(plugin.shown, isEmpty);
  });

  test(
      'current app OTP displays locally while expired and wrong-app OTP do not',
      () async {
    final plugin = _Notifications();
    final payload = {
      ...data(action: 'test_otp'),
      'clientType': 'customer',
      'challengeId': 'synthetic-challenge',
      'purpose': 'signUp',
      'expiresAtUtc': now.add(const Duration(minutes: 5)).toIso8601String(),
    };
    await showBrandedBackgroundNotification(
      RemoteMessage(data: payload),
      clientType: 'customer',
      notifications: plugin,
    );
    await showBrandedBackgroundNotification(
      RemoteMessage(data: {...payload, 'clientType': 'other-app'}),
      clientType: 'customer',
      notifications: plugin,
    );
    await showBrandedBackgroundNotification(
      RemoteMessage(
        data: {
          ...payload,
          'expiresAtUtc':
              now.subtract(const Duration(minutes: 1)).toIso8601String(),
        },
      ),
      clientType: 'customer',
      notifications: plugin,
    );
    expect(plugin.shown, hasLength(1));
    final decoded = jsonDecode(plugin.shown.single['payload'] as String)
        as Map<String, dynamic>;
    expect(decoded['action'], 'test_otp');
  });
}
