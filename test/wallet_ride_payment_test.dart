import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/app/theme/app_theme.dart';
import 'package:yemen_drive/core/config/app_environment.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/controllers/wallet_ride_payment_controller.dart';
import 'package:yemen_drive/features/ride/models/wallet_ride_payment.dart';
import 'package:yemen_drive/features/ride/repositories/wallet_ride_payment_repository.dart';
import 'package:yemen_drive/features/ride/widgets/wallet_ride_payment_panel.dart';

Map<String, Object?> _json(String status, {String rideId = '54'}) => {
      'id': 88,
      'rideId': rideId,
      'paymentMethodId': 4,
      'providerCode': 'Floosak',
      'providerName': 'فلوسك',
      'status': status,
      'nextAction': status == 'AwaitingConfirmation'
          ? 'Confirmation'
          : status == 'AwaitingCode'
              ? 'OneTimePassword'
              : 'None',
      'customerName': 'أحمد محمد',
      'customerIsProviderVerified': true,
      'mobile': '967771234567',
      'amount': 1500,
      'fees': 15,
      'feesKnown': true,
      'currency': 'YER',
      'feeCurrency': 'YER',
      'recipient': 'يمن درايف',
      'message': '',
      'providerReference': status == 'Succeeded' ? 'FL-123456' : null,
      'paidAtUtc': status == 'Succeeded' ? '2026-10-29T12:30:00Z' : null,
    };

WalletRidePayment _payment(String status, {String rideId = '54'}) =>
    WalletRidePayment.fromJson(_json(status, rideId: rideId));

