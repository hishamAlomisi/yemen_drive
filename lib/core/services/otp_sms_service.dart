import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'push_notifications_service.dart';

/// Starts before the API request so an SMS arriving during navigation is kept.
class OtpSmsService {
  static const channel = MethodChannel('yemen_drive/otp_sms');

  static Future<Map<String, Object?>> prepareRequest({
    Future<Map<String, Object?>> Function()? pushFields,
    bool allowPushFailure = false,
  }) async {
    final push = Get.isRegistered<PushNotificationsService>()
        ? Get.find<PushNotificationsService>()
        : null;
    final generation = push?.otpPushRequestGeneration;
    void ensureActive() {
      if (generation != null) push!.ensureOtpPushRequestActive(generation);
    }

    ensureActive();
    final smsFields = await _prepareSmsFields();
    ensureActive();
    var fields = <String, Object?>{};
    if (pushFields != null) {
      try {
        fields = await pushFields();
      } on OtpPushRequestCancelled {
        rethrow;
      } on Object {
        ensureActive();
        if (!allowPushFailure) rethrow;
      }
    }
    ensureActive();
    return {
      ...fields,
      ...smsFields,
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        'notificationRenderer': 'app',
    };
  }

  static Future<Map<String, Object?>> _prepareSmsFields() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return {};
    try {
      final hash = await channel
          .invokeMethod<String>('start')
          .timeout(const Duration(seconds: 3));
      if (hash != null && RegExp(r'^[A-Za-z0-9+/]{11}$').hasMatch(hash)) {
        return {'smsAppHash': hash};
      }
    } on TimeoutException {
      // SMS preparation must not delay the authentication request indefinitely.
    } on PlatformException {
      // Manual entry and keyboard autofill remain available without Play services.
    } on MissingPluginException {
      // Other platforms use their keyboard's oneTimeCode autofill.
    }
    return {};
  }

  static Future<void> attach(ValueChanged<String> onCode) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'code' && call.arguments is String) {
        final code = normalizeDigits(call.arguments as String);
        if (code.length == 6) onCode(code);
      }
    });
    try {
      final pending = await channel.invokeMethod<String>('takePendingCode');
      if (pending != null) {
        final code = normalizeDigits(pending);
        if (code.length == 6) onCode(code);
      }
    } on PlatformException {
      // Listening is optional; a failed bridge must not block verification.
    } on MissingPluginException {
      // No native SMS bridge on this platform.
    }
  }

  static Future<void> detach() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    channel.setMethodCallHandler(null);
    try {
      await channel.invokeMethod<void>('stop');
    } on PlatformException {
      // The activity may already have been destroyed.
    } on MissingPluginException {
      // No native bridge.
    }
  }

  static String normalizeDigits(String value) {
    final result = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0x30 && rune <= 0x39) {
        result.writeCharCode(rune);
      } else if (rune >= 0x660 && rune <= 0x669) {
        result.writeCharCode(0x30 + rune - 0x660);
      } else if (rune >= 0x6f0 && rune <= 0x6f9) {
        result.writeCharCode(0x30 + rune - 0x6f0);
      }
    }
    return result.toString();
  }
}
