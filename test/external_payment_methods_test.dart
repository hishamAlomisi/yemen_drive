import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/app/localization/app_translations.dart';
import 'package:yemen_drive/app/theme/app_theme.dart';
import 'package:yemen_drive/core/config/app_environment.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/widgets/external_payment_methods.dart';
import 'package:yemen_drive/features/ride/widgets/ride_booking_widgets.dart';

Map<String, Object?> _method(String code, String name,
        {bool active = true, bool ride = true, bool topUp = true}) =>
    <String, Object?>{
      'code': code,
      'nameAr': name,
      'descriptionAr': 'وصف الوسيلة من قائمة طرق الدفع',
      'kind': 0,
      'isActive': active,
      'isAvailableForRidePayment': ride,
      'isAvailableForWalletTopUp': topUp,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _CatalogApi api;

  setUpAll(() async {
    await (FontLoader('NotoSansArabic')
          ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  setUp(() {
    Get.testMode = true;
    AppEnvironment.paymentMethods = [];
    api = _CatalogApi()
      ..response = <Object?>[
        _method('EXTERNAL_A', 'محفظة تجريبية'),
        _method('TOP_UP', 'وسيلة شحن تجريبية', ride: false),
        _method('INACTIVE', 'وسيلة موقوفة', active: false),
        _method('HIDDEN', 'وسيلة مخفية', ride: false, topUp: false),
      ];
    Get.put<ApiClient>(api);
  });
  tearDown(() {
    AppEnvironment.paymentMethods = [];
    Get.reset();
  });

  test('catalog uses existing flags, codes, names and images from the API',
      () async {
    api.response = <Object?>[
      <String, Object?>{
        ..._method('API_CODE', 'اسم من الخادم', topUp: false),
        'imageUrl': 'https://example.com/provider.png',
        'kind': 2,
      },
      _method('Cash', 'نقد'),
      _method('YemenDriveWallet', 'محفظة التطبيق'),
      _method('OFF', 'موقوفة', active: false),
    ];
    expect(await AppEnvironment.loadPaymentMethods(api), isTrue);
    final method = AppEnvironment.externalPaymentMethods.single;
    expect(method.id, 'API_CODE');
    expect(method.label, 'اسم من الخادم');
    expect(method.imageUrl, 'https://example.com/provider.png');
    expect(method.kind, 2);
    expect(method.availableForWalletTopUp, isFalse);
    expect(AppEnvironment.paymentMethodById('OFF'), isNull);
    expect(api.calls, ['PaymentMethodModel.list']);
  });

  testWidgets('third option loads the catalog and returns a preference only',
      (tester) async {
    var selected = 'cash';
    var changes = 0;
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, update) => PaymentPreferenceButton(
        method: selected,
        onSelected: (value) => update(() {
          selected = value;
          changes++;
        }),
      ),
    )));
    await tester.tap(find.byTooltip('طريقة الدفع'));
    await tester.pumpAndSettle();
    expect(find.text('نقداً'), findsOneWidget);
    expect(find.text('المحفظة'), findsOneWidget);
    await tester.tap(find.text('محافظ إلكترونية'));
    await tester.pumpAndSettle();
    expect(find.text('محفظة تجريبية'), findsOneWidget);
    expect(find.text('وسيلة شحن تجريبية'), findsOneWidget);
    expect(find.text('وسيلة موقوفة'), findsNothing);
    expect(find.text('وسيلة مخفية'), findsNothing);
    expect(find.text('لشحن محفظة يمن درايف فقط'), findsOneWidget);
    await tester.tap(find.text('محفظة تجريبية'));
    await tester.pumpAndSettle();
    expect(selected, 'EXTERNAL_A');
    expect(changes, 1);
    expect(find.byType(PaymentPreferenceSheet), findsNothing);
    expect(find.byType(ExternalPaymentMethodsPage), findsNothing);
    expect(find.byType(PaymentCatalogIcon), findsOneWidget);
    expect(api.calls, ['PaymentMethodModel.list']);
  });

  testWidgets('top-up-only methods cannot replace a ride payment preference',
      (tester) async {
    await tester.pumpWidget(
        _host(const ExternalPaymentMethodsPage(selected: 'EXTERNAL_A')));
    await tester.pumpAndSettle();
    final row = tester.widget<ListTile>(find.ancestor(
        of: find.text('وسيلة شحن تجريبية'), matching: find.byType(ListTile)));
    expect(row.enabled, isFalse);
    expect(row.onTap, isNull);
    await tester.tap(find.text('وسيلة شحن تجريبية'));
    await tester.pumpAndSettle();
    expect(find.byType(ExternalPaymentMethodsPage), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(api.calls, ['PaymentMethodModel.list']);
  });

  testWidgets('back from external methods keeps the sheet and original choice',
      (tester) async {
    var changes = 0;
    await tester.pumpWidget(_host(PaymentPreferenceButton(
      method: 'wallet',
      onSelected: (_) => changes++,
    )));
    await tester.tap(find.byTooltip('طريقة الدفع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('محافظ إلكترونية'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PaymentPreferenceSheet), findsOneWidget);
    expect(find.text('المحفظة'), findsOneWidget);
    expect(changes, 0);
  });

  testWidgets('failed refresh hides stale methods and supports retry',
      (tester) async {
    await AppEnvironment.loadPaymentMethods(api);
    api.fail = true;
    await tester
        .pumpWidget(_host(const ExternalPaymentMethodsPage(selected: 'cash')));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل طرق الدفع. حاول مرة أخرى.'), findsOneWidget);
    expect(find.text('محفظة تجريبية'), findsNothing);
    api.fail = false;
    api.response = [_method('NEW_CODE', 'وسيلة جديدة')];
    await tester.tap(find.text('تحديث القائمة'));
    await tester.pumpAndSettle();
    expect(find.text('وسيلة جديدة'), findsOneWidget);
    expect(find.text('محفظة تجريبية'), findsNothing);
  });

  testWidgets('empty catalog shows an honest empty state', (tester) async {
    api.response = [];
    await tester
        .pumpWidget(_host(const ExternalPaymentMethodsPage(selected: 'cash')));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد طرق دفع خارجية متاحة حالياً.'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('closing while the catalog loads does not update disposed state',
      (tester) async {
    api.pending = Completer<Object?>();
    await tester
        .pumpWidget(_host(const ExternalPaymentMethodsPage(selected: 'cash')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(_host(const SizedBox()));
    api.pending!.complete([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('external catalog fits Arabic text on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    api.response = [
      _method('LONG', 'محفظة إلكترونية تجريبية ذات اسم طويل'),
      _method('TOP_UP', 'وسيلة شحن تجريبية', ride: false),
    ];
    final previewKey = GlobalKey();
    await tester.pumpWidget(_host(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.35)),
      child: RepaintBoundary(
        key: previewKey,
        child: const ExternalPaymentMethodsPage(selected: 'LONG'),
      ),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('محفظة إلكترونية تجريبية ذات اسم طويل'), findsOneWidget);
    await tester.runAsync(() async {
      final boundary =
          previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/payment-previews')
        ..createSync(recursive: true);
      File('${directory.path}/external-methods.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}

Widget _host(Widget child) => GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('ar', 'SA'),
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );

class _CatalogApi extends ApiClient {
  _CatalogApi() : super(SecureStorageService());

  Object? response;
  bool fail = false;
  Completer<Object?>? pending;
  final List<String> calls = [];

  @override
  Future<ApiResult<T>> execute<T>({
    required String model,
    required String operation,
    Object? data,
    T Function(Object? json)? parse,
  }) async {
    calls.add('$model.$operation');
    if (model != 'PaymentMethodModel' || operation != 'list') {
      throw StateError('The selector must never submit a payment or ride.');
    }
    if (fail) {
      return ApiFailure<T>(
          const ApiProblemDetails(title: 'offline', status: 503));
    }
    return ApiSuccess<T>(
        (pending == null ? response : await pending!.future) as T);
  }
}
