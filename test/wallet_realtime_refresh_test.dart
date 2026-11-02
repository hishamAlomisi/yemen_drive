import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/core/realtime/tracking_hub_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/account/wallet/controllers/wallet_controller.dart';
import 'package:yemen_drive/features/account/wallet/repositories/wallet_repository.dart';
import 'package:yemen_drive/features/account/wallet/models/wallet_models.dart';
import 'package:yemen_drive/features/account/wallet/views/wallet_view.dart';

class Hub extends TrackingHubService {
  Hub() : super(SecureStorageService());
  final changes = StreamController<TrackingHubEvent>.broadcast();
  final restores = StreamController<void>.broadcast();
  @override Stream<TrackingHubEvent> get events => changes.stream;
  @override Stream<void> get connectionRestored => restores.stream;
  @override Future<void> setUserEventListening(Object owner, bool listen) async {}
}
class Wallets implements WalletRepository {
  double balance = 100;
  double debt = 0;
  bool fail = false;
  Completer<WalletSnapshot>? pending;
  int reads = 0;
  @override Future<WalletSnapshot> wallet() async {
    reads++; if (fail) throw Exception('offline');
    return pending?.future ?? WalletSnapshot(balance: balance, ledgerDebt: debt, transactions: const []);
  }
}
void main() {
  testWidgets('wallet shows approved debt separately and removes it after a deposit settles it', (tester) async {
    final hub = Get.put<TrackingHubService>(Hub(), permanent: true) as Hub;
    final repo = Wallets()..balance = 0..debt = 549; final wallet = Get.put<WalletController>(WalletController(repo));
    try {
      await tester.pumpWidget(const GetMaterialApp(home: WalletPage(embedded: true))); await tester.pumpAndSettle();
      expect(find.text('مديونية المحفظة: 549.00 ر.ي'), findsOneWidget);
      repo.balance = 51; repo.debt = 0; hub.changes.add(TrackingHubEvent('notificationCreated', {})); await tester.pumpAndSettle();
      expect(find.textContaining('مديونية المحفظة:'), findsNothing); expect(wallet.walletBalance.value, 51);
    } finally { Get.delete<WalletController>(force: true); await hub.changes.close(); await hub.restores.close(); Get.reset(); }
  });
  testWidgets('wallet updates on notification, reconnect and resume and retains confirmed balance offline', (tester) async {
    final hub = Get.put<TrackingHubService>(Hub(), permanent: true) as Hub;
    final repo = Wallets(); final wallet = Get.put<WalletController>(WalletController(repo));
    try {
      await tester.pumpWidget(const MaterialApp(home: SizedBox())); await tester.pumpAndSettle();
      expect(wallet.walletBalance.value, 100);
      repo.balance = 250; hub.changes.add(TrackingHubEvent('notificationCreated', {})); await tester.pumpAndSettle(); expect(wallet.walletBalance.value, 250);
      repo.balance = 300; hub.restores.add(null); await tester.pumpAndSettle(); expect(wallet.walletBalance.value, 300);
      repo.balance = 400; wallet.didChangeAppLifecycleState(AppLifecycleState.resumed); await tester.pumpAndSettle(); expect(wallet.walletBalance.value, 400);
      repo.fail = true; hub.changes.add(TrackingHubEvent('notificationCreated', {})); await tester.pumpAndSettle(); expect(wallet.walletBalance.value, 400);
    } finally { Get.delete<WalletController>(force: true); await hub.changes.close(); await hub.restores.close(); Get.reset(); }
  });
  testWidgets('wallet change during a pending fetch triggers a second fetch', (tester) async {
    final hub = Get.put<TrackingHubService>(Hub(), permanent: true) as Hub;
    final repo = Wallets()..pending = Completer<WalletSnapshot>(); final wallet = Get.put<WalletController>(WalletController(repo));
    try {
      await tester.pumpWidget(const MaterialApp(home: SizedBox())); await tester.pump();
      hub.changes.add(TrackingHubEvent('notificationCreated', {})); await tester.pump();
      final pending = repo.pending!; repo.pending = null; repo.balance = 800; pending.complete(const WalletSnapshot(balance: 100, transactions: []));
      await tester.pumpAndSettle(); expect(repo.reads, 2); expect(wallet.walletBalance.value, 800);
    } finally { Get.delete<WalletController>(force: true); await hub.changes.close(); await hub.restores.close(); Get.reset(); }
  });
}
