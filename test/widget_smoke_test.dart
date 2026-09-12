import 'package:yemen_drive/app/localization/app_translations.dart';
import 'package:yemen_drive/app/theme/app_theme.dart';
import 'package:yemen_drive/features/auth/login/controllers/login_controller.dart';
import 'package:yemen_drive/features/auth/routes/auth_routes.dart';
import 'package:yemen_drive/core/config/app_environment.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  setUp(() {
    Get.testMode = true;
  });

  tearDown(() => Get.reset());

  testWidgets('تفتح شاشة تسجيل الدخول دون اتصال شبكي', (
    WidgetTester tester,
  ) async {
    AppEnvironment.configure(
        flavor: 'test', baseUrl: 'http://localhost:5080/api');
    final storage = Get.put<SecureStorageService>(SecureStorageService());
    await Get.putAsync<ApiClient>(() => ApiClient(storage).init());
    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        translations: AppTranslations(),
        locale: const Locale('ar', 'SA'),
        fallbackLocale: const Locale('ar', 'SA'),
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        initialRoute: AuthRoutes.signIn,
        getPages: authPages,
      ),
    );

    await tester.pump();

    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.text('رقم الجوال'), findsOneWidget);
    expect(Get.isRegistered<LoginController>(), isTrue);
    expect(
      Directionality.of(tester.element(find.byType(Scaffold).first)),
      TextDirection.rtl,
    );
  });
}
