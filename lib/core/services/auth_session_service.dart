import 'dart:async';

import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/routes/auth_routes.dart';
import '../../features/ride/ride_routes.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../network/api_models.dart';
import '../realtime/tracking_hub_service.dart';
import '../storage/secure_storage_service.dart';

class AuthSessionService extends GetxService {
  AuthSessionService(this._storage, this._apiClient);

  final SecureStorageService _storage;
  final ApiClient _apiClient;
  final RxBool isAuthenticated = false.obs;
  final RxBool rememberLogin = false.obs;
  final RxnInt currentUserId = RxnInt();

  String? _pendingRoute;
  Object? _pendingArguments;
  bool _pendingNotificationOpen = false;
  late final String deviceId;
  Future<void> Function()? onAuthenticated;
  Future<void> Function()? onSignedOut;
  Future<void> Function()? onSessionEnded;

  bool get hasPendingNotificationOpen => _pendingNotificationOpen;

  Future<AuthSessionService> init() async {
    _apiClient.onSessionExpired = _handleServerSessionExpired;
    if (Get.isRegistered<TrackingHubService>()) {
      Get.find<TrackingHubService>().onSessionRevoked =
          _handleServerSessionExpired;
    }
    deviceId = await _storage.deviceId ?? const Uuid().v4();
    await _storage.saveDeviceId(deviceId);
    rememberLogin.value = await _storage.rememberMe;

    if (!rememberLogin.value) {
      await _storage.clear();
      isAuthenticated.value = false;
      return this;
    }

    final accessToken = await _storage.accessToken;
    final refreshToken = await _storage.refreshToken;
    isAuthenticated.value = (accessToken?.isNotEmpty ?? false) ||
        (refreshToken?.isNotEmpty ?? false);
    currentUserId.value = await _storage.authenticatedUserId;
    if (isAuthenticated.value) {
      await _validateStoredSession();
    }
    return this;
  }

  Future<void> _validateStoredSession() async {
    // A token-shaped value in encrypted storage is not proof that it is still
    // accepted by the server. Use the existing protected profile operation as
    // a lightweight validation request and never log the token itself.
    final result = await _apiClient.execute<Object?>(
      model: 'UserModel',
      operation: 'get',
      data: const <String, Object?>{},
    );
    if (result is ApiSuccess<Object?>) {
      if (_hasExpectedAccountType(result.data)) return;
      await _clearLocalSession(navigate: false);
      return;
    }

    final failure = result as ApiFailure<Object?>;
    // Do not sign a customer out solely because the device is temporarily
    // offline. Any completed server rejection means the stored session is no
    // longer usable and must not keep the UI in a false signed-in state.
    if (failure.problem.code == 'network_error' ||
        failure.problem.code == 'invalid_response') {
      return;
    }
    await _clearLocalSession(navigate: false);
  }

  bool _hasExpectedAccountType(Object? value) {
    if (value is! Map) return false;
    final role = value['role'] ?? value['Role'];
    if (role is num) return role.toInt() == 0;
    return role?.toString().toLowerCase() == 'customer';
  }

  Future<void> activate({
    required String accessToken,
    required String refreshToken,
    required bool remember,
    int? userId,
  }) async {
    await _storage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    if (userId != null) await _storage.saveAuthenticatedUserId(userId);
    await _storage.setRememberMe(remember);
    rememberLogin.value = remember;
    isAuthenticated.value = true;
    currentUserId.value = userId;
    // Push registration belongs to every authenticated session. The
    // persistence choice only determines whether this session survives an
    // application restart; it must never behave like a sign-out.
    unawaited(onAuthenticated?.call());
  }

  bool requireAuthentication({
    required String returnRoute,
    Object? arguments,
  }) {
    if (isAuthenticated.value) return true;
    _pendingRoute = returnRoute;
    _pendingArguments = arguments;
    Get.toNamed<void>(AuthRoutes.signIn);
    return false;
  }

  void continueAfterAuthentication({String fallbackRoute = '/home'}) {
    final route = _pendingRoute ?? fallbackRoute;
    final arguments = _pendingArguments;
    _pendingRoute = null;
    _pendingArguments = null;
    _pendingNotificationOpen = false;
    Get.offAllNamed<void>(route, arguments: arguments);
  }

  void openNotificationFromPush(Map<String, dynamic> data) {
    final payload = _safePushPayload(data);
    if (payload.isEmpty) return;
    final arguments = <String, Object?>{'pushNotification': payload};
    _pendingRoute = RideRoutes.homeTransport;
    _pendingArguments = arguments;
    _pendingNotificationOpen = true;

    if (!isAuthenticated.value) {
      if (Get.key.currentState != null) {
        Get.offAllNamed<void>(AuthRoutes.signIn);
      }
      return;
    }

    if (Get.key.currentState != null) {
      _pendingRoute = null;
      _pendingArguments = null;
      _pendingNotificationOpen = false;
      Get.offAllNamed<void>(RideRoutes.homeTransport, arguments: arguments);
    }
  }

  Map<String, String> _safePushPayload(Map<String, dynamic> data) {
    const allowedKeys = <String>{
      'notificationId',
      'notificationType',
      'action',
      'rideId',
      'offerId',
      'paymentId',
      'walletTransactionId',
      'cashCollectionApprovalId',
      'cashPaymentRequestId',
      'cancellationRequestId',
      'messageId',
      'safetyIncidentId',
      'safetyRecordingId',
      'driverSettlementPaymentId',
      'status',
      'approved',
      'settled',
    };
    final result = <String, String>{};
    for (final entry in data.entries) {
      if (!allowedKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value is! String && value is! num && value is! bool) continue;
      final text = '$value'.trim();
      if (text.isNotEmpty && text.length <= 256) result[entry.key] = text;
    }
    return result;
  }

  Future<void> signOut({bool revokeServerSession = true}) async {
    await onSignedOut?.call();
    if (revokeServerSession) {
      try {
        await _apiClient.dio.post<Object?>(ApiEndpoints.logout);
      } on Object {
        // Local sign-out must still finish when the device is offline.
      }
    }
    await _clearLocalSession(navigate: true);
  }

  Future<void> _handleServerSessionExpired() =>
      _clearLocalSession(navigate: true);

  Future<void> _clearLocalSession({required bool navigate}) async {
    await onSessionEnded?.call();
    if (Get.isRegistered<TrackingHubService>()) {
      await Get.find<TrackingHubService>().disconnect();
    }
    await _storage.clear();
    rememberLogin.value = false;
    isAuthenticated.value = false;
    currentUserId.value = null;
    if (navigate && Get.key.currentState != null) {
      Get.offAllNamed<void>('/home');
    }
  }
}
