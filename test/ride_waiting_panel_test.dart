import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/shared/widgets/ride_waiting_panel.dart';
import 'package:yemen_drive/features/ride/booking/widgets/booking_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('NotoSansArabic')..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late _WaitingApi api;
  setUp(() {
    Get.testMode = true;
    api = _WaitingApi();
    Get.put<ApiClient>(api);
  });
  tearDown(() async {
    Get.reset();
  });

  Widget host(Widget child) => GetMaterialApp(
      theme: ThemeData(fontFamily: 'NotoSansArabic'),
      locale: const Locale('ar'),
      home: Scaffold(
          body: Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(child: child))));

  testWidgets('passenger reviews waiting terms before consenting',
      (tester) async {
    await tester.pumpWidget(host(const RideWaitingPanel(rideId: 42)));
    await tester.pumpAndSettle();
    expect(api.actions, isEmpty);
    expect(find.text('طلب انتظار بانتظار الموافقة'), findsOneWidget);
    await tester.tap(find.text('مراجعة وموافقة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('المهلة المجانية لكل توقف: 2 دقيقة'),
        findsOneWidget);
    expect(api.actions, isEmpty);
    await tester.tap(find.text('أوافق على بدء الانتظار'));
    await tester.pumpAndSettle();
    expect(api.actions, ['accept']);
    expect(find.text('الإجمالي الحالي: 1250 ر.ي'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'driver can stop waiting and the Arabic panel fits a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    api.active = true;
    final key = GlobalKey();
    await tester.pumpWidget(host(RepaintBoundary(
        key: key, child: const RideWaitingPanel(rideId: 42, isDriver: true))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('الإجمالي الحالي: 1250 ر.ي'), findsOneWidget);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/waiting-previews/driver-waiting.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
    await tester.tap(find.text('استئناف الرحلة وإيقاف الانتظار'));
    await tester.pumpAndSettle();
    expect(api.actions, ['update']);
    expect(find.text('انتهى التوقف.'), findsOneWidget);
    expect(find.text('الإجمالي الحالي: 1250 ر.ي'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual Arabic fare input cannot leave the configured range',
      (tester) async {
    await tester.pumpWidget(host(const BookingFareSheet(
        currentPrice: 1000,
        suggestedPrice: 1000,
        minPrice: 800,
        maxPrice: 1300,
        currency: 'ر.ي')));
    await tester.enterText(find.byType(TextField), '١٣٠١');
    await tester.tap(find.text('تم'));
    await tester.pump();
    expect(find.text('الأجرة المسموحة من 800 إلى 1300 ر.ي'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '٧٩٩');
    await tester.tap(find.text('تم'));
    await tester.pump();
    expect(find.text('الأجرة المسموحة من 800 إلى 1300 ر.ي'), findsOneWidget);
  });
}

class _WaitingApi extends ApiClient {
  _WaitingApi() : super(SecureStorageService());
  bool active = false;
  bool ended = false;
  final List<String> actions = [];
  @override
  Future<ApiResult<T>> execute<T>(
      {required String model,
      required String operation,
      Object? data,
      T Function(Object?)? parse}) async {
    if (operation != 'get') actions.add(operation);
    if (operation == 'accept') active = true;
    if (operation == 'update') ended = true;
    final now = DateTime.now().toUtc();
    return ApiSuccess<T>(<String, Object?>{
      'rideId': 42,
      'totalAmount': active ? 1250 : 1100,
      'serverNowUtc': now.toIso8601String(),
      'waitingFreeMinutes': 2,
      'waitingPricePerMinute': 50,
      'waitingMaxFee': 500,
      'settledWaitingFee': ended ? 150 : 0,
      'waitingFee': active ? 150 : 0,
      'baseFare': 1000,
      'serviceFee': 100,
      'connectionDeadlineUtc':
          now.add(const Duration(minutes: 2)).toIso8601String(),
      'canRequest': ended,
      'canDecide': !active,
      'requestedByMe': false,
      'session': {
        'id': 7,
        'isOpen': !ended,
        'startedAtUtc': active
            ? now.subtract(const Duration(minutes: 5)).toIso8601String()
            : null,
        'freeMinutes': 2,
        'pricePerMinute': 50,
        'maxFee': 500,
        'endReason': ended ? 'driver_resumed' : null
      },
    } as T);
  }
}
