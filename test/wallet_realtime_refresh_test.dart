import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/core/realtime/tracking_hub_service.dart';
import 'package:yemen_drive/core/realtime/state_change_coordinator.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/account/wallet/controllers/wallet_controller.dart';
import 'package:yemen_drive/features/account/wallet/repositories/wallet_repository.dart';
import 'package:yemen_drive/features/account/wallet/models/wallet_models.dart';
import 'package:yemen_drive/features/account/wallet/views/wallet_view.dart';

class Hub extends TrackingHubService {
  Hub() : super(SecureStorageService());
  final changes = StreamController<TrackingHubEvent>.broadcast();
  final restores = StreamController<void>.broadcast();
  @override
  Stream<TrackingHubEvent> get events => changes.stream;
  @override
  Stream<void> get connectionRestored => restores.stream;
  @override
  Future<void> setUserEventListening(Object owner, bool listen) async {}
}

class Wallets implements WalletRepository {
  double balance = 100;
  double debt = 0;
  bool fail = false;
  Completer<WalletSnapshot>? pending;
  int reads = 0;
  @override
  Future<WalletSnapshot> wallet() async {
    reads++;
    if (fail) throw Exception('offline');
    return pending?.future ??
        WalletSnapshot(
            balance: balance, ledgerDebt: debt, transactions: const []);
  }
}

