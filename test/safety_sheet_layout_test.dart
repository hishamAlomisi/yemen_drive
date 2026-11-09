import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/app/localization/app_translations.dart';
import 'package:yemen_drive/app/theme/app_theme.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/controllers/ride_controller.dart';
import 'package:yemen_drive/features/ride/controllers/route_deviation_controller.dart';
import 'package:yemen_drive/features/ride/controllers/safety_recording_controller.dart';
import 'package:yemen_drive/features/ride/negotiation/repositories/ride_negotiation_repository.dart';
import 'package:yemen_drive/features/ride/widgets/ride_trip_widgets.dart';

class RideRepo implements RideNegotiationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DeviationRepo implements RouteDeviationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Deviation extends RouteDeviationController {
  Deviation(RideController ride) : super(DeviationRepo(), ride);
  @override
  void onInit() {}
  @override
  void onClose() {}
}

class Recording extends SafetyRecordingController {
  Recording(super.api, super.ride);
  @override
  void onClose() {}
}

void main() {
  tearDown(Get.reset);
  testWidgets('safety sheet on 320px phone with 1.35 Arabic text scale',
      (tester) async {
    Get.testMode = true;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fonts = FontLoader('BeINArabic')
      ..addFont(rootBundle.load('assets/fonts/bein_ar_regular.ttf'));
    await fonts.load();
    final storage = SecureStorageService();
    final api = ApiClient(storage);
    final ride = RideController(RideRepo(), AuthSessionService(storage, api));
    ride.chatRideId.value = '7';
    ride.activeRideStatus.value = '5';
    Get.put<SafetyRecordingController>(Recording(api, ride));
    Get.put<RouteDeviationController>(Deviation(ride));
    await tester.pumpWidget(GetMaterialApp(
      theme: AppTheme.light,
      translations: AppTranslations(),
      locale: const Locale('ar', 'SA'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ar', 'SA')],
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.35)),
          child: child!),
      home: Scaffold(
          body: TripEmergencyActions(onShareTrip: () {}, onCancelRide: () {})),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.health_and_safety_outlined));
    await tester.pumpAndSettle();
    expect(find.text('الإبلاغ عن انحراف المسار'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
