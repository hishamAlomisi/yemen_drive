import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;

import '../config/app_environment.dart';
import '../services/startup_connection_service.dart';
import '../storage/secure_storage_service.dart';
import 'api_endpoints.dart';
import 'api_models.dart';

enum _RefreshOutcome { refreshed, expired, unavailable }

class ApiClient extends GetxService {
  ApiClient(
    this._storage, {
    Dio? refreshClient,
    this.refreshTimeout = const Duration(seconds: 8),
  }) : _refreshClient = refreshClient;

  final SecureStorageService _storage;
  final Dio? _refreshClient;
  final Duration refreshTimeout;
  late final Dio dio;
  Completer<_RefreshOutcome>? _refreshCompleter;
  final Map<String, Future<Response<Object?>>> _pendingReads = {};

  /// A read starting after a server invalidation must not join a snapshot
  /// requested before it. Existing callers still finish and verify their epoch.
  void invalidatePendingReads() => _pendingReads.clear();
  Future<void> Function()? onSessionExpired;

  StartupConnectionService? get _availability =>
      Get.isRegistered<StartupConnectionService>()
          ? Get.find<StartupConnectionService>()
          : null;

  Future<ApiClient> init() async {
    // Relative endpoint paths (for example `auth/login`) require a trailing
    // slash on the base URL. Without it, URI resolution treats `/api` as the
    // last file segment and produces `/auth/login` instead of
    // `/api/auth/login`.
    final dioBaseUrl = AppEnvironment.baseUrl.toString().endsWith("/")
        ? AppEnvironment.baseUrl
        : '${AppEnvironment.baseUrl}/';
    dio = Dio(
      BaseOptions(
        baseUrl: dioBaseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 25),
        sendTimeout: const Duration(seconds: 25),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        headers: const <String, Object>{
          'Accept': Headers.jsonContentType,
          'Accept-Language': 'ar-SA',
        },
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.accessToken;
          // Storage can yield while another request discovers an outage.
          // Check immediately before dispatch, not before that await.
          if (_availability?.runtimeUnavailable.value == true) {
            options.extra['availabilityBlocked'] = true;
            handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              message: 'تعذّر الاتصال بالخادم. تجري إعادة الاتصال تلقائياً.',
            ));
            return;
          }
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          final body = response.data;
          if (response.requestOptions.responseType == ResponseType.json &&
              (body is! Map || body['success'] is! bool)) {
            final error = DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              message: 'استجابة غير صالحة من الخادم',
            );
            _availability?.reportRequestFailure(error);
            handler.reject(error);
            return;
          }
          _availability?.reportRequestSuccess();
          handler.next(response);
        },
        onError: (error, handler) async {
          if (error.requestOptions.extra['availabilityBlocked'] != true) {
            _availability?.reportRequestFailure(error);
          }
          // Public/guest requests can legitimately receive 401. There is no
          // session to refresh or expire, and navigating home here interrupts
          // whatever page the passenger is using.
          if (error.response?.statusCode == 401 &&
              error.requestOptions.headers['Authorization'] == null) {
            handler.next(error);
            return;
          }
          if (error.response?.statusCode == 401 &&
              error.requestOptions.extra['retried'] == true) {
            await _expireSession();
            handler.next(error);
            return;
          }
          if (error.response?.statusCode == 401 &&
              error.requestOptions.extra['retried'] != true) {
            final refreshOutcome = await _refreshToken();
            if (refreshOutcome == _RefreshOutcome.refreshed) {
              final request = error.requestOptions;
              request.extra['retried'] = true;
              final token = await _storage.accessToken;
              request.headers['Authorization'] = 'Bearer $token';
              try {
                handler.resolve(await dio.fetch<Object?>(request));
              } on DioException catch (retryError) {
                handler.reject(retryError);
              } on Object catch (retryError, stackTrace) {
                handler.reject(DioException(
                  requestOptions: request,
                  error: retryError,
                  stackTrace: stackTrace,
                ));
              }
              return;
            }
            if (refreshOutcome == _RefreshOutcome.unavailable) {
              handler
                  .reject(DioException(requestOptions: error.requestOptions));
              return;
            }
          }
          handler.next(error);
        },
      ),
    );
    return this;
  }

  Future<ApiResult<T>> execute<T>({
    required String model,
    required String operation,
    Object? data,
    T Function(Object? json)? parse,
  }) async {
    try {
      final response = await _executeRequest(model, operation, data);
      final body = response.data;
      if (body is! Map) {
        return ApiFailure<T>(
          const ApiProblemDetails(
            title: 'استجابة غير صالحة من الخادم',
            status: 0,
            code: 'invalid_response',
          ),
        );
      }
      final json = Map<String, Object?>.from(body);
      if (json['success'] != true) {
        return ApiFailure<T>(ApiProblemDetails.fromJson(json));
      }
      final value = parse == null ? json['data'] as T : parse(json['data']);
      return ApiSuccess<T>(value);
    } on Object catch (error) {
      return ApiFailure<T>(problemFrom(error));
    }
  }

  // Only known query contracts may share a concurrent request. Completed
  // snapshots are never cached, and user actions are always dispatched once
  // per invocation. A reconnect burst cannot stack identical polling reads.
  static const _queryOperations = <String, Set<String>>{
    'RideModel': {'get', 'list'},
    'RideWaitingModel': {'get'},
    'RideRouteChangeModel': {'get'},
    'RideArrivalModel': {'get'},
    'RideCancellationRequestModel': {'get'},
    'RideSearchViewModel': {'get'},
    'RideSearchRecipientModel': {'get'},
    'RideMessageModel': {'list'},
    'NotificationModel': {'list'},
    'NearbyDriverModel': {'list'},
    'WalletModel': {'get'},
    'CashPaymentRequestModel': {'get'},
    'ServiceKindModel': {'list'},
    'ServiceCatalogModel': {'list'},
    'PaymentMethodModel': {'list'},
    'SavedPlaceModel': {'list'},
    'MapLocationSearchModel': {'search'},
  };

  Future<Response<Object?>> _executeRequest(
      String model, String operation, Object? data) async {
    final payload = <String, Object?>{
      'model': model,
      'operation': operation,
      'data': data ?? <String, Object?>{},
    };
    Future<Response<Object?>> dispatch() =>
        dio.post<Object?>(ApiEndpoints.execute, data: payload);
    if (_queryOperations[model]?.contains(operation) != true) {
      // A read requested after an action must not join a pre-action snapshot.
      _pendingReads.clear();
      try {
        return await dispatch();
      } finally {
        _pendingReads.clear();
      }
    }
    // Auth scope is part of the identity: an old account's in-flight read
    // must never satisfy a new account's request after sign-out/sign-in.
    final token = await _storage.accessToken;
    final String key;
    try {
      key = jsonEncode([token, _canonicalQuery(payload)]);
    } on Object {
      return dispatch();
    }
    final pending = _pendingReads[key];
    if (pending != null) return pending;
    if (_pendingReads.length >= 64) return dispatch();
    late final Future<Response<Object?>> request;
    request = dispatch().whenComplete(() {
      if (identical(_pendingReads[key], request)) _pendingReads.remove(key);
    });
    _pendingReads[key] = request;
    return request;
  }

  static Object? _canonicalQuery(Object? value) {
    if (value is Map<String, Object?>) {
      final keys = value.keys.toList()..sort();
      return {for (final key in keys) key: _canonicalQuery(value[key])};
    }
    if (value is List) return value.map(_canonicalQuery).toList();
    return value;
  }

  Future<_RefreshOutcome> _refreshToken() async {
    final inFlight = _refreshCompleter;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<_RefreshOutcome>();
    _refreshCompleter = completer;
    var outcome = _RefreshOutcome.unavailable;
    try {
      final refreshToken = await _storage.refreshToken;
      if (refreshToken == null || refreshToken.isEmpty) {
        await _expireSession();
        outcome = _RefreshOutcome.expired;
      } else {
        if (_availability?.runtimeUnavailable.value == true) {
          return _RefreshOutcome.unavailable;
        }
        final refreshDio = _refreshClient ?? Dio();
        refreshDio.options = BaseOptions(
          baseUrl:
              '${AppEnvironment.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/',
          connectTimeout: refreshTimeout,
          sendTimeout: refreshTimeout,
          receiveTimeout: refreshTimeout,
          responseType: ResponseType.json,
        );
        final cancel = CancelToken();
        late final Response<Object?> response;
        try {
          response = await refreshDio
              .post<Object?>(
            ApiEndpoints.refresh,
            data: <String, Object?>{'refreshToken': refreshToken},
            cancelToken: cancel,
          )
              .timeout(refreshTimeout, onTimeout: () {
            cancel.cancel('Token refresh timed out');
            throw DioException(
              requestOptions: RequestOptions(path: ApiEndpoints.refresh),
              type: DioExceptionType.receiveTimeout,
            );
          });
        } finally {
          if (_refreshClient == null) refreshDio.close(force: true);
        }
        final body = response.data;
        final payload =
            body is Map && body['success'] == true ? body['data'] : null;
        final access =
            payload is Map ? payload['accessToken']?.toString() : null;
        final refresh =
            payload is Map ? payload['refreshToken']?.toString() : null;
        if (access != null &&
            access.isNotEmpty &&
            refresh != null &&
            refresh.isNotEmpty) {
          await _storage.replaceTokens(
            accessToken: access,
            refreshToken: refresh,
          );
          outcome = _RefreshOutcome.refreshed;
        } else if (body is Map &&
            body['success'] == false &&
            (body['code'] == 'invalid_refresh_token' ||
                body['code'] == 'session_expired')) {
          await _expireSession();
          outcome = _RefreshOutcome.expired;
        } else if (body is! Map || body['success'] is! bool) {
          _availability?.reportRequestFailure(DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
          ));
        }
      }
    } catch (error) {
      if (error is DioException) {
        _availability?.reportRequestFailure(error);
        if (error.response?.statusCode == 401) {
          await _expireSession();
          outcome = _RefreshOutcome.expired;
        }
      }
    } finally {
      completer.complete(outcome);
      _refreshCompleter = null;
    }
    return outcome;
  }

  Future<void> _expireSession() async {
    await _storage.clear();
    await onSessionExpired?.call();
  }

  ApiProblemDetails problemFrom(Object error) {
    if (error is DioException &&
        (error.response?.statusCode ?? 0) >= 200 &&
        (error.response?.statusCode ?? 0) < 300) {
      final body = error.response?.data;
      if (body is! Map || body['success'] is! bool) {
        return const ApiProblemDetails(
          title: 'استجابة غير صالحة من الخادم',
          status: 0,
          code: 'invalid_response',
        );
      }
    }
    if (error is DioException && error.response?.data is Map) {
      return ApiProblemDetails.fromJson(
        Map<String, Object?>.from(error.response!.data as Map),
        fallbackStatus: error.response?.statusCode,
      );
    }
    return const ApiProblemDetails(
      title: 'تعذّر الاتصال بالخادم',
      status: 0,
      code: 'network_error',
    );
  }
}
