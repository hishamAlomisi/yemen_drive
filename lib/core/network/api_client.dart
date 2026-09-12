import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../config/app_environment.dart';
import '../storage/secure_storage_service.dart';
import 'api_endpoints.dart';
import 'api_models.dart';

class ApiClient extends GetxService {
  ApiClient(this._storage);

  final SecureStorageService _storage;
  late final Dio dio;
  Completer<void>? _refreshCompleter;

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
              error.requestOptions.extra['retried'] != true) {
            final refreshed = await _refreshToken();
            if (refreshed) {
              final request = error.requestOptions;
              request.extra['retried'] = true;
              final token = await _storage.accessToken;
              request.headers['Authorization'] = 'Bearer $token';
              handler.resolve(await dio.fetch<Object?>(request));
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

  Future<bool> _refreshToken() async {
    if (_refreshCompleter != null) {
      await _refreshCompleter!.future;
      return (await _storage.accessToken)?.isNotEmpty ?? false;
    }
    _refreshCompleter = Completer<void>();
    try {
      final refreshToken = await _storage.refreshToken;
      // The current API issues access tokens only; do not call the
      // unimplemented refresh endpoint with an empty placeholder token.
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final refreshDio = Dio(
        BaseOptions(baseUrl: '${AppEnvironment.baseUrl}/'),
      );

      final response = await refreshDio.post<Map<String, Object?>>(
        ApiEndpoints.refresh,
        data: <String, Object?>{'refreshToken': refreshToken},
      );
      final data = response.data;
      final access = data?['accessToken']?.toString();
      final refresh = data?['refreshToken']?.toString();
      if (access == null || refresh == null) return false;
      await _storage.saveTokens(accessToken: access, refreshToken: refresh);
      return true;
    } catch (_) {
      await _storage.clear();
      return false;
    } finally {
      _refreshCompleter?.complete();
      _refreshCompleter = null;
    }
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
