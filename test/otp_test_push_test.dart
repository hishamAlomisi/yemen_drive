import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/core/config/app_environment.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/services/push_notifications_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/auth/login/models/login_models.dart';
import 'package:yemen_drive/features/auth/login/providers/login_provider.dart';
import 'package:yemen_drive/features/auth/password_reset/models/password_reset_models.dart';
import 'package:yemen_drive/features/auth/password_reset/providers/password_reset_provider.dart';
import 'package:yemen_drive/features/auth/registration/models/registration_models.dart';
import 'package:yemen_drive/features/auth/registration/providers/registration_provider.dart';

class _Storage extends SecureStorageService {
  int pendingTokenSaves = 0;
  int pendingTokenClears = 0;
  @override
  Future<String?> get accessToken async => null;
  @override
  Future<String?> get deviceId async => 'synthetic-device';
  @override
  Future<void> saveDeviceId(String value) async {}
  @override
  Future<bool> get rememberMe async => false;
  @override
  Future<void> clear() async {}
  @override
  Future<void> savePendingPushToken(String value) async => pendingTokenSaves++;
  @override
  Future<void> clearPendingPushToken() async => pendingTokenClears++;
}

class _Settings extends Fake implements NotificationSettings {
  _Settings(this.authorizationStatus);
  @override
  final AuthorizationStatus authorizationStatus;
}

class _AwaitGate {
  final started = Completer<void>();
  final released = Completer<void>();
  Future<void> wait() {
    started.complete();
    return released.future;
  }
}

class _Messaging extends Fake implements FirebaseMessaging {
  AuthorizationStatus authorization = AuthorizationStatus.authorized;
  String? token = 'synthetic-fcm-address';
  Completer<String?>? pendingToken;
  _AwaitGate? permissionGate;
  _AwaitGate? autoInitGate;
  _AwaitGate? tokenGate;
  final calls = <String>[];
  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    calls.add('permission');
    await permissionGate?.wait();
    return _Settings(authorization);
  }

  @override
  Future<void> setAutoInitEnabled(bool enabled) async {
    calls.add('auto:$enabled');
    if (enabled) await autoInitGate?.wait();
  }

  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async {
    calls.add('token');
    await tokenGate?.wait();
    return pendingToken?.future ?? Future.value(token);
  }

  @override
  Future<void> deleteToken() async => calls.add('delete');
}

class _Notifications extends Fake implements FlutterLocalNotificationsPlugin {
  final shown = <Map<String, Object?>>[];
  final android = _AndroidNotifications();
  @override
  T? resolvePlatformSpecificImplementation<
          T extends FlutterLocalNotificationsPlatform>() =>
      android is T ? android as T : null;
  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shown.add({
      'title': title,
      'body': body,
      'payload': payload,
      'details': notificationDetails,
    });
  }
}

class _AndroidNotifications extends Fake
    implements AndroidFlutterLocalNotificationsPlugin {
  bool? enabled;
  _AwaitGate? probeGate;
  @override
  Future<bool?> areNotificationsEnabled() async {
    await probeGate?.wait();
    return enabled;
  }
}

class _Adapter implements HttpClientAdapter {
  bool enabled = true;
  _AwaitGate? capabilityGate;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path == 'auth/otp-delivery') await capabilityGate?.wait();
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'data': options.path == 'auth/otp-delivery'
            ? {'testPushEnabled': enabled}
            : {'challengeId': 'synthetic-challenge'},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

