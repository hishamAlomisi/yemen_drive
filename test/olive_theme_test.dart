import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:yemen_drive/app/localization/app_translations.dart';
import 'package:yemen_drive/app/theme/app_palette.dart';
import 'package:yemen_drive/app/theme/app_theme.dart';
import 'package:yemen_drive/core/services/theme_service.dart';
import 'package:yemen_drive/features/account/settings/controllers/settings_controller.dart';
import 'package:yemen_drive/features/account/settings/views/settings_view.dart';
import 'package:yemen_drive/features/auth/splash/views/splash_view.dart';
import 'package:yemen_drive/features/auth/widgets/auth_otp_page.dart';

class _Storage implements GetStorage {
  final values = <String, Object?>{};
  @override
  T? read<T>(String key) => values[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async => values[key] = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final directory = Directory('build/olive-test-storage')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.absolute.path,
    );
    await GetStorage.init();
    await (FontLoader('NotoSansArabic')
          ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  tearDown(Get.reset);

  test('new installs and missing preferences default to olive and light',
      () async {
    for (final version in [null, 2]) {
      final storage = _Storage();
      if (version != null) storage.values['passenger_design_version'] = version;
      final service = await ThemeService(storage: storage).init();
      expect(service.palette.value, AppPalette.olive);
      expect(service.mode.value, ThemeMode.light);
    }
    expect(AppTheme.light.colorScheme.primary, SplashArtwork.backgroundColor);
    expect(
        AppTheme.dark.scaffoldBackgroundColor, SplashArtwork.backgroundColor);
  });

  test(
      'saved explicit choices survive the new defaults; invalid values fall back',
      () async {
    final storage = _Storage();
    storage.values.addAll({'app_palette': 'lime', 'theme_mode': 'dark'});
    final existing = await ThemeService(storage: storage).init();
    expect(existing.palette.value, AppPalette.lime);
    expect(existing.mode.value, ThemeMode.dark);
    storage.values.addAll({'app_palette': 'unknown', 'theme_mode': 'unknown'});
    final invalid = await ThemeService(storage: storage).init();
    expect(invalid.palette.value, AppPalette.olive);
    expect(invalid.mode.value, ThemeMode.light);
  });

  testWidgets(
      'phone mode follows live brightness, persists, and is selected independently',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    final storage = _Storage();
    final service = await ThemeService(storage: storage).init();
    Get.put(service);
    Get.put(SettingsController());
    await tester.pumpWidget(Obx(() => GetMaterialApp(
          theme: AppTheme.lightFor(palette: service.palette.value),
          darkTheme: AppTheme.darkFor(palette: service.palette.value),
          themeMode: service.mode.value,
          home: const Directionality(
              textDirection: TextDirection.rtl, child: SettingsPage()),
        )));
    await tester.pumpAndSettle();
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(SettingsPage))).brightness;
    // The phone is dark, but the first-run default is explicitly light.
    expect(brightness(), Brightness.light);
    await tester.tap(find.text('مظهر التطبيق'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('theme-mode-system')));
    await tester.tap(find.byKey(const ValueKey('theme-mode-system')));
    await tester.pumpAndSettle();
    expect(service.mode.value, ThemeMode.system);
    expect(brightness(), Brightness.dark);
    expect(find.text('حسب إعدادات الهاتف'), findsOneWidget);
    expect((await ThemeService(storage: storage).init()).mode.value,
        ThemeMode.system);

    await tester.tap(find.text('مظهر التطبيق'));
    await tester.pumpAndSettle();
    void expectSelectedMode(ThemeMode mode) {
      for (final candidate in ThemeMode.values) {
        final tile = tester.widget<ListTile>(
            find.byKey(ValueKey('theme-mode-${candidate.name}')));
        expect(tile.selected, candidate == mode);
      }
    }

    expectSelectedMode(ThemeMode.system);
    dispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    expectSelectedMode(ThemeMode.system);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('theme-mode-light')));
    await tester.pumpAndSettle();
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    await service.setMode(ThemeMode.dark);
    dispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
  });

  test('olive follows splash colors with readable controls in both modes', () {
    final light = AppTheme.lightFor(palette: AppPalette.olive);
    final dark = AppTheme.darkFor(palette: AppPalette.olive);
    expect(light.colorScheme.primary, SplashArtwork.backgroundColor);
    expect(light.colorScheme.onPrimary, Colors.white);
    expect(dark.scaffoldBackgroundColor, SplashArtwork.backgroundColor);
    expect(dark.colorScheme.surface, SplashArtwork.backgroundColor);
    expect(dark.colorScheme.primary, SplashArtwork.gold);
    expect(dark.colorScheme.onPrimary, SplashArtwork.backgroundColor);
    for (final theme in [light, dark]) {
      final scheme = theme.colorScheme;
      for (final pair in [
        (scheme.primary, scheme.onPrimary),
        (scheme.surface, scheme.onSurface),
        (scheme.surfaceContainer, scheme.onSurfaceVariant),
      ]) {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
    }
  });

  test('olive and mode survive restart and migration preserves choices',
      () async {
    final storage = _Storage();
    final service = await ThemeService(storage: storage).init();
    await service.setPalette(AppPalette.olive);
    await service.setMode(ThemeMode.dark);
    final restarted = await ThemeService(storage: storage).init();
    expect(restarted.palette.value, AppPalette.olive);
    expect(restarted.mode.value, ThemeMode.dark);
    storage.values.remove('passenger_design_version');
    expect((await ThemeService(storage: storage).init()).palette.value,
        AppPalette.olive);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('olive picker and OTP fit small screens in ${mode.name}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = await ThemeService(storage: _Storage()).init();
      service.mode.value = mode;
      Get.put(service);
      Get.put(SettingsController());
      Widget host(Widget child) => Obx(() => GetMaterialApp(
            translations: AppTranslations(),
            locale: const Locale('ar', 'SA'),
            theme: AppTheme.lightFor(palette: service.palette.value),
            darkTheme: AppTheme.darkFor(palette: service.palette.value),
            themeMode: service.mode.value,
            home: RepaintBoundary(
              key: const ValueKey('preview'),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: child,
              ),
            ),
          ));
      await tester.pumpWidget(host(const SettingsPage()));
      await tester.tap(find.text('هوية الألوان'));
      await tester.pumpAndSettle();
      final oliveOption = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('الثيم الزيتي'),
      );
      await tester.ensureVisible(oliveOption);
      await tester.tap(oliveOption);
      await tester.pumpAndSettle();
      expect(service.palette.value, AppPalette.olive);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('UPDATE_PREVIEWS')) {
        await expectLater(
            find.byKey(const ValueKey('preview')),
            matchesGoldenFile(
                '../docs/previews/olive-settings-${mode.name}.png'));
      }
      await tester.pumpWidget(host(AuthOtpPage(
        title: 'تأكيد رقم الهاتف',
        subtitle: 'أدخل رمز التحقق المرسل إلى هاتفك',
        codeField: const TextField(),
        isLoading: false,
        onVerify: () {},
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('UPDATE_PREVIEWS')) {
        await expectLater(find.byKey(const ValueKey('preview')),
            matchesGoldenFile('../docs/previews/olive-otp-${mode.name}.png'));
      }
    });
  }
}
