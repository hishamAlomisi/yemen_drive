import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../storage/secure_storage_service.dart';
import 'auth_session_service.dart';

const String pushNotificationChannelId = 'yemendrive_alerts';

@pragma('vm:entry-point')
Future<void> firebasePushBackgroundHandler(RemoteMessage message) async {
  // Android presents notification payloads in the system tray while the app is
  // in the background. Keep this entry point initialized for data callbacks.
  await Firebase.initializeApp();
}

class PushNotificationsService extends GetxService with WidgetsBindingObserver {
  PushNotificationsService(this._client, this._session, this._storage);

  final ApiClient _client;
  final AuthSessionService _session;
  final SecureStorageService _storage;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  FirebaseMessaging? _messaging;
  bool _registrationInProgress = false;
  bool _registrationAttemptedForSession = false;
  bool _registrationEnabled = false;
  bool _tokenSyncInProgress = false;
  int _retryAttempt = 0;
  Timer? _retryTimer;

  Future<PushNotificationsService> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return this;

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(firebasePushBackgroundHandler);
    _messaging = FirebaseMessaging.instance;
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        _openPayload(response.payload);
      },
    );
    final androidNotifications =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidNotifications?.createNotificationChannel(
      const AndroidNotificationChannel(
        pushNotificationChannelId,
        'إشعارات يمن درايف',
        description: 'تحديثات الرحلات والدفع والحساب',
        importance: Importance.high,
        playSound: true,
      ),
    );

    _subscriptions
        .add(FirebaseMessaging.onMessage.listen(_showForegroundNotification));
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _openData(message.data);
      }),
    );
    _subscriptions.add(
      _messaging!.onTokenRefresh.listen((token) {
        unawaited(_queueTokenForSync(token));
      }),
    );

    final localLaunch =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (localLaunch?.didNotificationLaunchApp == true) {
      _openPayload(localLaunch?.notificationResponse?.payload);
    }
    final initialMessage = await _messaging!.getInitialMessage();
    if (initialMessage != null) _openData(initialMessage.data);

    if (_isEligible) {
      unawaited(onAuthenticated());
    } else {
      await _disableLocalRegistration();
    }
    return this;
  }

  bool get _isEligible => _session.isAuthenticated.value;

  Future<void> onAuthenticated() async {
    final messaging = _messaging;
    if (messaging == null ||
        !_isEligible ||
        _registrationInProgress ||
        _registrationAttemptedForSession) {
      return;
    }

    _registrationInProgress = true;
    _registrationAttemptedForSession = true;
    try {
      // A notification permission governs whether Android displays the push;
      // it must not prevent the authenticated device from registering its FCM
      // address. This matters on Android versions and emulators that report a
      // transient `denied` state before a channel has been shown.
      try {
        await messaging.requestPermission();
      } on Object {
        // Registering the device and prompting for notification permission are
        // independent operations. A later resume will ask again if needed.
      }
      if (!_isEligible) return;

      await messaging.setAutoInitEnabled(true);
      _registrationEnabled = true;
      await _syncPendingToken();
    } on Object {
      // Keep retrying after Firebase or the API is temporarily unavailable.
      _registrationAttemptedForSession = false;
      _scheduleRetry();
    } finally {
      _registrationInProgress = false;
    }
  }

  Future<void> onSignedOut() async {
    if (_session.isAuthenticated.value) {
      try {
        await _client.dio.delete<Object?>(
          '${ApiEndpoints.pushInstallations}/${Uri.encodeComponent(_session.deviceId)}',
        );
      } on Object {
        // The local device must still stop receiving pushes when offline.
      }
    }
    await _disableLocalRegistration();
  }

  Future<void> onSessionEnded() => _disableLocalRegistration();

  Future<void> _disableLocalRegistration() async {
    _registrationAttemptedForSession = false;
    _registrationEnabled = false;
    _tokenSyncInProgress = false;
    _retryAttempt = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _storage.clearPendingPushToken();
    final messaging = _messaging;
    if (messaging == null) return;
    try {
      await messaging.setAutoInitEnabled(false);
      await messaging.deleteToken();
    } on Object {
      // Best effort: session state and local navigation remain authoritative.
    }
  }

  bool _isAuthorized(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  Future<void> _queueTokenForSync(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return;
    try {
      await _storage.savePendingPushToken(normalized);
    } on Object {
      // Continue with the in-memory token even if secure storage is
      // temporarily unavailable on a restored emulator or device.
    }
    await _registerToken(normalized);
  }

  Future<void> _syncPendingToken() async {
    final pendingToken = await _storage.pendingPushToken;
    if (pendingToken != null && pendingToken.isNotEmpty) {
      await _registerToken(pendingToken);
      return;
    }
    try {
      final token = await _messaging?.getToken();
      if (token == null || token.trim().isEmpty) {
        _scheduleRetry();
        return;
      }
      await _queueTokenForSync(token);
    } on Object {
      _scheduleRetry();
    }
  }

  Future<void> _registerToken(String token) async {
    if (!_registrationEnabled || !_isEligible || token.isEmpty) return;
    if (_tokenSyncInProgress) return;

    _tokenSyncInProgress = true;
    var hasNewerToken = false;
    try {
      final response = await _client.dio.post<Object?>(
        ApiEndpoints.pushInstallations,
        data: <String, Object?>{
          'deviceId': _session.deviceId,
          'fcmToken': token,
          'platform': 'android',
        },
      );
      final body = response.data;
      if (body is Map && body['success'] != true) {
        throw StateError('Push installation was not accepted by the API.');
      }
      final pendingToken = await _storage.pendingPushToken;
      if (pendingToken == token) {
        await _storage.clearPendingPushToken();
      } else {
        hasNewerToken = true;
      }
      _retryAttempt = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
    } on Object {
      // Keep the token locally and retry registration. The server cannot send
      // any notification until this authenticated device has been registered.
      _scheduleRetry();
    } finally {
      _tokenSyncInProgress = false;
    }
    if (hasNewerToken && _registrationEnabled && _isEligible) {
      unawaited(_syncPendingToken());
    }
  }

  void _scheduleRetry() {
    if (!_registrationEnabled || !_isEligible || _retryTimer != null) return;
    const delays = <Duration>[
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ];
    final delay = delays[_retryAttempt.clamp(0, delays.length - 1).toInt()];
    _retryAttempt += 1;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (_registrationEnabled && _isEligible) {
        unawaited(_syncPendingToken());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isEligible) {
      if (_registrationEnabled) {
        unawaited(_syncPendingToken());
      } else {
        unawaited(onAuthenticated());
      }
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final payload = Map<String, Object?>.from(message.data);
    await _localNotifications.show(
      id: int.tryParse('${message.data['notificationId'] ?? ''}') ??
          message.hashCode,
      title: notification.title ?? 'يمن درايف',
      body: notification.body ?? '',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          pushNotificationChannelId,
          'إشعارات يمن درايف',
          channelDescription: 'تحديثات الرحلات والدفع والحساب',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_yemendrive',
          category: AndroidNotificationCategory.status,
          styleInformation: BigTextStyleInformation(
            notification.body ?? '',
            contentTitle: notification.title ?? 'يمن درايف',
          ),
        ),
      ),
      payload: jsonEncode(payload),
    );
  }

  void _openPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) _openData(Map<String, dynamic>.from(decoded));
    } on Object {
      // Ignore malformed payloads and preserve normal app startup.
    }
  }

  void _openData(Map<String, dynamic> data) {
    if (!Get.isRegistered<AuthSessionService>()) return;
    Get.find<AuthSessionService>().openNotificationFromPush(data);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.onClose();
  }
}
