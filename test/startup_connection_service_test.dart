import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_drive/core/config/app_environment.dart';
import 'package:yemen_drive/core/services/startup_connection_service.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];
  final started = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    if (!started.isCompleted) started.complete();
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(String json, [int status = 200]) => ResponseBody.fromString(
      json,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => AppEnvironment.configure(baseUrl: 'https://api.example/api'));

  StartupConnectionService service(
    _Adapter adapter, {
    bool online = true,
    Duration timeout = const Duration(seconds: 8),
  }) {
    final dio = Dio()..httpClientAdapter = adapter;
    final connection = StartupConnectionService(
      probe: dio,
      networkCheck: () async =>
          [online ? ConnectivityResult.wifi : ConnectivityResult.none],
      requestTimeout: timeout,
    );
    addTearDown(connection.onClose);
    return connection;
  }

  test('disabled interfaces fail without requesting the server', () async {
    final adapter =
        _Adapter((_) async => _body('{"success":true,"data":{"ready":true}}'));
    final connection = service(adapter, online: false);
    expect(await connection.verify(), false);
    expect(connection.status.value.failure, StartupFailure.offline);
    expect(adapter.requests, isEmpty);
  });

  test(
      'lightweight readiness verifies configured API without catalog or credentials',
      () async {
    final adapter =
        _Adapter((_) async => _body('{"success":true,"data":{"ready":true}}'));
    final connection = service(adapter);
    expect(await connection.verify(), true);
    expect(connection.isVerified, true);
    final request = adapter.requests.single;
    expect(request.uri.toString(), 'https://api.example/api/health/ready');
    expect(request.method, 'GET');
    expect(request.data, isNull);
    expect(request.headers.containsKey('Authorization'), false);
  });

  test('HTML, redirects, bad payload and API failures never pass', () async {
    for (final response in [
      _body('{"success":false,"code":"unexpected_error"}'),
      _body('{"success":true,"data":null}'),
      _body('{"success":true,"data":{"ready":false}}'),
      _body('{"success":true,"data":[]}'),
      ResponseBody.fromString('<html>WiFi sign in</html>', 200),
      _body('{}', 302),
      _body('{}', 503),
    ]) {
      final connection = service(_Adapter((_) async => response));
      expect(await connection.verify(), false);
      expect(connection.isVerified, false);
    }
  });

  test('older APIs fall back once only for a missing readiness endpoint',
      () async {
    for (final missing in [404, 405]) {
      final adapter = _Adapter((request) async => request.method == 'GET'
          ? _body('{}', missing)
          : _body('{"success":true,"data":[]}'));
      final connection = service(adapter);
      expect(await connection.verify(), true);
      expect(await connection.verify(), true);
      expect(adapter.requests.map((r) => r.method), ['GET', 'POST', 'POST']);
      expect(adapter.requests.last.data, {
        'model': 'ServiceKindModel',
        'operation': 'list',
        'data': <String, Object?>{},
      });
    }
  });

  test('readiness overload never causes another catalog request', () async {
    for (final status in [401, 429, 500, 503]) {
      final adapter = _Adapter((_) async => _body('{}', status));
      expect(await service(adapter).verify(), false);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.method, 'GET');
    }
  });

  test('unreachable API can be retried successfully', () async {
    var attempt = 0;
    final adapter = _Adapter((options) async {
      if (attempt++ == 0) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      return _body('{"success":true,"data":{"ready":true}}');
    });
    final connection = service(adapter);
    expect(await connection.verify(), false);
    expect(connection.status.value.failure, StartupFailure.unreachable);
    expect(await connection.verify(), false);
    expect(await connection.retryConnection(), true);
    expect(adapter.requests.length, 2);
  });

  test('slow API has a bounded timeout', () async {
    final pending = Completer<ResponseBody>();
    final adapter = _Adapter((_) => pending.future);
    final connection =
        service(adapter, timeout: const Duration(milliseconds: 30));
    expect(await connection.verify(), false);
    expect(connection.status.value.failure, StartupFailure.timeout);
    pending.complete(_body('{"success":true,"data":{"ready":true}}'));
    await Future<void>.delayed(Duration.zero);
    expect(connection.isVerified, false);
  });

  test('concurrent retries share the same in-flight request', () async {
    final pending = Completer<ResponseBody>();
    final adapter = _Adapter((_) => pending.future);
    final connection = service(adapter);
    final first = connection.verify();
    final second = connection.verify();
    await adapter.started.future;
    expect(adapter.requests.length, 1);
    pending.complete(_body('{"success":true,"data":{"ready":true}}'));
    expect(await first, true);
    expect(await second, true);
  });

  test('business responses and cancellation never close the global gate',
      () async {
    final connection = service(
        _Adapter((_) async => _body('{"success":true,"data":{"ready":true}}')));
    await connection.verify();
    for (final code in [
      'routes_not_configured',
      'places_not_configured',
      'route_not_found',
      'unexpected_error',
    ]) {
      final options = RequestOptions(path: '/api/execute');
      expect(
          connection.reportRequestFailure(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<Object?>(
              requestOptions: options,
              statusCode: 503,
              data: {'success': false, 'code': code},
            ),
          )),
          false);
    }
    expect(
        connection.reportRequestFailure(DioException(
          requestOptions: RequestOptions(path: '/api/execute'),
          type: DioExceptionType.cancel,
        )),
        false);
    expect(connection.runtimeUnavailable.value, false);
    expect(connection.isVerified, true);
  });

  test('an old successful probe cannot erase a newer transport outage',
      () async {
    final pending = Completer<ResponseBody>();
    var attempt = 0;
    final adapter = _Adapter((_) => attempt++ == 0
        ? pending.future
        : Future.value(_body('{"success":true,"data":{"ready":true}}')));
    final connection = service(adapter);
    final first = connection.verify();
    await adapter.started.future;
    connection.reportRequestFailure(DioException(
      requestOptions: RequestOptions(path: '/api/execute'),
      type: DioExceptionType.connectionError,
    ));
    pending.complete(_body('{"success":true,"data":{"ready":true}}'));
    expect(await first, false);
    expect(connection.runtimeUnavailable.value, true);
    final restored = connection.recovered.first;
    expect(await connection.retryConnection(), true);
    await restored;
    expect(connection.runtimeUnavailable.value, false);
  });

  test('monitor pauses probes in background and checks immediately on resume',
      () {
    fakeAsync((clock) {
      final adapter = _Adapter(
          (_) async => _body('{"success":true,"data":{"ready":true}}'));
      final connection = StartupConnectionService(
        probe: Dio()..httpClientAdapter = adapter,
        networkCheck: () async => [ConnectivityResult.wifi],
        networkChanges: const Stream.empty(),
        healthyInterval: const Duration(milliseconds: 15),
        retryInterval: const Duration(milliseconds: 10),
      );
      addTearDown(connection.onClose);
      unawaited(connection.verify());
      clock.elapse(Duration.zero);
      connection.startMonitoring();
      connection.didChangeAppLifecycleState(AppLifecycleState.paused);
      clock.elapse(const Duration(milliseconds: 45));
      expect(adapter.requests.length, 1);
      connection.didChangeAppLifecycleState(AppLifecycleState.resumed);
      clock.elapse(Duration.zero);
      expect(adapter.requests.length, 2);
      connection.stopMonitoring();
      clock.elapse(const Duration(milliseconds: 30));
      expect(adapter.requests.length, 2);
    });
  });

  test('real HTTP restart automatically recovers and never replays writes',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      HttpServer? server;
      var port = 0;
      final requests = <String>[];
      Future<void> listen() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        port = server!.port;
        server!.listen((request) async {
          final bytes = await request
              .fold<List<int>>(<int>[], (buffer, part) => buffer..addAll(part));
          requests.add(
              '${request.method} ${request.uri.path} ${utf8.decode(bytes)}');
          request.response.headers.contentType = ContentType.json;
          request.response.persistentConnection = false;
          request.response.write('{"success":true,"data":{"ready":true}}');
          await request.response.close();
        });
      }

      await listen();
      final connection = StartupConnectionService(
        baseUrl: 'http://127.0.0.1:$port/api',
        networkCheck: () async => [ConnectivityResult.wifi],
        networkChanges: const Stream.empty(),
        requestTimeout: const Duration(milliseconds: 300),
        healthyInterval: const Duration(milliseconds: 25),
        retryInterval: const Duration(milliseconds: 25),
      );
      var recoveries = 0;
      final subscription = connection.recovered.listen((_) => recoveries++);
      try {
        expect(await connection.verify(), true);
        connection.startMonitoring();
        final outage =
            connection.runtimeUnavailable.stream.firstWhere((v) => v);
        await server!.close(force: true);
        server = null;
        await outage.timeout(const Duration(seconds: 3));
        expect(connection.isVerified, false);
        final restored = connection.recovered.first;
        await listen();
        await restored.timeout(const Duration(seconds: 3));
        expect(connection.isVerified, true);
        expect(connection.runtimeUnavailable.value, false);
        await connection.verify();
        expect(recoveries, 1);
        expect(requests, isNotEmpty);
        expect(requests.every((request) => request == 'GET /api/health/ready '),
            true);
      } finally {
        connection.onClose();
        await subscription.cancel();
        await server?.close(force: true);
      }
    }, _RealHttp());
  });

  test('rapid pause and resume replaces an invalidated in-flight probe',
      () async {
    final pending = Completer<ResponseBody>();
    final secondStarted = Completer<void>();
    var calls = 0;
    final adapter = _Adapter((_) {
      if (++calls == 2) {
        secondStarted.complete();
        return pending.future;
      }
      return Future.value(_body('{"success":true,"data":{"ready":true}}'));
    });
    final connection = StartupConnectionService(
      probe: Dio()..httpClientAdapter = adapter,
      networkCheck: () async => [ConnectivityResult.wifi],
      networkChanges: const Stream.empty(),
      healthyInterval: const Duration(minutes: 1),
    );
    addTearDown(connection.onClose);
    await connection.verify();
    connection.startMonitoring();
    final old = connection.checkNow();
    await secondStarted.future;
    connection.didChangeAppLifecycleState(AppLifecycleState.paused);
    connection.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final resumed = connection.checkNow();
    pending.complete(_body('{"success":true,"data":{"ready":true}}'));
    expect(await old, false);
    expect(await resumed.timeout(const Duration(seconds: 1)), true);
    expect(calls, 3);
    expect(connection.isVerified, true);
  });

  test('network recovery and resume share a probe and recover without a tap',
      () async {
    final changes = StreamController<List<ConnectivityResult>>();
    var online = true;
    final pending = Completer<ResponseBody>();
    var calls = 0;
    final adapter = _Adapter((_) => ++calls == 1
        ? Future.value(_body('{"success":true,"data":{"ready":true}}'))
        : pending.future);
    final connection = StartupConnectionService(
      probe: Dio()..httpClientAdapter = adapter,
      networkCheck: () async =>
          [online ? ConnectivityResult.wifi : ConnectivityResult.none],
      networkChanges: changes.stream,
      healthyInterval: const Duration(minutes: 1),
      retryInterval: const Duration(milliseconds: 10),
    );
    addTearDown(() async {
      connection.onClose();
      await changes.close();
    });
    expect(await connection.verify(), true);
    connection.startMonitoring();
    online = false;
    changes.add([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    expect(connection.runtimeUnavailable.value, true);
    connection.didChangeAppLifecycleState(AppLifecycleState.paused);
    online = true;
    changes.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    final restored = connection.recovered.first;
    connection.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final checks = List.generate(20, (_) => connection.checkNow());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 2);
    pending.complete(_body('{"success":true,"data":{"ready":true}}'));
    expect(await Future.wait(checks), everyElement(isTrue));
    await restored;
    expect(connection.runtimeUnavailable.value, false);
  });

  test(
      'successful traffic postpones idle health probes and rejects stale failure',
      () async {
    final pending = Completer<ResponseBody>();
    final adapter = _Adapter((_) => pending.future);
    final connection = service(adapter);
    final oldProbe = connection.verify();
    await adapter.started.future;
    connection.reportRequestSuccess();
    pending.complete(_body('{}', 503));
    expect(await oldProbe, false);
    expect(connection.isVerified, true);
    expect(connection.runtimeUnavailable.value, false);
  });

  test('5xx business envelope triggers health verification without gating it',
      () async {
    final adapter =
        _Adapter((_) async => _body('{"success":true,"data":{"ready":true}}'));
    final connection = StartupConnectionService(
      probe: Dio()..httpClientAdapter = adapter,
      networkCheck: () async => [ConnectivityResult.wifi],
      networkChanges: const Stream.empty(),
      healthyInterval: const Duration(minutes: 1),
    );
    addTearDown(connection.onClose);
    await connection.verify();
    connection.startMonitoring();
    final options = RequestOptions(path: '/api/execute');
    connection.reportRequestFailure(DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<Object?>(
          requestOptions: options,
          statusCode: 503,
          data: {'success': false, 'code': 'routes_not_configured'}),
    ));
    expect(connection.runtimeUnavailable.value, false);
    await connection.checkNow();
    expect(adapter.requests.length, 2);
    expect(connection.runtimeUnavailable.value, false);
  });
}

class _RealHttp extends HttpOverrides {}