WalletRidePayment _jaib(String status,
        {bool verified = true, String nextAction = 'OneTimePassword'}) =>
    WalletRidePayment.fromJson({
      ..._json(status),
      'paymentMethodId': 8,
      'providerCode': 'Jaib',
      'providerName': 'جيب',
      'mobile': '771234567',
      'customerIsProviderVerified': verified,
      'customerName': verified ? 'محمد أحمد من جيب' : null,
      if (status == 'AwaitingCode') 'nextAction': nextAction,
      if (status == 'Succeeded') 'providerReference': 'JAIB-123456',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader('NotoSansArabic')
          ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  test('only Succeeded is a receipt and unknown fees never become zero', () {
    for (final status in [
      'AwaitingConfirmation',
      'AwaitingCode',
      'Processing',
      'ReviewRequired',
      'ProviderSucceeded',
      'Failed',
      'Cancelled',
    ]) {
      expect(_payment(status).succeeded, isFalse, reason: status);
    }
    expect(_payment('Succeeded').succeeded, isTrue);
    final value = WalletRidePayment.fromJson({
      ..._json('AwaitingConfirmation'),
      'fees': null,
      'feesKnown': true,
    });
    expect(value.feesKnown, isFalse);
    expect(value.fees, isNull);
  });

  test('reopening recovers the same operation without another withdrawal',
      () async {
    final repository = _Repository()..current = _payment('AwaitingCode');
    final controller = WalletRidePaymentController(repository);
    addTearDown(controller.dispose);
    await controller.start('54', 4);
    expect(controller.payment.value!.id, '88');
    expect(controller.payment.value!.awaitingCode, isTrue);
    expect(repository.starts, 0);
    expect(controller.locksOtherMethods, isTrue);
  });

  test(
      'Jaib supports code before verified confirmation and success after approval',
      () async {
    final repository = _Repository()
      ..current = _jaib('AwaitingCode', verified: false);
    final controller = WalletRidePaymentController(repository);
    addTearDown(controller.dispose);
    await controller.refresh('54');
    expect(controller.payment.value!.providerName, 'جيب');
    expect(controller.payment.value!.customerIsProviderVerified, isFalse);
    expect(controller.payment.value!.customerName, isEmpty);
    await controller.confirm(true);
    expect(repository.approvals, isEmpty);
    repository.completion =
        Future.value(ApiSuccess(_jaib('AwaitingConfirmation')));
    await controller.complete('123456');
    expect(repository.completions, 1);
    expect(controller.payment.value!.awaitingConfirmation, isTrue);
    expect(controller.payment.value!.succeeded, isFalse);
    repository.confirmationResult = _jaib('Succeeded');
    await controller.confirm(true);
    expect(repository.approvals, [true]);
    expect(controller.payment.value!.succeeded, isTrue);
    expect(repository.starts, 0);
  });

  test('unverified customer details cannot be approved', () async {
    final repository = _Repository()
      ..current = _jaib('AwaitingConfirmation', verified: false);
    final controller = WalletRidePaymentController(repository);
    addTearDown(controller.dispose);
    await controller.refresh('54');
    await controller.confirm(true);
    expect(repository.approvals, isEmpty);
    expect(controller.payment.value!.succeeded, isFalse);
  });

  test('double taps and pending provider completion cannot submit twice',
      () async {
    final repository = _Repository()..current = _payment('AwaitingCode');
    final controller = WalletRidePaymentController(repository);
    addTearDown(controller.dispose);
    await controller.refresh('54');
    final pending = Completer<ApiResult<WalletRidePayment?>>();
    repository.completion = pending.future;
    final first = controller.complete('123456');
    await controller.complete('123456');
    await controller.start('54', 4);
    expect(repository.completions, 1);
    expect(repository.starts, 0);
    expect(controller.busy.value, isTrue);
    pending.complete(ApiSuccess(_payment('Succeeded')));
    await first;
    expect(controller.payment.value!.succeeded, isTrue);
  });

  test('lost completion response recovers success without resending the code',
      () async {
    final repository = _Repository()..current = _payment('AwaitingCode');
    var receipts = 0;
    final controller =
        WalletRidePaymentController(repository, onSucceeded: (_) => receipts++);
    addTearDown(controller.dispose);
    await controller.refresh('54');
    repository.completion = Future.value(
        const ApiFailure(ApiProblemDetails(title: 'انقطع الاتصال', status: 0)));
    repository.current = _payment('Succeeded');
    await controller.complete('123456');
    await controller.refresh('54');
    expect(repository.completions, 1);
    expect(controller.payment.value!.succeeded, isTrue);
    expect(controller.error.value, isEmpty);
    expect(receipts, 1);
  });

  test('uncertain state prevents choosing another tender or repeating payment',
      () async {
    final repository = _Repository()..current = _payment('AwaitingCode');
    final controller = WalletRidePaymentController(repository);
    addTearDown(controller.dispose);
    await controller.refresh('54');
    repository.completion = Future.value(
        const ApiFailure(ApiProblemDetails(title: 'انقطع الاتصال', status: 0)));
    repository.readFailure = true;
    await controller.complete('123456');
    expect(controller.stateKnown.value, isFalse);
    expect(controller.locksOtherMethods, isTrue);
    await controller.complete('123456');
    await controller.start('54', 4);
    expect(repository.completions, 1);
    expect(repository.starts, 0);
    repository.readFailure = false;
    repository.current = _payment('ReviewRequired');
    await controller.refresh('54');
    expect(controller.locksOtherMethods, isTrue);
    expect(controller.canStart, isFalse);
  });

  test(
      'provider rejection survives refreshes and temporary connectivity errors',
      () async {
    const reason = 'الرصيد المتاح في حساب فلوسك لا يكفي لإتمام عملية الدفع.';
    final repository = _Repository()..current = _payment('AwaitingCode');
    final controller = WalletRidePaymentController(repository);
    addTearDown(controller.dispose);
    await controller.refresh('54');
    repository.completion = Future.value(const ApiFailure(ApiProblemDetails(
        title: reason, status: 400, code: 'wallet_provider_rejected')));
    await controller.complete('123456');
    expect(controller.error.value, reason);
    expect(controller.payment.value!.succeeded, isFalse);
    await controller.refresh('54');
    await controller.refresh('54');
    expect(controller.error.value, reason);
    repository.readFailure = true;
    await controller.refresh('54');
    expect(controller.error.value, contains(reason));
    expect(controller.stateKnown.value, isFalse);
    repository.readFailure = false;
    await controller.refresh('54');
    expect(controller.error.value, reason);
    expect(controller.stateKnown.value, isTrue);
    repository.completion = Future.value(ApiSuccess(_payment('Succeeded')));
    await controller.complete('654321');
    expect(controller.error.value, isEmpty);
    expect(controller.payment.value!.succeeded, isTrue);
  });

  test('persisted provider reason survives recreating the payment controller',
      () async {
    const reason = 'رمز التحقق غير صحيح. تحقق من الرسالة وأدخل الرمز مجدداً.';
    final repository = _Repository()
      ..current = WalletRidePayment.fromJson({
        ..._json('AwaitingCode'),
        'message': reason,
      });
    final first = WalletRidePaymentController(repository);
    await first.refresh('54');
    first.dispose();
    final restored = WalletRidePaymentController(repository);
    addTearDown(restored.dispose);
    await restored.refresh('54');
    expect(restored.payment.value!.message, reason);
    expect(restored.payment.value!.awaitingCode, isTrue);
    expect(repository.starts, 0);
  });

  test(
      'rejecting confirmation releases choices only after confirmed cancellation',
      () async {
    final repository = _Repository()
      ..current = _payment('AwaitingConfirmation');
    final controller = WalletRidePaymentController(repository);
    addTearDown(controller.dispose);
    await controller.refresh('54');
    await controller.confirm(false);
    expect(repository.approvals, [false]);
    expect(controller.payment.value!.status, 'Cancelled');
    expect(controller.canStart, isTrue);
  });

  test('stale response from an earlier ride is ignored', () async {
    final repository = _Repository();
    final pending = Completer<ApiResult<WalletRidePayment?>>();
    repository.readOverride = (id) =>
        id == '54' ? pending.future : Future.value(const ApiSuccess(null));
    final controller = WalletRidePaymentController(repository);
    addTearDown(controller.dispose);
    final old = controller.refresh('54');
    await controller.refresh('55');
    pending.complete(ApiSuccess(_payment('Succeeded')));
    await old;
    expect(controller.payment.value, isNull);
    expect(controller.stateKnown.value, isTrue);
    expect(controller.busy.value, isFalse);
  });

  test('request payloads use catalog ID and never supply a phone or amount',
      () async {
    AppEnvironment.configure(baseUrl: 'https://example.invalid/api');
    final api = await ApiClient(_Storage()).init();
    final adapter = _Adapter();
    api.dio.httpClientAdapter = adapter;
    addTearDown(() => api.dio.close(force: true));
    final repository = ApiWalletRidePaymentRepository(api);
    await repository.getCurrent('54');
    await repository.start('54', 4);
    await repository.confirm('54', '88', true);
    await repository.complete('54', '88', '123456');
    expect(adapter.requests.map((r) => r.uri.path), [
      '/api/rides/54/wallet-payment',
      '/api/rides/54/wallet-payment',
      '/api/rides/54/wallet-payment/88/confirm',
      '/api/rides/54/wallet-payment/88/complete',
    ]);
    expect(
        adapter.requests.map((r) => r.method), ['GET', 'POST', 'POST', 'POST']);
    expect(adapter.requests[1].data, {'paymentMethodId': 4});
    expect(adapter.requests[2].data, {'approved': true});
    expect(adapter.requests[3].data, {'code': '123456'});
    expect(adapter.requests[1].headers['Authorization'], 'Bearer test-token');
  });

  for (final status in ['AwaitingConfirmation', 'AwaitingCode', 'Succeeded']) {
    testWidgets('$status fits a narrow Arabic phone and produces preview',
        (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository()..current = _payment(status);
      final controller = WalletRidePaymentController(repository);
      addTearDown(controller.dispose);
      await controller.refresh('54');
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(_host(controller, boundaryKey: boundaryKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('أحمد محمد'), findsOneWidget);
      expect(find.text('967771234567'), findsOneWidget);
      expect(find.text('1500 ريال يمني'), findsOneWidget);
      expect(find.text('15 ريال يمني'), findsOneWidget);
      expect(find.text('تم دفع الرحلة بنجاح'),
          status == 'Succeeded' ? findsOneWidget : findsNothing);
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/payment-previews')
          ..createSync(recursive: true);
        File('${directory.path}/floosak-$status.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }

  for (final status in [
    'AwaitingConfirmation',
    'AwaitingCode',
    'Processing',
    'Succeeded',
    'Failed',
    'Cancelled',
    'ReviewRequired',
  ]) {
    testWidgets(
        'provider message is visible and status stays authoritative: $status',
        (tester) async {
      const message = 'أفادت فلوسك بأن طلبك يحتاج إلى متابعة حالة العملية.';
      final repository = _Repository()
        ..current = WalletRidePayment.fromJson({
          ..._json(status),
          'message': message,
        });
      final controller = WalletRidePaymentController(repository);
      addTearDown(controller.dispose);
      await controller.refresh('54');
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.text('تم دفع الرحلة بنجاح'),
          status == 'Succeeded' ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('wallet-receipt-done')),
          status == 'Succeeded' ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  }

  testWidgets('same persisted and request rejection is shown once',
      (tester) async {
    const reason = 'الرصيد المتاح في حساب فلوسك لا يكفي لإتمام عملية الدفع.';
    final repository = _Repository()
      ..current = WalletRidePayment.fromJson({
        ..._json('AwaitingCode'),
        'message': reason,
      });
    final controller = WalletRidePaymentController(repository);
    addTearDown(controller.dispose);
    await controller.refresh('54');
    repository.completion = Future.value(const ApiFailure(ApiProblemDetails(
        title: reason, status: 400, code: 'wallet_provider_rejected')));
    await controller.complete('123456');
    await controller.refresh('54');
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    expect(find.text(reason), findsOneWidget);
    expect(find.text('تم دفع الرحلة بنجاح'), findsNothing);
  });

  for (final nextAction in ['OneTimePassword', 'Pin', 'Voucher']) {
    testWidgets(
        'Jaib $nextAction before identity confirmation shows no invented details',
        (tester) async {
      final repository = _Repository()
        ..current =
            _jaib('AwaitingCode', verified: false, nextAction: nextAction);
      final controller = WalletRidePaymentController(repository);
      addTearDown(controller.dispose);
      await controller.refresh('54');
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();
      expect(find.text('جيب'), findsOneWidget);
      expect(find.text('فلوسك'), findsNothing);
      expect(find.text('اسم العميل'), findsNothing);
      expect(find.text('محمد أحمد من جيب'), findsNothing);
      expect(find.text('771234567'), findsOneWidget);
      expect(find.text('تظهر بيانات الحساب بعد التحقق.'), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-verification-code')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-confirm')), findsNothing);
      expect(find.text('تم دفع الرحلة بنجاح'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Jaib moves from code to verified details before showing a receipt',
      (tester) async {
    final repository = _Repository()
      ..current = _jaib('AwaitingCode', verified: false)
      ..completion = Future.value(ApiSuccess(_jaib('AwaitingConfirmation')))
      ..confirmationResult = _jaib('Succeeded');
    final controller = WalletRidePaymentController(repository);
    addTearDown(controller.dispose);
    await controller.refresh('54');
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('wallet-verification-code'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '123456');
    await tester.pump();
    final complete = find.byKey(const ValueKey('wallet-complete'));
    await tester.ensureVisible(complete);
    await tester.tap(complete);
    await tester.pumpAndSettle();
    expect(input, findsNothing);
    expect(find.text('محمد أحمد من جيب'), findsOneWidget);
    expect(find.text('تم دفع الرحلة بنجاح'), findsNothing);
    final confirm = find.byKey(const ValueKey('wallet-confirm'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('تم دفع الرحلة بنجاح'), findsOneWidget);
    expect(find.text('JAIB-123456'), findsOneWidget);
    expect(find.text('جيب'), findsOneWidget);
    expect(repository.approvals, [true]);
    expect(repository.completions, 1);
  });

  testWidgets(
      'OTP button processes in place, clears code, then renders receipt',
      (tester) async {
    final repository = _Repository()..current = _payment('AwaitingCode');
    final controller = WalletRidePaymentController(repository);
    addTearDown(controller.dispose);
    await controller.refresh('54');
    final pending = Completer<ApiResult<WalletRidePayment?>>();
    repository.completion = pending.future;
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('wallet-verification-code'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '123456');
    await tester.pump();
    final button = find.byKey(const ValueKey('wallet-complete'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.completions, 1);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(
        find.descendant(
            of: button, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    expect(find.text('تم دفع الرحلة بنجاح'), findsNothing);
    pending.complete(ApiSuccess(_payment('Succeeded')));
    await tester.pumpAndSettle();
    expect(find.text('تم دفع الرحلة بنجاح'), findsOneWidget);
    expect(find.text('FL-123456'), findsOneWidget);
    expect(input, findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(WalletRidePaymentController controller,
        {GlobalKey? boundaryKey}) =>
    GetMaterialApp(
      locale: const Locale('ar', 'SA'),
      theme: AppTheme.light,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(
            appBar: AppBar(title: const Text('طريقة الدفع')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: WalletRidePaymentPanel(
                controller: controller,
                onRefresh: () {},
                onRetry: () {},
                onChangeMethod: () {},
                onDone: () {},
              ),
            ),
          ),
        ),
      ),
    );

class _Repository implements WalletRidePaymentRepository {
  WalletRidePayment? current;
  int starts = 0;
  int completions = 0;
  final List<bool> approvals = [];
  bool readFailure = false;
  Future<ApiResult<WalletRidePayment?>>? completion;
  WalletRidePayment? confirmationResult;
  Future<ApiResult<WalletRidePayment?>> Function(String id)? readOverride;

  @override
  Future<ApiResult<WalletRidePayment?>> getCurrent(String rideId) async =>
      readOverride != null
          ? readOverride!(rideId)
          : readFailure
              ? const ApiFailure(ApiProblemDetails(title: 'offline', status: 0))
              : ApiSuccess(current);
  @override
  Future<ApiResult<WalletRidePayment?>> start(
      String rideId, int methodId) async {
    starts++;
    return ApiSuccess(
        current = _payment('AwaitingConfirmation', rideId: rideId));
  }

  @override
  Future<ApiResult<WalletRidePayment?>> confirm(
      String rideId, String id, bool approved) async {
    approvals.add(approved);
    if (confirmationResult != null) {
      return ApiSuccess(current = confirmationResult);
    }
    return ApiSuccess(current =
        _payment(approved ? 'AwaitingCode' : 'Cancelled', rideId: rideId));
  }

  @override
  Future<ApiResult<WalletRidePayment?>> complete(
      String rideId, String id, String code) async {
    completions++;
    return completion ??
        ApiSuccess(current = _payment('Succeeded', rideId: rideId));
  }
}

class _Storage extends SecureStorageService {
  @override
  Future<String?> get accessToken async => 'test-token';
}

class _Adapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'data':
              options.method == 'GET' ? null : _json('AwaitingConfirmation'),
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}
