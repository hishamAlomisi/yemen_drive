import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_drive/core/services/startup_connection_service.dart';
import 'package:yemen_drive/shared/widgets/api_availability_gate.dart';

class _HealthyAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString('{"success":true,"data":{"ready":true}}', 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets(
      'outage keeps actions, focus and navigation usable and recovers automatically',
      (tester) async {
    final probe = Dio()..httpClientAdapter = _HealthyAdapter();
    final connection = StartupConnectionService(
      probe: probe,
      baseUrl: 'https://outage.invalid/api',
      networkCheck: () async => [ConnectivityResult.wifi],
      networkChanges: const Stream.empty(),
      retryInterval: const Duration(milliseconds: 10),
    );
    final observer = ApiAvailabilityNavigatorObserver(connection);
    final navigator = GlobalKey<NavigatorState>();
    final draft = TextEditingController();
    final focus = FocusNode();
    var actions = 0;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [observer],
      builder: (context, child) =>
          ApiAvailabilityGate(connection: connection, child: child!),
      home: const Scaffold(body: Text('home')),
    ));
    final rideRoute = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/active-ride/42'),
      builder: (context) => Scaffold(
          body: Column(children: [
        const SizedBox(height: 100),
        const Text('active ride 42'),
        TextField(
            key: const Key('ride-draft'), controller: draft, focusNode: focus),
        ElevatedButton(
            key: const Key('ride-action'),
            onPressed: () => actions++,
            child: const Text('save')),
      ])),
    );
    unawaited(navigator.currentState!.push(rideRoute));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('ride-draft')), 'مسودة عنوان الرحلة');
    expect(focus.hasFocus, true);
    connection.reportRequestFailure(DioException(
      requestOptions: RequestOptions(path: 'execute'),
      type: DioExceptionType.connectionError,
    ));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('api-unavailable-banner')), findsOneWidget);
    expect(focus.hasFocus, true);
    await tester.tap(find.byKey(const Key('ride-action')), warnIfMissed: false);
    expect(actions, 1);
    expect(rideRoute.popDisposition, RoutePopDisposition.pop);
    expect(draft.text, 'مسودة عنوان الرحلة');
    await tester.runAsync(() async {
      final recovered = connection.recovered.first;
      connection.startMonitoring();
      await recovered.timeout(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('api-unavailable-banner')), findsNothing);
    expect(rideRoute.isCurrent, true);
    expect(find.text('active ride 42'), findsOneWidget);
    expect(draft.text, 'مسودة عنوان الرحلة');
    await tester.tap(find.byKey(const Key('ride-action')));
    expect(actions, 2);
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    observer.dispose();
    connection.onClose();
    focus.dispose();
    draft.dispose();
  });
}