void main() {
  testWidgets(
      'unrelated chat and notification events preserve an in-flight wallet read',
      (tester) async {
    final hub = Get.put<TrackingHubService>(Hub(), permanent: true) as Hub;
    final repo = Wallets();
    final wallet = Get.put<WalletController>(WalletController(repo));
    try {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      final recovering = hub.stateChanges.recover(
          (_, __) async => {'supported': true, 'hasMore': false, 'events': []});
      await tester.pumpAndSettle();
      await recovering;
      final readsBefore = repo.reads;
      repo.pending = Completer<WalletSnapshot>();
      final loading = wallet.loadTransactions();
      await tester.pump();
      hub.stateChanges.observe(const StateChange('messages:9', 1, 'messages', 9));
      hub.stateChanges
          .observe(const StateChange('notifications:2', 1, 'notifications', 2));
      await tester.pump();
      final pending = repo.pending!;
      repo.pending = null;
      repo.balance = 999;
      pending.complete(const WalletSnapshot(balance: 850, transactions: []));
      await tester.pumpAndSettle();
      await loading;
      expect(repo.reads, readsBefore + 1);
      expect(wallet.walletBalance.value, 850);
      expect(hub.stateChanges.versions['messages:9'], 1);
      expect(hub.stateChanges.versions['notifications:2'], 1);
    } finally {
      hub.stateChanges.dispose();
      Get.delete<WalletController>(force: true);
      await hub.changes.close();
      await hub.restores.close();
      Get.reset();
    }
  });
  testWidgets(
      'durable wallet recovery is acknowledged only after a successful canonical read',
      (tester) async {
    final hub = Get.put<TrackingHubService>(Hub(), permanent: true) as Hub;
    final repo = Wallets();
    final wallet = Get.put<WalletController>(WalletController(repo));
    Map<Object?, Object?> page() => {
          'supported': true,
          'hasMore': false,
          'events': [
            {
              'stream': 'wallet:7',
              'version': 1,
              'resource': 'wallet',
              'resourceId': 7
            }
          ]
        };
    try {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      repo.fail = true;
      final first = expectLater(
          hub.stateChanges.recover((_, __) async => page()), throwsException);
      await tester.pumpAndSettle();
      await first;
      expect(hub.stateChanges.versions, isEmpty);
      expect(wallet.walletBalance.value, 100);
      repo.fail = false;
      repo.balance = 850;
      final second = hub.stateChanges.recover((_, __) async => page());
      await tester.pumpAndSettle();
      await second;
      expect(wallet.walletBalance.value, 850);
      expect(hub.stateChanges.versions['wallet:7'], 1);
    } finally {
      hub.stateChanges.dispose();
      Get.delete<WalletController>(force: true);
      await hub.changes.close();
      await hub.restores.close();
      Get.reset();
    }
  });
  testWidgets(
      'durable event discards a wallet response started before the event',
      (tester) async {
    final hub = Get.put<TrackingHubService>(Hub(), permanent: true) as Hub;
    final repo = Wallets();
    final wallet = Get.put<WalletController>(WalletController(repo));
    final shown = <double>[];
    final listener = wallet.walletBalance.listen(shown.add);
    try {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      final recovering = hub.stateChanges.recover(
          (_, __) async => {'supported': true, 'hasMore': false, 'events': []});
      await tester.pumpAndSettle();
      await recovering;
      repo.pending = Completer<WalletSnapshot>();
      unawaited(wallet.loadTransactions());
      await tester.pump();
      hub.stateChanges.observe(const StateChange('wallet:7', 2, 'wallet', 7));
      await tester.pump();
      final pending = repo.pending!;
      repo.pending = null;
      repo.balance = 950;
      pending.complete(const WalletSnapshot(balance: 15, transactions: []));
      await tester.pumpAndSettle();
      expect(shown, isNot(contains(15)));
      expect(wallet.walletBalance.value, 950);
      expect(hub.stateChanges.versions['wallet:7'], 2);
    } finally {
      await listener.cancel();
      hub.stateChanges.dispose();
      Get.delete<WalletController>(force: true);
      await hub.changes.close();
      await hub.restores.close();
      Get.reset();
    }
  });
  testWidgets(
      'wallet shows approved debt separately and removes it after a deposit settles it',
      (tester) async {
    final hub = Get.put<TrackingHubService>(Hub(), permanent: true) as Hub;
    final repo = Wallets()
      ..balance = 0
      ..debt = 549;
    final wallet = Get.put<WalletController>(WalletController(repo));
    try {
      await tester
          .pumpWidget(const GetMaterialApp(home: WalletPage(embedded: true)));
      await tester.pumpAndSettle();
      expect(find.text('مديونية المحفظة: 549.00 ر.ي'), findsOneWidget);
      repo.balance = 51;
      repo.debt = 0;
      hub.changes.add(TrackingHubEvent('notificationCreated', {}));
      await tester.pumpAndSettle();
      expect(find.textContaining('مديونية المحفظة:'), findsNothing);
      expect(wallet.walletBalance.value, 51);
    } finally {
      Get.delete<WalletController>(force: true);
      await hub.changes.close();
      await hub.restores.close();
      Get.reset();
    }
  });
  testWidgets(
      'wallet updates on notification, reconnect and resume and retains confirmed balance offline',
      (tester) async {
    final hub = Get.put<TrackingHubService>(Hub(), permanent: true) as Hub;
    final repo = Wallets();
    final wallet = Get.put<WalletController>(WalletController(repo));
    try {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(wallet.walletBalance.value, 100);
      repo.balance = 250;
      hub.changes.add(TrackingHubEvent('notificationCreated', {}));
      await tester.pumpAndSettle();
      expect(wallet.walletBalance.value, 250);
      repo.balance = 300;
      hub.restores.add(null);
      await tester.pumpAndSettle();
      expect(wallet.walletBalance.value, 300);
      repo.balance = 400;
      wallet.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(wallet.walletBalance.value, 400);
      repo.fail = true;
      hub.changes.add(TrackingHubEvent('notificationCreated', {}));
      await tester.pumpAndSettle();
      expect(wallet.walletBalance.value, 400);
    } finally {
      Get.delete<WalletController>(force: true);
      await hub.changes.close();
      await hub.restores.close();
      Get.reset();
    }
  });
  testWidgets('wallet change during a pending fetch triggers a second fetch',
      (tester) async {
    final hub = Get.put<TrackingHubService>(Hub(), permanent: true) as Hub;
    final repo = Wallets()..pending = Completer<WalletSnapshot>();
    final wallet = Get.put<WalletController>(WalletController(repo));
    try {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      hub.changes.add(TrackingHubEvent('notificationCreated', {}));
      await tester.pump();
      final pending = repo.pending!;
      repo.pending = null;
      repo.balance = 800;
      pending.complete(const WalletSnapshot(balance: 100, transactions: []));
      await tester.pumpAndSettle();
      expect(repo.reads, 2);
      expect(wallet.walletBalance.value, 800);
    } finally {
      Get.delete<WalletController>(force: true);
      await hub.changes.close();
      await hub.restores.close();
      Get.reset();
    }
  });
}
