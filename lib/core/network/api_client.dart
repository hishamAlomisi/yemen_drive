import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../config/app_environment.dart';
import '../storage/secure_storage_service.dart';
import 'api_endpoints.dart';
import 'api_models.dart';

enum _RefreshOutcome { refreshed, expired, unavailable }

class ApiClient extends GetxService {
  ApiClient(this._storage);

  final SecureStorageService _storage;
  late final Dio dio;
  Completer<_RefreshOutcome>? _refreshCompleter;
  Future<void> Function()? onSessionExpired;

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
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
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
              handler.resolve(await dio.fetch<Object?>(request));
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
      final response = await dio.post<Object?>(
        ApiEndpoints.execute,
        data: <String, Object?>{
          'model': model,
          'operation': operation,
          'data': data ?? <String, Object?>{},
        },
      );
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
        final refreshDio = Dio(
          BaseOptions(baseUrl: '${AppEnvironment.baseUrl}/'),
        );

        final response = await refreshDio.post<Map<String, Object?>>(
          ApiEndpoints.refresh,
          data: <String, Object?>{'refreshToken': refreshToken},
        );
        final body = response.data;
        final payload =
            body != null && body['success'] == true ? body['data'] : null;
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
        } else if (body != null && body['success'] == false) {
          await _expireSession();
          outcome = _RefreshOutcome.expired;
        }
      }
    } catch (error) {
      if (error is DioException && error.response?.statusCode == 401) {
        await _expireSession();
        outcome = _RefreshOutcome.expired;
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
