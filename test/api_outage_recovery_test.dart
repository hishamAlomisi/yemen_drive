import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:yemen_drive/core/config/app_environment.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/realtime/realtime_state_binding.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/services/startup_connection_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/location_selection/repositories/route_repository.dart';

class _Storage extends SecureStorageService {
  String? access = 'existing-access', refresh = 'existing-refresh';
  int clears = 0, replacements = 0;
  Completer<String?>? pendingAccess;
  final accessStarted = Completer<void>();
  @override
  Future<String?> get accessToken {
    if (!accessStarted.isCompleted) accessStarted.complete();
    return pendingAccess?.future ?? Future.value(access);
  }

  @override
  Future<String?> get refreshToken async => refresh;
  @override
  Future<bool> get rememberMe async => true;
  @override
  Future<String?> get deviceId async => 'test-device';
  @override
  Future<int?> get authenticatedUserId async => 7;
  @override
  Future<void> saveDeviceId(String value) async {}
  @override
  Future<void> replaceTokens(
      {required String accessToken, required String refreshToken}) async {
    access = accessToken;
    refresh = refreshToken;
    replacements++;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
    clears++;
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(String body, [int status = 200]) =>
    ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    Get.testMode = true;
    AppEnvironment.configure(baseUrl: 'https://outage.invalid/api');
  });
  tearDown(Get.reset);

  StartupConnectionService availability() {
    final probe = Dio()
      ..httpClientAdapter = _Adapter(
          (_) async => _body('{"success":true,"data":{"ready":true}}'));
    return Get.put(StartupConnectionService(
        probe: probe,
        networkCheck: () async => [ConnectivityResult.wifi],
        networkChanges: const Stream.empty()));
  }

  test(
      'malformed proxy 502 closes gate, preserves tokens, and never replays writes on recovery',
      () async {
    final connection = availability();
    final storage = _Storage();
    var healthy = false;
    final adapter = _Adapter((_) async => healthy
        ? _body('{"success":true,"data":{"id":8}}')
        : _body('<html>Bad Gateway</html>', 502));
    final client = await ApiClient(storage).init();
    client.dio.httpClientAdapter = adapter;
    addTearDown(() => client.dio.close(force: true));
    expect(
        await client.execute<Object?>(model: 'RideModel', operation: 'update'),
        isA<ApiFailure<Object?>>());
    expect(connection.runtimeUnavailable.value, true);
    expect(await client.execute<Object?>(model: 'RideModel', operation: 'add'),
        isA<ApiFailure<Object?>>());
    expect(adapter.requests.length, 1);
    healthy = true;
    expect(await connection.retryConnection(), true);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requests.length, 1,
        reason: 'recovery must not repeat an ambiguous write');
    expect(storage.access, 'existing-access');
    expect(storage.clears, 0);
    expect(await client.execute<Object?>(model: 'RideModel', operation: 'add'),
        isA<ApiSuccess<Object?>>());
    expect(adapter.requests.length, 2);
  });

  test(
      'an outage discovered while secure storage is pending blocks the mutation before dispatch',
      () async {
    final connection = availability();
    final storage = _Storage()..pendingAccess = Completer<String?>();
    final adapter = _Adapter((_) async => _body('{"success":true,"data":{}}'));
    final client = await ApiClient(storage).init();
    client.dio.httpClientAdapter = adapter;
    addTearDown(() => client.dio.close(force: true));
    final mutation =
        client.execute<Object?>(model: 'RideModel', operation: 'update');
    await storage.accessStarted.future;
    connection.reportRequestFailure(DioException(
        requestOptions: RequestOptions(path: 'execute'),
        type: DioExceptionType.connectionError));
    storage.pendingAccess!.complete('existing-access');
    expect(await mutation, isA<ApiFailure<Object?>>());
    expect(adapter.requests, isEmpty);
    expect(storage.clears, 0);
  });

  test(
      'valid map business failure keeps the global gate open and preserves the server reason',
      () async {
    final connection = availability();
    final client = await ApiClient(_Storage()).init();
    client.dio.httpClientAdapter = _Adapter((_) async => _body(
        '{"success":false,"title":"Route unavailable","detail":"خدمة المسارات غير مهيأة على الخادم","code":"routes_not_configured"}',
        503));
    addTearDown(() => client.dio.close(force: true));
    await expectLater(
        ApiRoutesRepository(client).getDrivingRoute(
            origin: const LatLng(15.3, 44.1),
            destination: const LatLng(15.4, 44.2)),
        throwsA(isA<RouteRequestException>()
            .having((e) => e.message, 'server reason',
                'خدمة المسارات غير مهيأة على الخادم')
            .having((e) => e.code, 'server code', 'routes_not_configured')));
    expect(connection.runtimeUnavailable.value, false);
  });

  test(
      'failed request after a successful token refresh completes instead of hanging',
      () async {
    final connection = availability();
    final storage = _Storage();
    final refreshAdapter = _Adapter((_) async => _body(
        '{"success":true,"data":{"accessToken":"new-access","refreshToken":"new-refresh"}}'));
    final refresh = Dio()..httpClientAdapter = refreshAdapter;
    var attempts = 0;
    final adapter = _Adapter((_) async => ++attempts == 1
        ? _body('{"success":false,"code":"session_expired"}', 401)
        : _body('<html>Bad Gateway</html>', 502));
    final client = await ApiClient(storage, refreshClient: refresh).init();
    client.dio.httpClientAdapter = adapter;
    addTearDown(() {
      client.dio.close(force: true);
      refresh.close(force: true);
    });
    final result = await client
        .execute<Object?>(model: 'UserModel', operation: 'get')
        .timeout(const Duration(seconds: 2));
    expect(result, isA<ApiFailure<Object?>>());
    expect(attempts, 2);
    expect(storage.replacements, 1);
    expect(storage.clears, 0);
    expect(connection.runtimeUnavailable.value, true);
  });

  test('token refresh has a bounded timeout and retains the existing session',
      () async {
    final connection = availability();
    final storage = _Storage();
    final pending = Completer<ResponseBody>();
    final refreshAdapter = _Adapter((_) => pending.future);
    final refresh = Dio()..httpClientAdapter = refreshAdapter;
    final client = await ApiClient(storage,
            refreshClient: refresh,
            refreshTimeout: const Duration(milliseconds: 30))
        .init();
    client.dio.httpClientAdapter = _Adapter(
        (_) async => _body('{"success":false,"code":"session_expired"}', 401));
    addTearDown(() {
      client.dio.close(force: true);
      refresh.close(force: true);
    });
    final result = await client
        .execute<Object?>(model: 'UserModel', operation: 'get')
        .timeout(const Duration(seconds: 2));
    expect(result, isA<ApiFailure<Object?>>());
    expect(connection.runtimeUnavailable.value, true);
    expect(storage.clears, 0);
    expect(storage.access, 'existing-access');
    expect(refreshAdapter.requests.single.connectTimeout,
        const Duration(milliseconds: 30));
    pending.complete(_body('{"success":false}'));
  });

  test(
      'stored authentication survives a valid API 503 during startup validation',
      () async {
    availability();
    final storage = _Storage();
    final client = await ApiClient(storage).init();
    client.dio.httpClientAdapter = _Adapter((_) async => _body(
        '{"success":false,"message":"database unavailable","code":"unexpected_error"}',
        503));
    addTearDown(() => client.dio.close(force: true));
    final session = await AuthSessionService(storage, client).init();
    expect(session.isAuthenticated.value, true);
    expect(session.currentUserId.value, 7);
    expect(storage.clears, 0);
  });

  test('stored authentication survives a malformed JSON success response',
      () async {
    final connection = availability();
    final storage = _Storage();
    final client = await ApiClient(storage).init();
    client.dio.httpClientAdapter =
        _Adapter((_) async => _body('{"proxy":"temporarily unavailable"}'));
    addTearDown(() => client.dio.close(force: true));
    final session = await AuthSessionService(storage, client).init();
    expect(session.isAuthenticated.value, true);
    expect(storage.clears, 0);
    expect(connection.runtimeUnavailable.value, true);
  });

  test(
      'API recovery refreshes canonical screen data once and respects disposal',
      () async {
    final connection = availability();
    var reads = 0;
    final binding = RealtimeStateBinding(
      owner: Object(),
      resources: {'wallet'},
      accepts: (_) => true,
      refresh: () async {
        reads++;
      },
    );
    connection.reportRequestFailure(DioException(
      requestOptions: RequestOptions(path: 'execute'),
      type: DioExceptionType.connectionError,
    ));
    expect(await connection.retryConnection(), true);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(reads, 1);
    expect(await connection.retryConnection(), true);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1, reason: 'a healthy heartbeat is not a recovery event');
    binding.dispose();
    connection.reportRequestFailure(DioException(
      requestOptions: RequestOptions(path: 'execute'),
      type: DioExceptionType.connectionError,
    ));
    expect(await connection.retryConnection(), true);
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1, reason: 'a discarded screen must not be refreshed');
  });
}
