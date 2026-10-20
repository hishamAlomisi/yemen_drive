import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../config/app_environment.dart';
import '../network/api_endpoints.dart';

enum StartupPhase { checkingNetwork, checkingApi, initializing, ready, failed }

enum StartupFailure { offline, unreachable, timeout, server, initialization }

class StartupStatus {
  const StartupStatus(this.phase, {this.failure});

  final StartupPhase phase;
  final StartupFailure? failure;

  bool get hasFailed => phase == StartupPhase.failed;

  String get message => switch (phase) {
        StartupPhase.checkingNetwork => 'جاري فحص اتصال الشبكة ...',
        StartupPhase.checkingApi => 'جاري الاتصال بالخادم ...',
        StartupPhase.initializing => 'جاري تهيئة التطبيق ...',
        StartupPhase.ready => 'تم الاتصال بنجاح',
        StartupPhase.failed => switch (failure) {
            StartupFailure.offline => 'لا يوجد اتصال بالشبكة',
            StartupFailure.timeout => 'انتهت مهلة الاتصال بالخادم',
            StartupFailure.server => 'خدمة الخادم غير متاحة الآن',
            StartupFailure.initialization => 'تعذّر تهيئة التطبيق',
            _ => 'تعذّر الاتصال بالخادم',
          },
      };

  String get advice => switch (failure) {
        StartupFailure.offline =>
          'فعّل الواي فاي أو بيانات الهاتف، ثم أعد المحاولة.',
        StartupFailure.timeout =>
          'الاتصال بطيء أو الخادم لا يستجيب. أعد المحاولة.',
        StartupFailure.server =>
          'الخادم لم يُكمل الطلب بنجاح. حاول مرة أخرى بعد قليل.',
        StartupFailure.initialization =>
          'لم يكتمل تشغيل التطبيق. اضغط إعادة المحاولة.',
        _ => 'تحقق من اتصال الإنترنت ثم أعد المحاولة.',
      };
}

/// Checks the configured API itself rather than an unrelated Internet host.
/// The public catalog read also verifies that the backend can access its DB.
class StartupConnectionService extends GetxService {
  StartupConnectionService({
    Dio? probe,
    Future<List<ConnectivityResult>> Function()? networkCheck,
    this.requestTimeout = const Duration(seconds: 8),
  })  : _probe = probe ?? Dio(),
        _networkCheck = networkCheck ?? Connectivity().checkConnectivity;

  final Dio _probe;
  final Future<List<ConnectivityResult>> Function() _networkCheck;
  final Duration requestTimeout;
  final Rx<StartupStatus> status =
      const StartupStatus(StartupPhase.checkingNetwork).obs;
  bool isVerified = false;
  Future<bool>? _inFlight;
  CancelToken? _cancelToken;

  Future<bool> verify() {
    final pending = _inFlight;
    if (pending != null) return pending;
    final operation = _verify();
    _inFlight = operation;
    return operation.whenComplete(() => _inFlight = null);
  }

  Future<bool> _verify() async {
    isVerified = false;
    status.value = const StartupStatus(StartupPhase.checkingNetwork);
    try {
      final networks =
          await _networkCheck().timeout(const Duration(seconds: 3));
      if (!networks.any((network) => network != ConnectivityResult.none)) {
        return _fail(StartupFailure.offline);
      }
    } on PlatformException {
      // If the platform cannot report the interface, the real API request
      // remains the authoritative connectivity check.
    } on MissingPluginException {
      // Some desktop platforms do not provide a network interface plugin.
    } on TimeoutException {
      // A slow interface check must not stop the bounded API probe.
    } on Object {
      // Continue with the real request when interface detection is unavailable.
    }
    if (isClosed) return false;
    status.value = const StartupStatus(StartupPhase.checkingApi);
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      final base = AppEnvironment.baseUrl;
      final url =
          '${base.endsWith('/') ? base : '$base/'}${ApiEndpoints.execute}';
      final response = await _probe
          .post<Object?>(
        url,
        // Read-only, public request; no stored tokens or session interceptors.
        data: const <String, Object?>{
          'model': 'ServiceKindModel',
          'operation': 'list',
          'data': <String, Object?>{},
        },
        options: Options(
          sendTimeout: requestTimeout,
          receiveTimeout: requestTimeout,
          responseType: ResponseType.json,
          followRedirects: false,
          headers: const {'Cache-Control': 'no-cache'},
        ),
        cancelToken: cancelToken,
      )
          .timeout(
        requestTimeout,
        onTimeout: () {
          cancelToken.cancel('Startup connection check timed out');
          throw TimeoutException('API connection timeout');
        },
      );
      if (isClosed) return false;
      final body = response.data;
      if (response.statusCode != 200 ||
          body is! Map ||
          body['success'] != true ||
          body['data'] is! List) {
        return _fail(StartupFailure.server);
      }
      isVerified = true;
      status.value = const StartupStatus(StartupPhase.ready);
      return true;
    } on TimeoutException {
      return _fail(StartupFailure.timeout);
    } on DioException catch (error) {
      if (isClosed || CancelToken.isCancel(error)) return false;
      return _fail(
        switch (error.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout =>
            StartupFailure.timeout,
          DioExceptionType.badResponse => StartupFailure.server,
          _ => StartupFailure.unreachable,
        },
      );
    } on Object {
      return _fail(StartupFailure.unreachable);
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
  }

  bool _fail(StartupFailure failure) {
    if (!isClosed) {
      status.value = StartupStatus(StartupPhase.failed, failure: failure);
    }
    return false;
  }

  void initializing() {
    status.value = const StartupStatus(StartupPhase.initializing);
  }

  void initializationFailed() {
    isVerified = false;
    _fail(StartupFailure.initialization);
  }

  @override
  void onClose() {
    _cancelToken?.cancel('Startup connection check disposed');
    _probe.close(force: true);
    super.onClose();
  }
}
