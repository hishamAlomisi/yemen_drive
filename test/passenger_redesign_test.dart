import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/app/localization/app_translations.dart';
import 'package:yemen_drive/app/theme/app_theme.dart';
import 'package:yemen_drive/features/account/profile/controllers/profile_controller.dart';
import 'package:yemen_drive/features/account/profile/repositories/profile_repository.dart';
import 'package:yemen_drive/features/account/profile/views/profile_view.dart';
import 'package:yemen_drive/features/ride/widgets/ride_booking_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'));
    await loader.load();
  });
  tearDown(Get.reset);

  Widget host(Widget child, {TextDirection direction = TextDirection.rtl}) =>
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('ar', 'SA'),
        theme: AppTheme.light,
        home: Scaffold(
          body: Directionality(textDirection: direction, child: child),
        ),
      );

  for (final direction in TextDirection.values) {
    testWidgets('payment stays right of search in $direction on a narrow phone',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var searches = 0;
      await tester.pumpWidget(host(
        BookingActionBar(
          label: 'البحث عن السائقين',
          onPressed: () => searches++,
          paymentButton: PaymentPreferenceButton(
            method: 'cash',
            onSelected: (_) {},
          ),
        ),
        direction: direction,
      ));
      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(find.byType(PaymentPreferenceButton)).dx,
        greaterThan(tester.getCenter(find.text('البحث عن السائقين')).dx),
      );
      await tester.tap(find.text('البحث عن السائقين'));
      expect(searches, 1);
    });
  }

  testWidgets(
      'dismissal keeps the method; choosing wallet returns only a preference',
      (tester) async {
    var method = 'cash';
    var selectionCount = 0;
    await tester.pumpWidget(host(PaymentPreferenceButton(
      method: method,
      onSelected: (value) {
        method = value;
        selectionCount++;
      },
    )));
    await tester.tap(find.byTooltip('طريقة الدفع'));
    await tester.pumpAndSettle();
    expect(find.text('طريقة الدفع'), findsOneWidget);
    expect(find.text('تأكيد ودفع'), findsNothing);
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(method, 'cash');
    expect(selectionCount, 0);
    await tester.tap(find.byTooltip('طريقة الدفع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المحفظة'));
    await tester.pumpAndSettle();
    expect(method, 'wallet');
    expect(selectionCount, 1);
    expect(find.byType(PaymentPreferenceSheet), findsNothing);
  });

  testWidgets('payment choice is locked while search is active',
      (tester) async {
    await tester.pumpWidget(host(PaymentPreferenceButton(
      method: 'cash',
      enabled: false,
      onSelected: (_) => fail('A disabled selector must not change the method'),
    )));
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentPreferenceSheet), findsNothing);
  });

  testWidgets('payment options fit a short screen with larger Arabic text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.35)),
      child: const PaymentPreferenceSheet(selected: 'wallet'),
    )));
    expect(tester.takeException(), isNull);
    expect(find.text('المحفظة'), findsOneWidget);
  });

  testWidgets('drawer shows the current profile and fits a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Get.put(ProfileController(_ProfileFixture()));
    await tester.pumpWidget(host(const SideMenuPage()));
    await tester.pumpAndSettle();
    expect(find.text('راكب تجريبي'), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ProfileFixture implements ProfileRepository {
  @override
  Future<ProfileData> get() async => const ProfileData(name: 'راكب تجريبي');

  @override
  Future<ProfileData> update({
    String? name,
    String? phone,
    String? gender,
    String? street,
  }) async =>
      throw StateError('Profile edits must not occur during a drawer preview');
}
