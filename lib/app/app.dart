import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import '../core/services/locale_service.dart';
import '../core/services/theme_service.dart';
import '../features/auth/routes/auth_routes.dart';
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
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = InitialBinding().dependencies();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.error == null) {
            return const _ConfiguredApp();
          }
          return _BootstrapApp(error: snapshot.error);
        },
      );
}

class _ConfiguredApp extends StatelessWidget {
  const _ConfiguredApp();

  @override
  Widget build(BuildContext context) {
    final localeService = Get.find<LocaleService>();
    final themeService = Get.find<ThemeService>();
    return Obx(() => GetMaterialApp(
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
              Localizations.maybeLocaleOf(context) ??
                  localeService.locale.value,
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
        ),);
  }

  TextDirection _textDirectionFor(Locale locale) =>
      locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: error == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.error_outline_rounded, size: 52),
                            const SizedBox(height: 16),
                            const Text(
                              'تعذر تهيئة التطبيق. أعد تشغيله وحاول مرة أخرى.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              error.toString(),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
}
