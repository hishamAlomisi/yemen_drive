import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:yemen_drive/features/account/wallet/repositories/wallet_transfer_repository.dart';
import 'package:yemen_drive/features/account/wallet/views/wallet_transfer_view.dart';
import 'package:yemen_drive/app/theme/app_theme.dart';

class MemoryStore implements GetStorage {
  final data = <String, dynamic>{};
  @override
  T? read<T>(String key) => data[key] as T?;
  @override
  Future<void> write(String key, dynamic value) async {
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Transfers implements WalletTransferRepository {
  final calls = <String>[];
  bool insufficient = false,
      wrongPassword = false,
      loseResponse = false,
      completed = false;
  Completer<void>? pending;
  Map<String, dynamic> get data => {
        'reference': '9d95b0d7-16dd-4499-9711-6a9e7adfd83c',
        'recipientName': 'محمد عبدالله',
        'recipientPhone': '967771234567',
        'recipientType': 'سائق',
        'amount': 1000,
        'fee': 20,
        'total': 1020,
        'note': 'تسوية حساب',
        'currency': 'YER',
        'status': completed ? 'Completed' : 'AwaitingConfirmation',
        'completedAtUtc': completed ? '2026-11-02T18:00:00Z' : null,
        'senderBalanceAfter': 8980
      };
  @override
  Future<List<Map<String, dynamic>>> history() async => [];
  @override
  Future<Map<String, dynamic>> request(
      String operation, Map<String, Object?> body) async {
    calls.add(operation);
    if (operation == 'quote' && insufficient)
      throw Exception('رصيد المحفظة لا يسمح بالمبلغ ورسوم التحويل');
    if (operation == 'confirm') {
      await pending?.future;
      if (wrongPassword)
        throw Exception('كلمة المرور غير صحيحة. لم يتم التحويل.');
      completed = true;
      if (loseResponse) throw Exception('انقطع الاتصال');
    }
    return data;
  }
}

Future<void> open(WidgetTester tester, Transfers repo, MemoryStore store,
    {double scale = 1}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
              data: MediaQueryData(
                  size: const Size(390, 844),
                  textScaler: TextScaler.linear(scale)),
              child: WalletTransferPage(
                  repository: repo, store: store, storageKey: 'test')))));
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), '771234567');
  await tester.enterText(find.byType(TextFormField).at(1), '١٠٠٠');
  await tester.enterText(find.byType(TextFormField).at(2), 'تسوية حساب');
  await tester.ensureVisible(find.text('متابعة'));
  await tester.tap(find.text('متابعة'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final primaryFont = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'));
    await primaryFont.load();
    final font = FontLoader('BeINArabic')
      ..addFont(rootBundle.load('assets/fonts/bein_ar_regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  tearDown(() => Get.reset());
  testWidgets(
      'insufficient balance shows error without confirmation or password',
      (tester) async {
    final repo = Transfers()..insufficient = true;
    await open(tester, repo, MemoryStore());
    await fill(tester);
    expect(find.textContaining('رصيد المحفظة لا يسمح'), findsOneWidget);
    expect(find.text('تأكيد التحويل'), findsNothing);
    expect(repo.calls, ['quote']);
  });
  testWidgets(
      'recipient summary precedes password; duplicate click and lost response recover one receipt',
      (tester) async {
    final repo = Transfers()
      ..loseResponse = true
      ..pending = Completer<void>();
    final store = MemoryStore();
    await open(tester, repo, store);
    await fill(tester);
    expect(find.text('محمد عبدالله (سائق)'), findsOneWidget);
    expect(find.text('رسوم التحويل: 20.00 ر.ي'), findsOneWidget);
    expect(find.text('الملاحظة: تسوية حساب'), findsOneWidget);
    expect(repo.calls, ['quote']);
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد كلمة المرور'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, 'Secret123');
    await tester.tap(find.text('تأكيد'));
    await tester.pump();
    expect(find.text('جارٍ التأكيد…'), findsOneWidget);
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('فاتورة التحويل'), findsOneWidget);
    expect(find.text('تم التحويل بنجاح'), findsOneWidget);
    expect(repo.calls.where((e) => e == 'confirm').length, 1);
    expect(repo.calls.last, 'get');
    expect(store.data, isEmpty);
  });
  testWidgets('wrong password stays in dialog and permits safe retry',
      (tester) async {
    final repo = Transfers()..wrongPassword = true;
    await open(tester, repo, MemoryStore());
    await fill(tester);
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, 'wrong');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(find.text('كلمة المرور غير صحيحة. لم يتم التحويل.'), findsOneWidget);
    expect(repo.completed, false);
    repo.wrongPassword = false;
    await tester.enterText(find.byType(TextFormField).last, 'correct');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(find.text('تم التحويل بنجاح'), findsOneWidget);
  });
  testWidgets('pending committed transfer is recovered after reopening',
      (tester) async {
    final repo = Transfers()..completed = true;
    final store = MemoryStore();
    store.data['test'] = '9d95b0d7-16dd-4499-9711-6a9e7adfd83c';
    await open(tester, repo, store);
    expect(find.text('فاتورة التحويل'), findsOneWidget);
    expect(repo.calls, ['get']);
  });
  testWidgets('Arabic confirmation fits narrow screen with larger text',
      (tester) async {
    await open(tester, Transfers(), MemoryStore(), scale: 1.3);
    await fill(tester);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/wallet-transfer-confirmation.png'));
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/wallet-transfer-password.png'));
  });
}
