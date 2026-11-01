import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/app/theme/app_theme.dart';
import '../lib/features/ride/widgets/cancellation_refund_dialog.dart';

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
  for (final started in [false, true]) {
    testWidgets('refund confirmation fits narrow RTL screen, started=$started',
        (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.3)),
                child: Directionality(
                    textDirection: TextDirection.rtl, child: child!)),
            home: Scaffold(
                body: CancellationRefundDialog(quote: {
              'paymentCompleted': true,
              'rideStarted': started,
              'paidAmount': 1000,
              'serviceFee': 100,
              'cancellationFee': 50,
              'travelledFare': started ? 56 : 0,
              'totalDeductions': started ? 206 : 150,
              'refundAmount': started ? 794 : 850,
              'currency': 'YER',
              'canCalculateRefund': true,
            })),
          )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('أجرة الجزء المقطوع'),
          started ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('confirm-cancellation-refund')),
          findsOneWidget);
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('build/cancellation-preview')
          ..createSync(recursive: true);
        File('${dir.path}/refund-${started ? 'started' : 'prestart'}.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
