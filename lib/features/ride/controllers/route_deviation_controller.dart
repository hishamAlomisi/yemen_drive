import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/startup_connection_service.dart';
import '../models/route_deviation_status.dart';
import 'ride_controller.dart';

abstract interface class RouteDeviationRepository {
  Future<RouteDeviationStatus> check(String rideId);
  Future<RouteDeviationStatus> report(String rideId);
}

class ApiRouteDeviationRepository implements RouteDeviationRepository {
  ApiRouteDeviationRepository(this.api);
  final ApiClient api;

  RouteDeviationStatus _read(Object? body) {
    if (body is! Map || body['success'] != true || body['data'] is! Map) {
      throw const FormatException('تعذر التحقق من مسار الرحلة.');
    }
    return RouteDeviationStatus.fromJson(
        Map<Object?, Object?>.from(body['data'] as Map));
  }

  @override
  Future<RouteDeviationStatus> check(String rideId) async =>
      _read((await api.dio.get<Object?>('rides/$rideId/route-deviation')).data);

  @override
  Future<RouteDeviationStatus> report(String rideId) async => _read(
      (await api.dio.post<Object?>('rides/$rideId/route-deviation/report'))
          .data);
}

/// Warnings use the server's stored route and recent GPS, never a client route
/// recalculated from the driver's off-route location.
class RouteDeviationController extends GetxController
    with WidgetsBindingObserver {
  RouteDeviationController(this.repository, this.ride);
  final RouteDeviationRepository repository;
  final RideController ride;
  final RxBool reporting = false.obs;
  final RouteDeviationPromptPolicy _policy = RouteDeviationPromptPolicy();
  Worker? _rideWorker;
  Timer? _timer;
  StreamSubscription<void>? _recovery;
  bool _foreground = true;
  bool _checking = false;
  String? _scopeRideId;
  int _generation = 0;
  DialogRoute<bool>? _warningRoute;
  NavigatorState? _warningNavigator;
  ValueNotifier<RouteDeviationStatus>? _warningDetails;

  bool get tripInProgress =>
      const {'5', 'InProgress'}.contains(ride.activeRideStatus.value);
  bool get _connected =>
      !Get.isRegistered<StartupConnectionService>() ||
      !Get.find<StartupConnectionService>().runtimeUnavailable.value;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _rideWorker =
        everAll([ride.chatRideId, ride.activeRideStatus], (_) => _sync());
    if (Get.isRegistered<StartupConnectionService>()) {
      _recovery = Get.find<StartupConnectionService>()
          .recovered
          .listen((_) => unawaited(checkNow()));
    }
    _sync();
  }

  void _sync() {
    final id = tripInProgress ? ride.currentRideId : null;
    if (_scopeRideId != id) {
      _scopeRideId = id;
      _generation++;
      _policy.reset();
      unawaited(_closeWarning());
    }
    _timer?.cancel();
    if (id == null || !_foreground) return;
    unawaited(checkNow());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => checkNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _generation++;
    _sync();
  }

  Future<void> checkNow() async {
    final id = ride.currentRideId;
    if (isClosed ||
        _checking ||
        !_foreground ||
        !_connected ||
        !tripInProgress ||
        id == null ||
        reporting.value) return;
    final generation = _generation;
    _checking = true;
    try {
      final status = await repository.check(id);
      if (isClosed ||
          generation != _generation ||
          id != ride.currentRideId ||
          !tripInProgress ||
          !_connected) return;
      final shown = _warningDetails?.value;
      if (shown != null &&
          (!status.available ||
              !status.isDeviating ||
              shown.routeVersion != status.routeVersion)) {
        await _closeWarning();
        if (isClosed ||
            generation != _generation ||
            id != ride.currentRideId ||
            !tripInProgress ||
            !_connected) return;
      } else if (shown != null) {
        _warningDetails!.value = status;
      }
      final prompt = _policy.shouldPrompt(id, status);
      if (!prompt ||
          _warningRoute != null ||
          Get.context == null ||
          (Get.isDialogOpen ?? false) ||
          (Get.isBottomSheetOpen ?? false)) return;
      unawaited(_showWarning(id, status));
    } catch (_) {
      await _closeWarning();
      // The global connection card handles transport failure. Missing/stale
      // route data must never be described as a confirmed safe route.
    } finally {
      _checking = false;
    }
  }

  Future<void> _showWarning(String rideId, RouteDeviationStatus status) async {
    final context = Get.context;
    if (context == null) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final details = ValueNotifier(status);
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.alt_route_rounded),
          title: const Text('تنبيه انحراف عن المسار'),
          content: ValueListenableBuilder<RouteDeviationStatus>(
            valueListenable: details,
            builder: (_, current, __) => Text(current.description),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('نعم، المسار آمن'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('لا، الإبلاغ عن انحراف المسار'),
            ),
          ],
        ),
      ),
    );
    _warningRoute = route;
    _warningNavigator = navigator;
    _warningDetails = details;
    final report = await navigator.push<bool>(route);
    final stillCurrent = identical(_warningRoute, route);
    if (stillCurrent) {
      _warningRoute = null;
      _warningNavigator = null;
      _warningDetails = null;
      if (report != null) _policy.handled();
    }
    details.dispose();
    if (report == true &&
        stillCurrent &&
        !isClosed &&
        rideId == ride.currentRideId &&
        tripInProgress) {
      await reportFromSafety();
    }
  }

  Future<void> reportFromSafety() async {
    final id = ride.currentRideId;
    final generation = _generation;
    if (id == null || !tripInProgress || reporting.value) return;
    reporting.value = true;
    String title;
    String message;
    try {
      final result = await repository.report(id);
      if (isClosed || id != ride.currentRideId || !tripInProgress) return;
      if (result.accepted) {
        _policy.handled();
        title = 'تم قبول بلاغ انحراف المسار';
        message =
            'أُرسل البلاغ إلى الإدارة وأُشعر السائق. يمكنك متابعة الرحلة.';
      } else {
        title = result.available
            ? 'لا يوجد انحراف يستدعي البلاغ'
            : 'تعذر التحقق من المسار';
        message = result.message.isNotEmpty
            ? result.message
            : result.available
                ? 'الرحلة ما زالت تسير في مسارها، ولا يوجد انحراف يستدعي القلق.'
                : 'لا تتوفر بيانات موقع حديثة كافية للتحقق. أعد المحاولة عند توفرها.';
      }
    } catch (_) {
      title = 'تعذر إرسال البلاغ';
      message = 'لم يُؤكد إرسال البلاغ. تحقق من الاتصال ثم أعد المحاولة.';
    } finally {
      reporting.value = false;
    }
    if (isClosed ||
        generation != _generation ||
        id != ride.currentRideId ||
        !tripInProgress ||
        Get.context == null ||
        !_connected) return;
    await Get.dialog<void>(AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: Get.back<void>, child: const Text('متابعة الرحلة'))
      ],
    ));
  }

  Future<void> _closeWarning() {
    final route = _warningRoute;
    final navigator = _warningNavigator;
    _warningRoute = null;
    _warningNavigator = null;
    _warningDetails = null;
    return Future<void>.microtask(() {
      if (route != null && navigator != null) {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      }
    });
  }

  @override
  void onClose() {
    _generation++;
    _timer?.cancel();
    _rideWorker?.dispose();
    _recovery?.cancel();
    unawaited(_closeWarning());
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
