import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

import '../core/services/locale_service.dart';
import '../core/services/startup_connection_service.dart';
import '../core/services/theme_service.dart';
import '../features/auth/routes/auth_routes.dart';
import '../features/auth/splash/views/splash_view.dart';
import 'bindings/initial_binding.dart';
import 'localization/app_translations.dart';
import 'routes/app_pages.dart';
import 'theme/app_theme.dart';

class EasyRideApp extends StatefulWidget {
  const EasyRideApp({super.key});

  static Locale fallbackLocale = Locale('ar', 'SA');
  static List<Locale> supportedLocales = <Locale>[
    fallbackLocale,
    Locale('en', 'US'),
  ];

  @override
  State<EasyRideApp> createState() => _EasyRideAppState();
}

class _EasyRideAppState extends State<EasyRideApp> {
  late final StartupConnectionService _connection;
  bool _initialized = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _connection = Get.isRegistered<StartupConnectionService>()
        ? Get.find<StartupConnectionService>()
        : Get.put(StartupConnectionService(), permanent: true);
    _start();
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    try {
      if (!await _connection.verify() || !mounted) return;
      _connection.initializing();
      await InitialBinding().dependencies();
      if (mounted) setState(() => _initialized = true);
    } on Object {
      if (mounted) _connection.initializationFailed();
    } finally {
      _starting = false;
    }
  }

  @override
  Widget build(BuildContext context) => _initialized
      ? const _ConfiguredApp()
      : _BootstrapApp(connection: _connection, onRetry: _start);
}

class _ConfiguredApp extends StatelessWidget {
  const _ConfiguredApp();

  @override
  Widget build(BuildContext context) {
    final localeService = Get.find<LocaleService>();
    final themeService = Get.find<ThemeService>();
    return Obx(
      () => GetMaterialApp(
        title: 'يمن درايف',
        debugShowCheckedModeBanner: false,
        initialBinding: InitialBinding(),
        initialRoute: AuthRoutes.splash,
        getPages: AppPages.pages,
        translations: AppTranslations(),
        locale: localeService.locale.value,
        fallbackLocale: EasyRideApp.fallbackLocale,
        supportedLocales: EasyRideApp.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.lightFor(palette: themeService.palette.value),
        darkTheme: AppTheme.darkFor(palette: themeService.palette.value),
        themeMode: themeService.mode.value,
        defaultTransition: Transition.cupertino,
        transitionDuration: const Duration(milliseconds: 260),
        builder: (context, child) => Directionality(
          textDirection: _textDirectionFor(
            Localizations.maybeLocaleOf(context) ?? localeService.locale.value,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(minScaleFactor: .85, maxScaleFactor: 1.35),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  TextDirection _textDirectionFor(Locale locale) =>
      locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({required this.connection, required this.onRetry});
  final StartupConnectionService connection;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.light,
        home: Obx(
          () => SplashArtwork(
            status: connection.status.value,
            onRetry: onRetry,
          ),
        ),
      );
}
