import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/account/wallet/repositories/wallet_top_up_repository.dart';
import 'package:yemen_drive/features/ride/controllers/wallet_ride_payment_controller.dart';
import 'package:yemen_drive/features/ride/widgets/wallet_ride_payment_panel.dart';

class MemoryStore implements GetStorage {
  final values = <String, dynamic>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TopUpAdapter implements HttpClientAdapter {
  Map<String, Object?>? current;
  Map<String, Object?>? invoice;
  final posts = <Map<String, Object?>>[];
  bool failStart = false;
  bool lostCompleteResponse = false;
  Map<String, Object?> operation(String status, String requestId) => {
        'id': 66,
        'rideId': null,
        'paymentMethodId': 8,
        'providerCode': 'Jaib',
        'providerName': 'جيب',
        'status': status,
        'nextAction': status == 'AwaitingConfirmation'
            ? 'Confirmation'
            : status == 'AwaitingCode'
                ? 'OneTimePassword'
                : 'None',
        'customerName': 'اسم العميل',
        'customerIsProviderVerified': true,
        'mobile': '771234567',
        'amount': 786.50,
        'fees': 10,
        'feesKnown': true,
        'currency': 'YER',
        'feeCurrency': 'YER',
        'requestId': requestId,
        'message': status == 'Failed' ? 'الرصيد غير كافٍ' : '',
        'canCancel':
            status == 'AwaitingCode' || status == 'AwaitingConfirmation',
        if (status == 'Succeeded')
          'receipt': {
            'number': 'TOPUP-66',
            'amount': 786.50,
            'providerFees': 10,
            'balanceAfter': 836.50
          },
      };
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    if (options.method == 'POST') {
      final data = Map<String, Object?>.from(options.data as Map);
      posts.add(data);
      if (options.path.endsWith('/complete')) {
        current = operation('Succeeded', '${current!['requestId']}');
        if (lostCompleteResponse)
          throw DioException(
              requestOptions: options, type: DioExceptionType.connectionError);
      } else if (options.path.endsWith('/confirm')) {
        current = operation(
            data['approved'] == true ? 'AwaitingCode' : 'Cancelled',
            '${current!['requestId']}');
      } else {
        current = operation(failStart ? 'Failed' : 'AwaitingConfirmation',
            '${data['requestId']}');
      }
    }
    final result = options.method == 'GET' && options.path.endsWith('/99')
        ? invoice
        : options.method == 'GET' &&
                options.path.endsWith('/current') &&
                current?['status'] == 'Succeeded'
            ? null
            : current;
    return ResponseBody.fromString(
        jsonEncode({'success': true, 'data': result}), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TopUpAdapter adapter;
  late MemoryStore storage;
  late WalletTopUpRepository repository;
  late WalletRidePaymentController flow;
  var successes = 0;
  setUp(() {
    Get.testMode = true;
    adapter = TopUpAdapter();
    storage = MemoryStore();
    successes = 0;
    final api = ApiClient(SecureStorageService());
    api.dio = Dio(BaseOptions(baseUrl: 'https://test.invalid/api/'))
      ..httpClientAdapter = adapter;
    repository = WalletTopUpRepository(api, 1, store: storage)..amount = 786.50;
    flow = WalletRidePaymentController(repository,
        onSucceeded: (_) => successes++);
  });
  tearDown(() {
    flow.dispose();
    Get.reset();
  });

  test(
      'user amount and fresh reference go through confirmation and OTP; credit is final only',
      () async {
    await flow.start('topup', 8);
    expect(adapter.posts.single['amount'], 786.50);
    final reference = adapter.posts.single['requestId'];
    expect(flow.payment.value!.awaitingConfirmation, isTrue);
    expect(successes, 0);
    await flow.confirm(true);
    expect(flow.payment.value!.awaitingCode, isTrue);
    await flow.complete('123456');
    expect(flow.payment.value!.succeeded, isTrue);
    expect(flow.payment.value!.receipt!['number'], 'TOPUP-66');
    await flow.refresh('topup');
    expect(successes, 1);
    expect(flow.payment.value!.requestId, reference);
    expect(jsonEncode(storage.values).contains('123456'), isFalse);
  });

  test('provider refusal allows another attempt with a new reference',
      () async {
    adapter.failStart = true;
    await flow.start('topup', 8);
    final first = adapter.posts.single['requestId'];
    expect(flow.canStart, isTrue);
    adapter.failStart = false;
    await flow.start('topup', 8);
    expect(adapter.posts.last['requestId'], isNot(first));
  });

  test('viewing an old invoice preserves the pending topup reference',
      () async {
    await flow.start('topup', 8);
    final pending = Map<String, dynamic>.from(
        storage.read<Map<String, dynamic>>(repository.storageKey)!);
    adapter.invoice = adapter.operation('Succeeded', 'old-invoice-reference')
      ..['id'] = 99;
    await repository.getById('99');
    await flow.refresh('topup');
    expect(flow.payment.value!.id, '99');
    expect(storage.read<Map<String, dynamic>>(repository.storageKey), pending);
    await repository.clearFinished();
    await flow.refresh('topup');
    expect(flow.payment.value!.awaitingConfirmation, isTrue);
    expect(flow.payment.value!.requestId, pending['requestId']);
    expect(adapter.posts.length, 1);
  });

  test('lost final response recovers success without another provider mutation',
      () async {
    await flow.start('topup', 8);
    await flow.confirm(true);
    adapter.lostCompleteResponse = true;
    await flow.complete('123456');
    expect(flow.payment.value!.succeeded, isTrue);
    expect(successes, 1);
    expect(adapter.posts.length, 3);
  });

  testWidgets(
      'topup receipt shows credited amount, fees and balance without ride number',
      (tester) async {
    await tester.runAsync(() async {
      await flow.start('topup', 8);
      await flow.confirm(true);
      await flow.complete('123456');
    });
    await tester.pumpWidget(GetMaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WalletRidePaymentPanel(
      controller: flow,
      onRefresh: () {},
      onRetry: () {},
      onChangeMethod: () {},
      onDone: () {},
    )))));
    await tester.pumpAndSettle();
    expect(find.text('تم شحن محفظتك'), findsOneWidget);
    expect(find.text('TOPUP-66'), findsOneWidget);
    expect(find.text('الرصيد بعد الشحن'), findsOneWidget);
    expect(find.text('مبلغ الشحن'), findsOneWidget);
    expect(find.text('رقم الرحلة'), findsNothing);
  });
}
