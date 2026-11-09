import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
/// A bounded readiness check verifies DB access without loading the catalog.
class StartupConnectionService extends GetxService with WidgetsBindingObserver {
  StartupConnectionService({
    Dio? probe,
    String? baseUrl,
    Future<List<ConnectivityResult>> Function()? networkCheck,
    Stream<List<ConnectivityResult>>? networkChanges,
    this.requestTimeout = const Duration(seconds: 8),
    this.healthyInterval = const Duration(seconds: 60),
    this.retryInterval = const Duration(seconds: 3),
  })  : _probe = probe ?? Dio(),
        _baseUrl = baseUrl,
        _networkChanges = networkChanges,
        _networkCheck = networkCheck ?? Connectivity().checkConnectivity;

  final Dio _probe;
  final String? _baseUrl;
  final Future<List<ConnectivityResult>> Function() _networkCheck;
  final Stream<List<ConnectivityResult>>? _networkChanges;
  final Duration requestTimeout;
  final Duration healthyInterval;
  final Duration retryInterval;
  final Rx<StartupStatus> status =
      const StartupStatus(StartupPhase.checkingNetwork).obs;
  bool isVerified = false;
  final RxBool runtimeUnavailable = false.obs;
  final StreamController<void> _recovered = StreamController<void>.broadcast();
  Stream<void> get recovered => _recovered.stream;
  Future<bool>? _inFlight;
  int _inFlightVersion = 0;
  CancelToken? _cancelToken;
  Timer? _monitorTimer;
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  bool _monitoring = false;
  bool _foreground = true;
  int _availabilityVersion = 0;
  bool _legacyCatalogProbe = false;

  /// Runtime recovery shares one read-only probe and never replays actions.
  void startMonitoring() {
    if (_monitoring || isClosed) return;
    _monitoring = true;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    try {
      _networkSubscription =
          (_networkChanges ?? Connectivity().onConnectivityChanged).listen(
        (networks) {
          if (!networks.any((item) => item != ConnectivityResult.none)) {
            _recordFailure(StartupFailure.offline);
          } else if (_foreground) {
            unawaited(checkNow());
          }
        },
        onError: (Object _) {
          // Interface reporting is advisory; the bounded API probe remains.
        },
      );
    } on Object {
      // Monitoring still works when a platform has no interface event plugin.
    }
    _schedule(runtimeUnavailable.value ? retryInterval : healthyInterval);
  }

