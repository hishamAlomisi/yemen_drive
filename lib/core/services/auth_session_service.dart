import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/routes/auth_routes.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../network/api_models.dart';
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
  late final String deviceId;

  Future<AuthSessionService> init() async {
    _apiClient.onSessionExpired = _handleServerSessionExpired;
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
    if (result is ApiSuccess) return;

    final failure = result as ApiFailure<Object?>;
    // Do not sign a customer out solely because the device is temporarily
    // offline. Any completed server rejection means the stored session is no
    // longer usable and must not keep the UI in a false signed-in state.
    if (failure.problem.code == 'network_error' ||
        failure.problem.code == 'invalid_response') {
      return;
    }
    await _storage.clear();
    isAuthenticated.value = false;
    currentUserId.value = null;
    rememberLogin.value = false;
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
    Get.offAllNamed<void>(route, arguments: arguments);
  }

  Future<void> signOut({bool revokeServerSession = true}) async {
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
    await _storage.clear();
    rememberLogin.value = false;
    isAuthenticated.value = false;
    currentUserId.value = null;
    if (navigate && Get.key.currentState != null) {
      Get.offAllNamed<void>('/home');
    }
  }
}
