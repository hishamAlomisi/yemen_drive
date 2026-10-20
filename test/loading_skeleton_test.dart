import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:yemen_drive/app/theme/app_palette.dart';
import 'package:yemen_drive/app/theme/app_theme.dart';
import 'package:yemen_drive/features/ride/booking/widgets/booking_service_widgets.dart';
import 'package:yemen_drive/shared/widgets/app_skeleton.dart';

void main() {
  setUpAll(() async {
    for (final font in [
      ('NotoSansArabic', 'assets/fonts/NotoSansArabic.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  Widget host(Widget child, {bool reduced = false, bool dark = false}) =>
      MaterialApp(
        theme: dark
            ? AppTheme.darkFor(palette: AppPalette.olive)
            : AppTheme.lightFor(palette: AppPalette.olive),
        home: Scaffold(
            body: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Directionality(textDirection: TextDirection.rtl, child: child),
        )),
      );

  testWidgets('loading blocks placeholder taps and excludes their semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(host(AppSkeleton(
        child: TextButton(
      onPressed: () => taps++,
      child: const Text('placeholder'),
    ))));
    await tester.tap(find.byType(TextButton), warnIfMissed: false);
    expect(taps, 0);
    expect(find.bySemanticsLabel('placeholder'), findsNothing);
    expect(find.bySemanticsLabel('Loading content'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(host(AppSkeleton(
        enabled: false,
        child: TextButton(
          onPressed: () => taps++,
          child: const Text('ready'),
        ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ready'));
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    semantics.dispose();
  });

  testWidgets('reduced motion keeps skeleton without an animation ticker',
      (tester) async {
    await tester.pumpWidget(host(const AppSkeletonStrip(), reduced: true));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Skeletonizer>(
                find.byWidgetPredicate((w) => w is Skeletonizer))
            .effect,
        isA<SolidColorEffect>());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading service picker fits a short screen', (tester) async {
    tester.view.physicalSize = const Size(320, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(BookingServiceKindsSheet(
      services: const [],
      selectedId: null,
      isLoading: true,
      onSelected: (_) {},
      onClose: () {},
    )));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final dark in [false, true]) {
    testWidgets('skeleton renders in olive ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(390, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(
          RepaintBoundary(
            key: const ValueKey('loading-preview'),
            child: ColoredBox(
              color:
                  dark ? AppPalette.olive.colors.darkBackground! : Colors.white,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(children: [
                  AppSkeletonStrip(),
                  SizedBox(height: 24),
                  AppSkeletonList()
                ]),
              ),
            ),
          ),
          dark: dark));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('UPDATE_PREVIEWS')) {
        await expectLater(
            find.byKey(const ValueKey('loading-preview')),
            matchesGoldenFile(
                '../docs/previews/loading-${dark ? 'dark' : 'light'}.png'));
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
