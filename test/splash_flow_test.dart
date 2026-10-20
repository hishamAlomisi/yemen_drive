import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:yemen_drive/app/app.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/services/startup_connection_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/auth/routes/auth_routes.dart';
import 'package:yemen_drive/features/auth/splash/controllers/splash_controller.dart';
import 'package:yemen_drive/features/auth/splash/views/splash_view.dart';
import 'package:yemen_drive/features/auth/splash/widgets/splash_motion.dart';
import 'package:yemen_drive/features/ride/ride_routes.dart';

class _MemoryStorage implements GetStorage {
  bool hasSeenOnboarding = false;
  @override
  T? read<T>(String key) =>
      (key == 'has_seen_onboarding' ? hasSeenOnboarding : null) as T?;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connection extends StartupConnectionService {
  late Completer<bool> pending;
  int attempts = 0;

  @override
  Future<bool> verify() {
    attempts++;
    status.value = const StartupStatus(StartupPhase.checkingApi);
    pending = Completer<bool>();
    return pending.future;
  }

  void succeed() {
    isVerified = true;
    status.value = const StartupStatus(StartupPhase.ready);
    pending.complete(true);
  }

  void fail(StartupFailure failure) {
    isVerified = false;
    status.value = StartupStatus(StartupPhase.failed, failure: failure);
    pending.complete(false);
  }
}

void main() {
  late AuthSessionService session;
  late _Connection connection;
  late _MemoryStorage storage;

  setUpAll(() async {
    final font = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'));
    await font.load();
  });

  setUp(() {
    Get.testMode = true;
    final secureStorage = SecureStorageService();
    session = AuthSessionService(secureStorage, ApiClient(secureStorage));
    Get.put<AuthSessionService>(session);
    storage = _MemoryStorage();
    connection = _Connection();
    Get.put<StartupConnectionService>(connection);
  });

  tearDown(() => Get.reset());

  if (const bool.fromEnvironment('UPDATE_PREVIEWS')) {
    testWidgets('render entrance preview frames', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: RepaintBoundary(
            key: ValueKey('animation-preview'),
            child: SplashArtwork(),
          ),
        ),
      );
      await tester.runAsync(
        () async {
          final context =
              tester.element(find.byKey(const ValueKey('splash-rider-logo')));
          await precacheImage(
            const AssetImage(SplashArtwork.logoAsset),
            context,
          );
          if (!context.mounted) return;
          await precacheImage(
            const ResizeImage(
              AssetImage(SplashArtwork.appIconAsset),
              width: 128,
            ),
            context,
          );
        },
      );
      for (var frame = 0; frame <= 120; frame++) {
        await tester.pump(const Duration(milliseconds: 40));
        await expectLater(
          find.byKey(const ValueKey('animation-preview')),
          matchesGoldenFile(
            '../../work/rider-splash-motion-frames/frame-${frame.toString().padLeft(3, '0')}.png',
          ),
        );
      }
    });
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: '/',
        defaultTransition: Transition.noTransition,
        getPages: [
          GetPage<dynamic>(
            name: '/',
            page: () => const RepaintBoundary(
              key: ValueKey('splash-preview'),
              child: SplashScreen(),
            ),
            binding: BindingsBuilder<SplashController>(() {
              Get.put(
                SplashController(connection: connection, storage: storage),
              );
            }),
          ),
          GetPage<dynamic>(
            name: AuthRoutes.onboardingOne,
            page: () => const Scaffold(body: Text('onboarding-destination')),
          ),
          GetPage<dynamic>(
            name: RideRoutes.homeTransport,
            page: () => const Scaffold(body: Text('home-destination')),
          ),
          GetPage<dynamic>(
            name: AuthRoutes.signIn,
            page: () => const Scaffold(body: Text('signin-destination')),
          ),
        ],
      ),
    );
    await tester.pump();
  }

  testWidgets('signed-out launch shows Flutter composition before onboarding',
      (tester) async {
    await mount(tester);
    await tester.runAsync(() async {
      final element =
          tester.element(find.byKey(const ValueKey('splash-rider-logo')));
      await precacheImage(
        const AssetImage(SplashArtwork.logoAsset),
        element,
      );
      if (!element.mounted) return;
      await precacheImage(
        const ResizeImage(AssetImage(SplashArtwork.appIconAsset), width: 128),
        element,
      );
    });
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('رحلتك بين يديك'), findsNWidgets(2));
    expect(find.text('اطلب .. وانت في مكانك .. مع يمن درايف'), findsOneWidget);
    expect(find.text('طلب سريع'), findsOneWidget);
    expect(find.text('رحلات موثوقة'), findsOneWidget);
    expect(find.text('رحلات آمنة'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final logo =
        tester.widget<Image>(find.byKey(const ValueKey('splash-rider-logo')));
    expect(find.byKey(const ValueKey('splash-app-icon')), findsOneWidget);
    expect(logo.image, const AssetImage(SplashArtwork.logoAsset));
    expect(logo.fit, BoxFit.contain);
    if (const bool.fromEnvironment('UPDATE_PREVIEWS')) {
      await expectLater(
        find.byKey(const ValueKey('splash-preview')),
        matchesGoldenFile('../docs/previews/splash.png'),
      );
    }
    await tester.pump(const Duration(seconds: 15));
    expect(find.byType(SplashScreen), findsOneWidget);
    connection.succeed();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('onboarding-destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entrance reveals the logo once and leaves no idle ticker',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RepaintBoundary(
          key: ValueKey('splash-motion-preview'),
          child: SplashArtwork(status: StartupStatus(StartupPhase.ready)),
        ),
      ),
    );
    final entrance = find.byKey(const ValueKey('splash-logo-entrance'));
    final fade =
        find.descendant(of: entrance, matching: find.byType(FadeTransition));
    expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<FadeTransition>(fade).opacity.value,
      inExclusiveRange(0, 1),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SplashEntrance>(entrance).timeline.isCompleted,
      isTrue,
    );
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion presents the full composition immediately',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const SplashArtwork(),
      ),
    );
    final fade = find.descendant(
      of: find.byKey(const ValueKey('splash-logo-entrance')),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('rider logo grows from viewport center into its final position',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashArtwork(status: StartupStatus(StartupPhase.ready)),
      ),
    );
    final logo = find.byKey(const ValueKey('splash-rider-logo'));
    final initial = tester.getRect(logo);
    expect(initial.center.dx, closeTo(195, .1));
    expect(initial.center.dy, closeTo(422, .1));
    expect(initial.width, closeTo(388 * .12, .1));
    await tester.pump(const Duration(milliseconds: 500));
    final middle = tester.getRect(logo);
    expect(middle.width, greaterThan(initial.width));
    expect(middle.center.dy, lessThan(initial.center.dy));
    await tester.pumpAndSettle();
    final settled = tester.getRect(logo);
    expect(settled.width, closeTo(388, .1));
    expect(settled.center.dy, lessThan(middle.center.dy));
  });

  testWidgets('only the gold trace repeats while waiting and stops on success',
      (tester) async {
    Widget artwork(StartupPhase phase) => MaterialApp(
          home: SplashArtwork(status: StartupStatus(phase)),
        );
    await tester.pumpWidget(artwork(StartupPhase.checkingApi));
    await tester.pump();
    SplashTracePainter trace() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<SplashTracePainter>()
        .singleWhere((painter) => painter.shape == SplashTraceShape.logo);
    await tester.pump(const Duration(milliseconds: 800));
    final firstPass = trace().progress.value;
    expect(firstPass, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(trace().progress.value, closeTo(firstPass, .01));
    final entrance = tester.widget<SplashEntrance>(
      find.byKey(const ValueKey('splash-logo-entrance')),
    );
    expect(entrance.timeline.isCompleted, isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(trace().progress.value, greaterThan(firstPass));
    await tester.pumpWidget(artwork(StartupPhase.ready));
    await tester.pumpAndSettle();
    expect(trace().progress.value, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('connection updates preserve entrance and failure stops it',
      (tester) async {
    await mount(tester);
    await tester.pump(const Duration(milliseconds: 350));
    final entrance = find.byKey(const ValueKey('splash-logo-entrance'));
    final fade =
        find.descendant(of: entrance, matching: find.byType(FadeTransition));
    final before = tester.widget<FadeTransition>(fade).opacity.value;
    connection.status.value = const StartupStatus(StartupPhase.initializing);
    await tester.pump();
    expect(tester.widget<FadeTransition>(fade).opacity.value, before);
    connection.fail(StartupFailure.offline);
    await tester.pumpAndSettle();
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    connection.succeed();
    await tester.pumpAndSettle();
    expect(find.text('onboarding-destination'), findsOneWidget);
  });

  testWidgets('composition fits compact, tall and landscape screens',
      (tester) async {
    for (final size in [
      const Size(320, 568),
      const Size(390, 693),
      const Size(430, 932),
      const Size(768, 1024),
      const Size(844, 390),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 24, bottom: 20),
              textScaler: const TextScaler.linear(1.35),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: const SplashArtwork(),
        ),
      );
      await tester.pump();
      final logo = tester.getRect(
        find.byKey(const ValueKey('splash-rider-logo')),
      );
      final progress = tester.getRect(find.byType(LinearProgressIndicator));
      expect(logo.top, greaterThanOrEqualTo(24));
      expect(logo.bottom, lessThan(progress.top));
      expect(progress.bottom, lessThanOrEqualTo(size.height - 20));
      expect(tester.takeException(), isNull, reason: 'viewport $size');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('remembered session reaches the rider home after onboarding',
      (tester) async {
    session.isAuthenticated.value = true;
    storage.hasSeenOnboarding = true;
    await mount(tester);
    connection.succeed();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home-destination'), findsOneWidget);
  });

  testWidgets('returning guest reaches home only after the API succeeds',
      (tester) async {
    storage.hasSeenOnboarding = true;
    await mount(tester);
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('home-destination'), findsNothing);
    connection.succeed();
    await tester.pumpAndSettle();
    expect(find.text('home-destination'), findsOneWidget);
  });

  testWidgets('signed-out notification reaches sign-in and retains payload',
      (tester) async {
    session.openNotificationFromPush({'rideId': '2048', 'notificationId': '8'});
    await mount(tester);
    connection.succeed();
    await tester.pumpAndSettle();
    expect(find.text('signin-destination'), findsOneWidget);
    expect(session.hasPendingNotificationOpen, true);
  });

  testWidgets('cold notification retains its destination and ride data',
      (tester) async {
    session.isAuthenticated.value = true;
    session.openNotificationFromPush({'rideId': '2048', 'notificationId': '8'});
    await mount(tester);
    connection.succeed();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home-destination'), findsOneWidget);
    expect(
      ((Get.arguments as Map)['pushNotification'] as Map)['rideId'],
      '2048',
    );
    expect(session.hasPendingNotificationOpen, false);
  });

  testWidgets('leaving splash early does not replace the chosen route',
      (tester) async {
    await mount(tester);
    Get.offAllNamed<void>(RideRoutes.homeTransport);
    await tester.pumpAndSettle();
    expect(Get.isRegistered<SplashController>(), false);
    connection.succeed();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home-destination'), findsOneWidget);
  });

  testWidgets('offline failure stops loading and retry waits for the API',
      (tester) async {
    await mount(tester);
    connection.fail(StartupFailure.offline);
    await tester.pumpAndSettle();
    expect(find.text('لا يوجد اتصال بالشبكة'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('onboarding-destination'), findsNothing);
    if (const bool.fromEnvironment('UPDATE_PREVIEWS')) {
      await expectLater(
        find.byKey(const ValueKey('splash-preview')),
        matchesGoldenFile('../docs/previews/splash-offline.png'),
      );
    }
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    expect(connection.attempts, 2);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(find.byType(SplashScreen), findsOneWidget);
    connection.succeed();
    await tester.pumpAndSettle();
    expect(find.text('onboarding-destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bootstrap connection failure offers retry before services load',
      (tester) async {
    await tester.pumpWidget(const EasyRideApp());
    connection.fail(StartupFailure.timeout);
    await tester.pumpAndSettle();
    expect(find.text('انتهت مهلة الاتصال بالخادم'), findsOneWidget);
    expect(Get.isRegistered<ApiClient>(), false);
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    expect(connection.attempts, 2);
    connection.fail(StartupFailure.server);
    await tester.pumpAndSettle();
    expect(find.text('خدمة الخادم غير متاحة الآن'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure and retry stay readable on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.35),
          ),
          child: child!,
        ),
        home: SplashArtwork(
          status: const StartupStatus(
            StartupPhase.failed,
            failure: StartupFailure.unreachable,
          ),
          onRetry: () {},
        ),
      ),
    );
    await tester.pump();
    final retry = tester.getRect(find.byType(FilledButton));
    expect(retry.height, greaterThanOrEqualTo(48));
    expect(retry.bottom, lessThan(568));
    expect(tester.takeException(), isNull);
  });
}