  void stopMonitoring() {
    if (!_monitoring) return;
    _monitoring = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    unawaited(_networkSubscription?.cancel());
    _networkSubscription = null;
    WidgetsBinding.instance.removeObserver(this);
    _availabilityVersion++;
    _cancelToken?.cancel('Connection monitoring stopped');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _monitorTimer?.cancel();
      _monitorTimer = null;
      _availabilityVersion++;
      _cancelToken?.cancel('Connection monitoring paused');
    } else if (_monitoring) {
      unawaited(checkNow());
    }
  }

  Future<bool> checkNow() async {
    if (!_monitoring || !_foreground || isClosed) {
      return isVerified;
    }
    _monitorTimer?.cancel();
    try {
      return await verify();
    } finally {
      _schedule(runtimeUnavailable.value ? retryInterval : healthyInterval);
    }
  }

  /// Optional immediate retry; runtime monitoring also recovers automatically.
  Future<bool> retryConnection() async {
    _monitorTimer?.cancel();
    try {
      return await verify(userInitiated: true);
    } finally {
      _schedule(runtimeUnavailable.value ? retryInterval : healthyInterval);
    }
  }

  void _schedule(Duration delay) {
    _monitorTimer?.cancel();
    if (!_monitoring || !_foreground || isClosed) {
      return;
    }
    _monitorTimer = Timer(delay, () => unawaited(checkNow()));
  }

  /// A valid API failure envelope belongs to the feature that made the call.
  /// For example routes_not_configured must not disable the whole application.
  bool reportRequestFailure(DioException error) {
    if (isClosed ||
        CancelToken.isCancel(error) ||
        error.requestOptions.extra['availabilityBlocked'] == true) return false;
    final response = error.response;
    final body = response?.data;
    if (body is Map && body['success'] is bool) {
      if ((response?.statusCode ?? 0) >= 500) unawaited(checkNow());
      return false;
    }
    final failure = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        StartupFailure.timeout,
      DioExceptionType.connectionError ||
      DioExceptionType.badCertificate =>
        StartupFailure.unreachable,
      DioExceptionType.badResponse
          when const {502, 503, 504}.contains(response?.statusCode) ||
              ((response?.statusCode ?? 0) >= 200 &&
                  (response?.statusCode ?? 0) < 300) =>
        StartupFailure.server,
      DioExceptionType.unknown when error.error is FormatException =>
        StartupFailure.server,
      _ => null,
    };
    if (failure == null) {
      if ((response?.statusCode ?? 0) >= 500) unawaited(checkNow());
      return false;
    }
    _recordFailure(failure);
    return true;
  }

  void _recordFailure(StartupFailure failure) {
    _availabilityVersion++;
    isVerified = false;
    runtimeUnavailable.value = true;
    status.value = StartupStatus(StartupPhase.failed, failure: failure);
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _schedule(retryInterval);
  }

  /// A valid application response proves reachability without another catalog
  /// query. Invalidate a slower probe so it cannot overwrite this recovery.
  void reportRequestSuccess() {
    if (isClosed || status.value.failure == StartupFailure.initialization)
      return;
    final wasUnavailable = runtimeUnavailable.value;
    if (wasUnavailable || !isVerified) _availabilityVersion++;
    isVerified = true;
    runtimeUnavailable.value = false;
    if (status.value.phase != StartupPhase.ready) {
      status.value = const StartupStatus(StartupPhase.ready);
    }
    if (wasUnavailable) _recovered.add(null);
    _schedule(healthyInterval);
  }

  Future<bool> verify({bool userInitiated = false}) {
    if (isClosed ||
        (runtimeUnavailable.value && !_monitoring && !userInitiated)) {
      return Future.value(false);
    }
    final requestedVersion = _availabilityVersion;
    final pending = _inFlight;
    if (pending != null) {
      if (_inFlightVersion == _availabilityVersion) return pending;
      // Resume or a newer outage invalidated this request. Wait for its cleanup
      // and immediately start one fresh probe instead of the healthy timer.
      return pending.then((_) {
        if (isClosed ||
            (_monitoring && !_foreground) ||
            requestedVersion != _availabilityVersion) return false;
        return verify(userInitiated: userInitiated);
      });
    }
    _inFlightVersion = _availabilityVersion;
    late final Future<bool> operation;
    operation = _verify().whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
    return _inFlight = operation;
  }

  Future<bool> _readReadiness(
      String base, CancelToken cancelToken, int version) async {
    final prefix = base.endsWith('/') ? base : '$base/';
    final options = Options(
      sendTimeout: requestTimeout,
      receiveTimeout: requestTimeout,
      responseType: ResponseType.json,
      followRedirects: false,
      headers: const {'Cache-Control': 'no-cache'},
    );
    if (!_legacyCatalogProbe) {
      try {
        final response = await _probe.get<Object?>('${prefix}health/ready',
            options: options, cancelToken: cancelToken);
        final body = response.data;
        return response.statusCode == 200 &&
            body is Map &&
            body['success'] == true &&
            body['data'] is Map &&
            body['data']['ready'] == true;
      } on DioException catch (error) {
        // Only an older API without this route needs the compatibility read.
        // An unavailable DB or invalid response must never pass via fallback.
        if (error.response?.statusCode != 404 &&
            error.response?.statusCode != 405) rethrow;
        if (cancelToken.isCancelled ||
            isClosed ||
            version != _availabilityVersion) return false;
        _legacyCatalogProbe = true;
      }
    }
    final response =
        await _probe.post<Object?>('$prefix${ApiEndpoints.execute}',
            data: const <String, Object?>{
              'model': 'ServiceKindModel',
              'operation': 'list',
              'data': <String, Object?>{},
            },
            options: options,
            cancelToken: cancelToken);
    final body = response.data;
    return response.statusCode == 200 &&
        body is Map &&
        body['success'] == true &&
        body['data'] is List;
  }

  Future<bool> _verify() async {
    final version = _availabilityVersion;
    bool fail(StartupFailure failure) {
      if (isClosed || version != _availabilityVersion) return false;
      return _fail(failure);
    }

    isVerified = false;
    status.value = const StartupStatus(StartupPhase.checkingNetwork);
    try {
      final networks =
          await _networkCheck().timeout(const Duration(seconds: 3));
      if (!networks.any((network) => network != ConnectivityResult.none)) {
        return fail(StartupFailure.offline);
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
    if (isClosed || version != _availabilityVersion) return false;
    status.value = const StartupStatus(StartupPhase.checkingApi);
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      final base = _baseUrl ?? AppEnvironment.baseUrl;
      final ready = await _readReadiness(base, cancelToken, version).timeout(
        requestTimeout,
        onTimeout: () {
          cancelToken.cancel('Startup connection check timed out');
          throw TimeoutException('API connection timeout');
        },
      );
      if (isClosed || version != _availabilityVersion) return false;
      if (!ready) {
        return fail(StartupFailure.server);
      }
      isVerified = true;
      final wasUnavailable = runtimeUnavailable.value;
      runtimeUnavailable.value = false;
      status.value = const StartupStatus(StartupPhase.ready);
      if (wasUnavailable) _recovered.add(null);
      return true;
    } on TimeoutException {
      return fail(StartupFailure.timeout);
    } on DioException catch (error) {
      if (isClosed || CancelToken.isCancel(error)) return false;
      return fail(
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
      return fail(StartupFailure.unreachable);
    } finally {
      if (identical(_cancelToken, cancelToken)) _cancelToken = null;
    }
  }

  bool _fail(StartupFailure failure) {
    if (!isClosed) {
      _recordFailure(failure);
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
    stopMonitoring();
    _cancelToken?.cancel('Startup connection check disposed');
    _probe.close(force: true);
    unawaited(_recovered.close());
    super.onClose();
  }
}
