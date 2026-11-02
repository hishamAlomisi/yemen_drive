import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import '../lib/core/network/api_client.dart';
import '../lib/core/network/api_models.dart';
import '../lib/core/storage/secure_storage_service.dart';
import '../lib/shared/widgets/ride_financial_follow_up.dart';

class FollowUpApi extends ApiClient {
  FollowUpApi() : super(SecureStorageService());
  bool offlineCancellation = false;
  bool reviewed = false;
  bool driverDecision = false;
  bool cashReceipt = false;
  int decisions = 0;
  @override
  Future<ApiResult<T>> execute<T>({required String model, required String operation, Object? data, T Function(Object?)? parse}) async {
    Object? value;
    if (model == 'RideModel') {
      value = {'ride': {'status': 6, 'serviceEndedAtUtc': '2026-11-01T10:00:00Z'}, 'finance': {'amountDue': 1000, 'paidAmount': 400, 'refundedAmount': 0, 'outstandingAmount': 600, 'refundDue': 0, 'amountUnderReview': reviewed}};
    } else if (model == 'RideFinancialCaseModel') {
      if (operation == 'accept') { decisions++; cashReceipt = true; }
      value = operation == 'list' ? [{'id': 1, 'kind': 'CashChange', 'status': cashReceipt ? 'Resolved' : 'AwaitingCashReceipt', 'amount': 100}] : {};
    } else {
      if (operation == 'accept' || operation == 'reject') { decisions++; driverDecision = false; value = {}; }
      else if (offlineCancellation) { return const ApiFailure(ApiProblemDetails(title: 'Offline', status: 0)) as ApiResult<T>; }
      else if (driverDecision) { value = {'id': 2, 'canDecide': true, 'reason': 'إلغاء قبل الصعود', 'refundDestination': 'VerifiedAlternative'}; }
      else { return const ApiFailure(ApiProblemDetails(title: 'Absent', status: 404, code: 'cancellation_request_not_found')) as ApiResult<T>; }
    }
    return ApiSuccess(parse == null ? value as T : parse(value));
  }
}

void main() {
  tearDown(() => Get.reset());
  testWidgets('partial invoice pays only remainder and independently follows cash receipt', (tester) async {
    final api = Get.put<ApiClient>(FollowUpApi()) as FollowUpApi;
    var paid = 0;
    await tester.pumpWidget(GetMaterialApp(home: RideFinancialFollowUp(rideId: 7, onPay: () async { paid++; })));
    await tester.pumpAndSettle();
    expect(find.text('600.00 YER'), findsOneWidget);
    await tester.tap(find.text('سداد المتبقي / تغيير طريقة الدفع'));
    await tester.pumpAndSettle(); expect(paid, 1);
    await tester.scrollUntilVisible(find.text('استلمت الباقي نقداً'), 160);
    await tester.tap(find.text('استلمت الباقي نقداً')); await tester.pumpAndSettle();
    expect(api.decisions, 0);
    expect(find.text('أكد استلامك الفعلي للباقي.'), findsOneWidget);
    await tester.tap(find.text('تأكيد')); await tester.pumpAndSettle();
    expect(api.decisions, 1); expect(find.text('استلمت الباقي نقداً'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('cancellation network failure is not treated as absence; refresh recovers decisions', (tester) async {
    final api = Get.put<ApiClient>(FollowUpApi()) as FollowUpApi;
    api.offlineCancellation = true;
    await tester.pumpWidget(GetMaterialApp(home: RideFinancialFollowUp(rideId: 7, onPay: () async {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.text('سداد المتبقي / تغيير طريقة الدفع'), findsNothing);
    api.offlineCancellation = false;
    await tester.tap(find.text('تحديث الحالة المؤكدة')); await tester.pumpAndSettle();
    expect(find.text('سداد المتبقي / تغيير طريقة الدفع'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('driver decides closed transport cancellation through authoritative follow-up', (tester) async {
    final api = Get.put<ApiClient>(FollowUpApi()) as FollowUpApi;
    api.driverDecision = true;
    await tester.pumpWidget(const GetMaterialApp(home: RideFinancialFollowUp(rideId: 7, isDriver: true)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('أعترض وأحيل للمراجعة'), 160);
    await tester.tap(find.text('أعترض وأحيل للمراجعة')); await tester.pumpAndSettle();
    expect(api.decisions, 1); expect(find.text('أعترض وأحيل للمراجعة'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('unreviewed cancellation does not offer collection and fits large text', (tester) async {
    final api = Get.put<ApiClient>(FollowUpApi()) as FollowUpApi;
    api.reviewed = true;
    tester.view.physicalSize = const Size(360, 680); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(GetMaterialApp(home: MediaQuery(data: const MediaQueryData(size: Size(360, 680), textScaler: TextScaler.linear(1.5)), child: RideFinancialFollowUp(rideId: 7, onPay: () async {}))));
    await tester.pumpAndSettle();
    expect(find.text('سداد المتبقي / تغيير طريقة الدفع'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
