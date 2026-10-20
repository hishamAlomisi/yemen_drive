import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
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
    final adapter = _Adapter((_) async => _body('{"success":true,"data":[]}'));
    final connection = service(adapter, online: false);
    expect(await connection.verify(), false);
    expect(connection.status.value.failure, StartupFailure.offline);
    expect(adapter.requests, isEmpty);
  });

  test('valid public catalog verifies configured API with no credentials',
      () async {
    final adapter = _Adapter((_) async => _body('{"success":true,"data":[]}'));
    final connection = service(adapter);
    expect(await connection.verify(), true);
    expect(connection.isVerified, true);
    final request = adapter.requests.single;
    expect(request.uri.toString(), 'https://api.example/api/execute');
    expect(request.data, {
      'model': 'ServiceKindModel',
      'operation': 'list',
      'data': <String, Object?>{},
    });
    expect(request.headers.containsKey('Authorization'), false);
  });

  test('HTML, redirects, bad payload and API failures never pass', () async {
    for (final response in [
      _body('{"success":false,"code":"unexpected_error"}'),
      _body('{"success":true,"data":null}'),
      ResponseBody.fromString('<html>WiFi sign in</html>', 200),
      _body('{}', 302),
      _body('{}', 503),
    ]) {
      final connection = service(_Adapter((_) async => response));
      expect(await connection.verify(), false);
      expect(connection.isVerified, false);
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
      return _body('{"success":true,"data":[]}');
    });
    final connection = service(adapter);
    expect(await connection.verify(), false);
    expect(connection.status.value.failure, StartupFailure.unreachable);
    expect(await connection.verify(), true);
    expect(adapter.requests.length, 2);
  });

  test('slow API has a bounded timeout', () async {
    final pending = Completer<ResponseBody>();
    final adapter = _Adapter((_) => pending.future);
    final connection =
        service(adapter, timeout: const Duration(milliseconds: 30));
    expect(await connection.verify(), false);
    expect(connection.status.value.failure, StartupFailure.timeout);
    pending.complete(_body('{"success":true,"data":[]}'));
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
    pending.complete(_body('{"success":true,"data":[]}'));
    expect(await first, true);
    expect(await second, true);
  });
}