RemoteMessage _otpMessage({
  String clientType = 'customer',
  DateTime? expiresAt,
}) =>
    RemoteMessage(
      notification: const RemoteNotification(
        title: 'رمز التحقق التجريبي',
        body: '123456',
      ),
      data: {
        'action': 'test_otp',
        'clientType': clientType,
        'challengeId': 'synthetic-challenge',
        'purpose': 'signUp',
        'expiresAtUtc': (expiresAt ??
                DateTime.now().toUtc().add(const Duration(minutes: 5)))
            .toIso8601String(),
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppEnvironment.configure(baseUrl: 'https://example.invalid/api');
  late _Storage storage;
  late ApiClient client;
  late AuthSessionService session;
  late _Adapter adapter;
  late _Messaging messaging;
  late _Notifications notifications;
  late PushNotificationsService push;
  setUp(() async {
    Get.testMode = true;
    storage = _Storage();
    client = await ApiClient(storage).init();
    adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    session = await AuthSessionService(storage, client).init();
    messaging = _Messaging();
    notifications = _Notifications();
    push = PushNotificationsService(
      client,
      session,
      storage,
      messaging: messaging,
      localNotifications: notifications,
    );
  });
  tearDown(() async {
    client.dio.close(force: true);
    Get.reset();
  });

  test('foreground data notifications display both app icons', () async {
    await push.handleForegroundMessage(
      const RemoteMessage(
        data: {
          'notificationRenderer': 'app',
          'notificationId': '91',
          'title': 'تحديث الرحلة',
          'body': 'رسالة تجريبية',
          'action': 'open_active_ride',
        },
      ),
    );
    final shown = notifications.shown.single;
    final details = (shown['details'] as NotificationDetails).android!;
    expect(details.icon, 'ic_stat_yemendrive');
    expect(
      (details.largeIcon as DrawableResourceAndroidBitmap).data,
      'ic_brand_notification',
    );
    expect(shown['body'], 'رسالة تجريبية');
  });

  test(
      'ordinary no-service provider fixtures do not request push or configuration',
      () async {
    expect(await requestOtpPushData(), isEmpty);
    await RegistrationProvider(client)
        .requestOtp(const SignUpDraft(phone: '777000001'));
    expect(adapter.requests, hasLength(1));
    expect(
      (adapter.requests.single.data as Map).containsKey('otpPushToken'),
      isFalse,
    );
    expect(messaging.calls, isEmpty);
  });

  test(
      'server flag controls permission and FCM before every issuance without guest installation',
      () async {
    adapter.enabled = false;
    expect(await push.prepareOtpTarget(), isEmpty);
    expect(messaging.calls, isEmpty);
    adapter.enabled = true;
    final target = await push.prepareOtpTarget();
    expect(target, {
      'otpPushToken': 'synthetic-fcm-address',
      'deviceId': 'synthetic-device',
      'clientType': 'customer',
    });
    expect(messaging.calls, ['permission', 'auto:true', 'token']);
    expect(session.isAuthenticated.value, isFalse);
    expect(storage.pendingTokenSaves, 0);
    expect(
      adapter.requests.every((request) => request.method == 'GET'),
      isTrue,
    );
    adapter.enabled = false;
    expect(await push.prepareOtpTarget(), isEmpty);
    expect(messaging.calls, hasLength(3));
    await push.handleForegroundMessage(_otpMessage());
    expect(notifications.shown, isEmpty);
  });

  test(
      'all issuance and resend provider paths await fresh target and verification does not request one',
      () async {
    var issued = 0;
    Future<Map<String, Object?>> target() async {
      await Future<void>.delayed(Duration.zero);
      issued++;
      return {
        'otpPushToken': 'synthetic-$issued',
        'deviceId': 'synthetic-device',
        'clientType': 'customer',
      };
    }

    final login = LoginProvider(client, otpPushData: target);
    final registration = RegistrationProvider(client, otpPushData: target);
    final reset = PasswordResetProvider(client, otpPushData: target);
    for (var resend = 0; resend < 2; resend++) {
      await login.login(
        const LoginRequest(
          phone: '777000001',
          password: 'synthetic-password',
          deviceId: 'login-device',
        ),
      );
      await registration.requestOtp(const SignUpDraft(phone: '777000001'));
      await reset.request(identity: '777000001', channel: RecoveryChannel.sms);
    }
    expect(issued, 6);
    expect(adapter.requests, hasLength(6));
    for (var index = 0; index < 6; index++) {
      expect(
        (adapter.requests[index].data as Map)['otpPushToken'],
        'synthetic-${index + 1}',
      );
      expect((adapter.requests[index].data as Map)['clientType'], 'customer');
    }
    expect((adapter.requests.first.data as Map)['deviceId'], 'login-device');
    await login.verifyDeviceOtp(
      const DeviceOtpRequest(
        phone: '777000001',
        code: '123456',
        challengeId: 'synthetic-challenge',
        deviceId: 'login-device',
      ),
    );
    await registration.verifyOtp(phone: '777000001', code: '123456');
    await reset.verify(identity: '777000001', code: '123456');
    expect(issued, 6);
    expect(
      adapter.requests
          .skip(6)
          .every((r) => !(r.data as Map).containsKey('otpPushToken')),
      isTrue,
    );
  });

  test(
      'blocked permission omits the target so the API can decide whether OTP is required',
      () async {
    messaging.authorization = AuthorizationStatus.denied;
    notifications.android.enabled = false;
    Get.put<PushNotificationsService>(push);
    await LoginProvider(client).login(
      const LoginRequest(
        phone: '777000001',
        password: 'synthetic-password',
        deviceId: 'synthetic-device',
        trustedDeviceToken: 'synthetic-trust',
      ),
    );
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first.method, 'GET');
    expect(adapter.requests.last.method, 'POST');
    expect(
      (adapter.requests.last.data as Map)['trustedDeviceToken'],
      'synthetic-trust',
    );
    expect(
      (adapter.requests.last.data as Map).containsKey('otpPushToken'),
      isFalse,
    );
    expect(messaging.calls, ['permission']);
  });

  test(
      'missing Firebase and empty address omit optional token without a guest installation',
      () async {
    final unavailable = PushNotificationsService(client, session, storage);
    expect(
      (await unavailable.prepareOtpTarget()).containsKey('otpPushToken'),
      isFalse,
    );
    messaging.token = null;
    expect(
      (await push.prepareOtpTarget()).containsKey('otpPushToken'),
      isFalse,
    );
    expect(
      adapter.requests.every((request) => request.method == 'GET'),
      isTrue,
    );
  });

  test(
      'Android permission result permits a token when Firebase reports transient denied',
      () async {
    messaging.authorization = AuthorizationStatus.denied;
    notifications.android.enabled = true;
    expect(
      (await push.prepareOtpTarget())['otpPushToken'],
      'synthetic-fcm-address',
    );
    expect(messaging.calls, ['permission', 'auto:true', 'token']);
  });

  test('push setup failure allows trusted login but cancellation still aborts',
      () async {
    final fallback = LoginProvider(
      client,
      otpPushData: () async => throw StateError('synthetic setup failure'),
    );
    await fallback.login(
      const LoginRequest(
        phone: '777000001',
        password: 'synthetic-password',
        deviceId: 'synthetic-device',
      ),
    );
    expect(adapter.requests, hasLength(1));
    final cancelled = LoginProvider(
      client,
      otpPushData: () async => throw const OtpPushRequestCancelled(),
    );
    await expectLater(
      cancelled.login(
        const LoginRequest(
          phone: '777000001',
          password: 'synthetic-password',
          deviceId: 'synthetic-device',
        ),
      ),
      throwsA(isA<OtpPushRequestCancelled>()),
    );
    expect(adapter.requests, hasLength(1));
  });

  test(
      'foreground OTP displays while unauthenticated and its tap leaves authentication state intact',
      () async {
    await push.prepareOtpTarget();
    Get.put<AuthSessionService>(session);
    await push.handleForegroundMessage(_otpMessage());
    expect(notifications.shown, hasLength(1));
    expect(notifications.shown.single['body'], '123456');
    expect(session.isAuthenticated.value, isFalse);
    push.openNotificationData(_otpMessage().data);
    expect(session.hasPendingNotificationOpen, isFalse);
    await push.handleForegroundMessage(_otpMessage(clientType: 'driver'));
    await push.handleForegroundMessage(
      _otpMessage(
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      ),
    );
    expect(notifications.shown, hasLength(1));
    push.openNotificationData({'action': 'open_active_ride', 'rideId': '10'});
    expect(session.hasPendingNotificationOpen, isTrue);
  });

  test(
      'sign-out invalidates an in-flight OTP token and disables later foreground delivery',
      () async {
    messaging.pendingToken = Completer<String?>();
    final pending = push.prepareOtpTarget();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(messaging.calls, contains('token'));
    await push.onSessionEnded();
    messaging.pendingToken!.complete('synthetic-late-token');
    await expectLater(pending, throwsA(isA<FormatException>()));
    expect(messaging.calls, containsAll(['auto:false', 'delete']));
    expect(storage.pendingTokenClears, 1);
    expect(storage.pendingTokenSaves, 0);
    await push.handleForegroundMessage(_otpMessage());
    expect(notifications.shown, isEmpty);
  });

  for (final phase in [
    'capability',
    'permission',
    'probe',
    'auto-init',
    'token',
  ]) {
    for (final throwsAfterSignOut in [false, true]) {
      test(
          'sign-out during $phase aborts login even when await throws: $throwsAfterSignOut',
          () async {
        final gate = _AwaitGate();
        switch (phase) {
          case 'capability':
            adapter.capabilityGate = gate;
          case 'permission':
            messaging.permissionGate = gate;
          case 'probe':
            notifications.android.probeGate = gate;
          case 'auto-init':
            messaging.autoInitGate = gate;
          case 'token':
            messaging.tokenGate = gate;
        }
        Get.put<PushNotificationsService>(push);
        final pending = LoginProvider(client).login(
          const LoginRequest(
            phone: '777000001',
            password: 'synthetic-password',
            deviceId: 'synthetic-device',
          ),
        );
        await gate.started.future.timeout(const Duration(seconds: 2));
        await push.onSessionEnded();
        if (throwsAfterSignOut) {
          gate.released
              .completeError(StateError('synthetic failure after sign-out'));
        } else {
          gate.released.complete();
        }
        await expectLater(pending, throwsA(isA<OtpPushRequestCancelled>()));
        expect(
          adapter.requests.where((request) => request.method == 'POST'),
          isEmpty,
        );
        expect(storage.pendingTokenSaves, 0);
      });
    }
  }
}
