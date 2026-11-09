import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/services/otp_sms_service.dart';
import 'package:yemen_drive/core/services/push_notifications_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/auth/login/models/login_models.dart';
import 'package:yemen_drive/features/auth/login/providers/login_provider.dart';
import 'package:yemen_drive/features/auth/password_reset/models/password_reset_models.dart';
import 'package:yemen_drive/features/auth/password_reset/providers/password_reset_provider.dart';
import 'package:yemen_drive/features/auth/registration/models/registration_models.dart';
import 'package:yemen_drive/features/auth/registration/providers/registration_provider.dart';
import 'package:yemen_drive/features/auth/widgets/otp_code_field.dart';

class _PushGuard extends GetxService implements PushNotificationsService {
  int generation = 0;
  @override
  int get otpPushRequestGeneration => generation;
  @override
  void ensureOtpPushRequestActive(int expected) {
    if (generation != expected) throw const OtpPushRequestCancelled();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"success":true,"data":{}}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final nativeCalls = <String>[];
  String? pending;
  setUp(() {
    nativeCalls.clear();
    pending = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(OtpSmsService.channel, (call) async {
      nativeCalls.add(call.method);
      if (call.method == 'start') return 'AbC12+/xYz9';
      if (call.method == 'takePendingCode') return pending;
      return null;
    });
  });
  tearDown(() async {
    await OtpSmsService.detach();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(OtpSmsService.channel, null);
    Get.reset();
  });

  Future<void> mount(
    WidgetTester tester,
    ValueChanged<String> onChanged, {
    String initial = '',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpCodeField(
            initialCode: initial,
            onChanged: onChanged,
            autofocus: false,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<String> cells(WidgetTester tester) => tester
      .widgetList<TextField>(find.byType(TextField))
      .map((field) => field.controller!.text)
      .toList();

  Future<void> deliver(String code) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      OtpSmsService.channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('code', code)),
      (_) {},
    );
  }

  test('normalizes Arabic and Persian digits while preserving zeroes', () {
    expect(OtpSmsService.normalizeDigits('٠١٢۳۴۵'), '012345');
  });

  testWidgets('fills six cells and updates the verification callback on SMS',
      (tester) async {
    var code = '';
    await mount(tester, (value) => code = value);
    await deliver('012345');
    await tester.pump();
    expect(cells(tester), ['0', '1', '2', '3', '4', '5']);
    expect(code, '012345');
  });

  testWidgets('keeps an SMS received before navigation', (tester) async {
    pending = '654321';
    var code = '';
    await mount(tester, (value) => code = value);
    expect(code, '654321');
    expect(cells(tester).join(), '654321');
  });

  testWidgets('accepts full keyboard autofill and Arabic paste',
      (tester) async {
    var code = '';
    await mount(tester, (value) => code = value);
    await tester.enterText(find.byType(TextField).first, '٠١٢٣٤٥');
    expect(code, '012345');
    expect(cells(tester).join(), '012345');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).autofillHints,
      [AutofillHints.oneTimeCode],
    );
  });

  testWidgets('retains manual entry and ignores malformed SMS values',
      (tester) async {
    var code = '';
    await mount(tester, (value) => code = value);
    for (var index = 0; index < 6; index++) {
      await tester.enterText(find.byType(TextField).at(index), '$index');
    }
    await deliver('12345');
    await deliver('1234567');
    expect(code, '012345');
  });

  testWidgets('stops native reception when the screen closes', (tester) async {
    final changes = <String>[];
    await mount(tester, changes.add);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final before = changes.length;
    await deliver('987654');
    expect(changes.length, before);
    expect(nativeCalls, contains('stop'));
  });

  test('prepares SMS reception and includes the app hash', () async {
    expect(await OtpSmsService.prepareRequest(), {
      'smsAppHash': 'AbC12+/xYz9',
      'notificationRenderer': 'app',
    });
    expect(nativeCalls, ['start']);
  });

  test('session cancellation during native SMS setup aborts OTP preparation',
      () async {
    final guard = _PushGuard();
    Get.put<PushNotificationsService>(guard);
    final started = Completer<void>();
    final released = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(OtpSmsService.channel, (call) async {
      if (call.method != 'start') return null;
      started.complete();
      return released.future;
    });
    var pushCalls = 0;
    final request = OtpSmsService.prepareRequest(
      pushFields: () async {
        pushCalls++;
        return {};
      },
      allowPushFailure: true,
    );
    final assertion =
        expectLater(request, throwsA(isA<OtpPushRequestCancelled>()));
    await started.future;
    guard.generation++;
    released.complete('AbC12+/xYz9');
    await assertion;
    expect(pushCalls, 0);
  });

  test('manual OTP remains available if Play services cannot start', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(OtpSmsService.channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    expect(
      (await OtpSmsService.prepareRequest()).containsKey('smsAppHash'),
      isFalse,
    );
  });

  test('all authentication requests carry the native app hash', () async {
    final client = ApiClient(SecureStorageService())
      ..dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/'));
    final adapter = _Adapter();
    client.dio.httpClientAdapter = adapter;
    final login = LoginProvider(client, otpPushData: () async => {});
    final registration =
        RegistrationProvider(client, otpPushData: () async => {});
    final recovery = PasswordResetProvider(client, otpPushData: () async => {});
    await login.login(
      const LoginRequest(
        phone: '775000000',
        password: 'synthetic-password',
        deviceId: 'test-device',
      ),
    );
    await registration.requestOtp(const SignUpDraft(phone: '775000000'));
    await recovery.request(identity: '775000000', channel: RecoveryChannel.sms);
    expect(adapter.requests, hasLength(3));
    for (final request in adapter.requests) {
      expect((request.data as Map)['smsAppHash'], 'AbC12+/xYz9');
    }
    expect(nativeCalls.where((call) => call == 'start'), hasLength(3));
    client.dio.close();
  });
}
