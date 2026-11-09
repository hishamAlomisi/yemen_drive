import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/core/config/app_environment.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/negotiation/repositories/ride_negotiation_repository.dart';

class _Storage extends SecureStorageService {
  String? token = 'account-one';
  @override
  Future<String?> get accessToken async => token;
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final responses = <Completer<ResponseBody>>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelled) {
    requests.add(options);
    final response = Completer<ResponseBody>();
    responses.add(response);
    return response.future;
  }

  void complete(int index, [int id = 42]) => responses[index].complete(
        ResponseBody.fromString('{"success":true,"data":{"id":$id}}', 200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            }),
      );
  @override
  void close({bool force = false}) {}
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    Get.testMode = true;
    AppEnvironment.configure(baseUrl: 'https://coalesce.invalid/api');
  });
  tearDown(Get.reset);

  test('a server invalidation separates old reads while new owners still share',
      () async {
    final adapter = _Adapter();
    final api = await ApiClient(_Storage()).init();
    api.dio.httpClientAdapter = adapter;
    addTearDown(() => api.dio.close(force: true));
    Future<ApiResult<Object?>> read() => api.execute<Object?>(
        model: 'RideModel',
        operation: 'get',
        data: {'id': '7', 'includeRouteHistory': false});
    final old = read();
    await _settle();
    api.invalidatePendingReads();
    final newOwner = read(), secondOwner = read();
    await _settle();
    expect(adapter.requests, hasLength(2));
    adapter.complete(0, 1);
    expect((await old as ApiSuccess).data, {'id': 1});
    // Old completion cannot evict the newer in-flight request.
    final thirdOwner = read();
    await _settle();
    expect(adapter.requests, hasLength(2));
    adapter.complete(1, 2);
    for (final result
        in await Future.wait([newOwner, secondOwner, thirdOwner])) {
      expect((result as ApiSuccess).data, {'id': 2});
    }
  });

  test(
      'live ride and payment reads share a snapshot without downloading route history',
      () async {
    final adapter = _Adapter();
    final api = await ApiClient(_Storage()).init();
    api.dio.httpClientAdapter = adapter;
    addTearDown(() => api.dio.close(force: true));
    final ride = ApiRideNegotiationRepository(api).getRideDetail('7');
    final payment = api.execute<Object?>(
        model: 'RideModel',
        operation: 'get',
        data: {'id': '7', 'includeRouteHistory': false});
    await _settle();
    expect(adapter.requests, hasLength(1));
    expect((adapter.requests.single.data as Map)['data'],
        {'id': '7', 'includeRouteHistory': false});
    adapter.complete(0, 7);
    expect((await ride)['id'], 7);
    expect(await payment, isA<ApiSuccess<Object?>>());
  });

  test('100 simultaneous ride reads share one request and parse independently',
      () async {
    final adapter = _Adapter();
    final api = await ApiClient(_Storage()).init();
    api.dio.httpClientAdapter = adapter;
    addTearDown(() => api.dio.close(force: true));
    final reads = List.generate(
        100,
        (_) => api.execute<int>(
            model: 'RideModel',
            operation: 'get',
            data: {'rideId': 42},
            parse: (json) => (json as Map)['id'] as int));
    await _settle();
    expect(adapter.requests, hasLength(1));
    adapter.complete(0);
    final values = await Future.wait(reads);
    expect(
        values.every((value) => value is ApiSuccess<int> && value.data == 42),
        isTrue);
    final fresh = api.execute<Object?>(
        model: 'RideModel', operation: 'get', data: {'rideId': 42});
    await _settle();
    expect(adapter.requests, hasLength(2),
        reason: 'completed snapshots must not hide later live state');
    adapter.complete(1, 43);
    expect((await fresh as ApiSuccess<Object?>).data, {'id': 43});
  });

  test(
      'canonical query data shares reads but differing ride and account do not',
      () async {
    final adapter = _Adapter();
    final storage = _Storage();
    final api = await ApiClient(storage).init();
    api.dio.httpClientAdapter = adapter;
    addTearDown(() => api.dio.close(force: true));
    Future<ApiResult<Object?>> read(Map<String, Object?> data) =>
        api.execute<Object?>(model: 'RideModel', operation: 'get', data: data);
    final first = read({'rideId': 42, 'includeDetails': true});
    final same = read({'includeDetails': true, 'rideId': 42});
    final otherRide = read({'rideId': 99, 'includeDetails': true});
    await _settle();
    expect(adapter.requests, hasLength(2));
    storage.token = 'account-two';
    final otherAccount = read({'rideId': 42, 'includeDetails': true});
    await _settle();
    expect(adapter.requests, hasLength(3));
    for (var i = 0; i < 3; i++) {
      adapter.complete(i);
    }
    await Future.wait([first, same, otherRide, otherAccount]);
  });

  test('actions and unknown contracts never share requests or retry themselves',
      () async {
    final adapter = _Adapter();
    final api = await ApiClient(_Storage()).init();
    api.dio.httpClientAdapter = adapter;
    addTearDown(() => api.dio.close(force: true));
    final actions = [
      for (var i = 0; i < 2; i++)
        api.execute<Object?>(
            model: 'RideModel', operation: 'update', data: {'rideId': 42}),
      for (var i = 0; i < 2; i++)
        api.execute<Object?>(model: 'UnknownModel', operation: 'get'),
    ];
    await _settle();
    expect(adapter.requests, hasLength(4));
    for (var i = 0; i < 4; i++) {
      adapter.complete(i);
    }
    await Future.wait(actions);
    expect(adapter.requests, hasLength(4));
  });

  test('a failed read is evicted so the next recovery read can succeed',
      () async {
    final adapter = _Adapter();
    final api = await ApiClient(_Storage()).init();
    api.dio.httpClientAdapter = adapter;
    addTearDown(() => api.dio.close(force: true));
    Future<ApiResult<Object?>> read() => api.execute<Object?>(
        model: 'RideModel', operation: 'get', data: {'rideId': 42});
    final first = read();
    final duplicate = read();
    await _settle();
    adapter.responses[0].completeError(DioException(
        requestOptions: adapter.requests[0],
        type: DioExceptionType.connectionError));
    expect(await first, isA<ApiFailure<Object?>>());
    expect(await duplicate, isA<ApiFailure<Object?>>());
    final next = read();
    await _settle();
    expect(adapter.requests, hasLength(2));
    adapter.complete(1);
    expect(await next, isA<ApiSuccess<Object?>>());
  });

  test('post-action read cannot reuse a pre-action pending snapshot', () async {
    final adapter = _Adapter();
    final api = await ApiClient(_Storage()).init();
    api.dio.httpClientAdapter = adapter;
    addTearDown(() => api.dio.close(force: true));
    Future<ApiResult<Object?>> read() => api.execute<Object?>(
        model: 'RideModel', operation: 'get', data: {'rideId': 42});
    final old = read();
    await _settle();
    final action = api.execute<Object?>(
        model: 'RideModel', operation: 'update', data: {'rideId': 42});
    await _settle();
    adapter.complete(1);
    await action;
    final fresh = read();
    await _settle();
    expect(adapter.requests, hasLength(3));
    adapter.complete(2, 43);
    expect((await fresh as ApiSuccess<Object?>).data, {'id': 43});
    adapter.complete(0, 42);
    expect((await old as ApiSuccess<Object?>).data, {'id': 42});
  });
}
