import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/core/network/api_client.dart';
import 'package:yemen_drive/core/network/api_models.dart';
import 'package:yemen_drive/core/realtime/tracking_hub_service.dart';
import 'package:yemen_drive/core/services/auth_session_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';
import 'package:yemen_drive/features/ride/controllers/chat_controller.dart';
import 'package:yemen_drive/features/ride/controllers/ride_controller.dart';

class _Session extends GetxService implements AuthSessionService {
  @override
  final RxBool isAuthenticated = true.obs;
  @override
  final RxnInt currentUserId = RxnInt(10);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ride extends GetxController implements RideController {
  @override
  final RxnString chatRideId = RxnString('7');
  @override
  String? get currentRideId => chatRideId.value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Hub extends TrackingHubService {
  _Hub() : super(SecureStorageService());
  final messages = StreamController<TrackingHubEvent>.broadcast();
  @override
  Stream<TrackingHubEvent> get events => messages.stream;
  @override
  Stream<void> get connectionRestored => const Stream.empty();
  @override
  Future<void> setUserEventListening(Object owner, bool listen) async {}
}

class _Api extends ApiClient {
  _Api() : super(SecureStorageService());
  List<Map<String, Object?>> rows = [];
  Completer<List<Map<String, Object?>>>? pending;
  Completer<Object?>? sending;
  int reads = 0;
  final List<Map<String, Object?>> acknowledgments = [];
  @override
  Future<ApiResult<T>> execute<T>({
    required String model,
    required String operation,
    Object? data,
    T Function(Object?)? parse,
  }) async {
    final args = Map<String, Object?>.from(data as Map);
    if (operation == 'add') return ApiSuccess<T>(await sending!.future as T);
    if (operation == 'update') {
      acknowledgments.add(args);
      final ids = args['messageIds'] as List;
      final updated = rows.where((row) => ids.contains(row['id'])).map((row) {
        row['deliveredAtUtc'] ??= '2026-11-03T12:01:00Z';
        if (args['markRead'] == true)
          row['readAtUtc'] ??= '2026-11-03T12:02:00Z';
        return Map<String, Object?>.from(row);
      }).toList();
      return ApiSuccess<T>(updated as T);
    }
    if (operation == 'report') {
      return ApiSuccess<T>({
        'rideId': 7,
        'unreadCount': rows
            .where((row) => row['senderId'] != 10 && row['readAtUtc'] == null)
            .length,
        'lastMessageId': rows.isEmpty ? null : rows.last['id'],
      } as T);
    }
    reads++;
    return ApiSuccess<T>((pending == null ? rows : await pending!.future) as T);
  }
}

Map<String, Object?> _message(int id, String text) => {
      'id': id,
      'senderId': 11,
      'recipientId': 10,
      'rideId': 7,
      'content': text,
      'createdAtUtc': '2026-11-03T12:00:00Z',
    };

void main() {
  testWidgets('sending, delivery and reading advance only on server receipts',
      (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    final hub = _Hub();
    final api = _Api()..sending = Completer<Object?>();
    final chat = Get.put(ChatController(api, _Session(), _Ride(), hub));
    await tester.pumpAndSettle();
    chat.messageController.text = 'on my way';
    final sending = chat.sendMessage();
    expect(chat.messages.single.isPending, isTrue);
    expect(chat.messages.single.deliveredAtUtc, isNull);
    final sent = {..._message(8, 'on my way'), 'senderId': 10};
    api.rows = [sent];
    hub.messages.add(TrackingHubEvent('rideMessageCreated', sent));
    await tester.pumpAndSettle();
    expect(chat.messages.length, 1);
    expect(chat.messages.single.id, 8);
    expect(chat.isSending.value, isTrue);
    api.sending!.complete(sent);
    await sending;
    expect(chat.messages.single.isPending, isFalse);
    expect(chat.messages.single.deliveredAtUtc, isNull);
    final delivered = {...sent, 'deliveredAtUtc': '2026-11-03T12:03:00Z'};
    hub.messages.add(TrackingHubEvent('rideMessageUpdated', delivered));
    await tester.pumpAndSettle();
    expect(chat.messages.single.deliveredAtUtc, isNotNull);
    expect(chat.messages.single.readAtUtc, isNull);
    hub.messages.add(TrackingHubEvent('rideMessageUpdated', {
      ...delivered,
      'readAtUtc': '2026-11-03T12:04:00Z',
    }));
    await tester.pumpAndSettle();
    hub.messages.add(TrackingHubEvent('rideMessageCreated', sent));
    await tester.pumpAndSettle();
    expect(chat.messages.single.readAtUtc, isNotNull);
    expect(chat.messages.single.deliveredAtUtc, isNotNull);
    expect(api.acknowledgments, isEmpty);
    api.sending = Completer<Object?>();
    chat.messageController.text = 'received before timeout';
    final lostResponse = chat.sendMessage();
    final echoed = {..._message(9, 'received before timeout'), 'senderId': 10};
    api.rows.add(echoed);
    hub.messages.add(TrackingHubEvent('rideMessageCreated', echoed));
    await tester.pumpAndSettle();
    api.sending!.completeError(StateError('HTTP response lost'));
    await lostResponse;
    expect(chat.messages.length, 2);
    expect(chat.messages.any((row) => row.isPending), isFalse);
    expect(chat.messageController.text, isEmpty);
    expect(chat.error.value, isNull);
    Get.delete<ChatController>(force: true);
    hub.stateChanges.dispose();
    await hub.messages.close();
    Get.reset();
  });
  testWidgets('messages stream recovers chat without the legacy message event',
      (tester) async {
    final hub = _Hub();
    final api = _Api();
    final chat = Get.put(ChatController(api, _Session(), _Ride(), hub));
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();
    hub.supportsStateRecovery.value = true;
    api.rows = [_message(1, 'committed')];
    final recovery = hub.stateChanges.recover((_, __) async => {
          'supported': true,
          'hasMore': false,
          'events': [
            {
              'schemaVersion': 1,
              'stream': 'messages:7',
              'version': 2,
              'resource': 'messages',
              'resourceId': 7,
            }
          ],
        });
    await tester.pumpAndSettle();
    await recovery;
    expect(chat.messages.single.text, 'committed');
    expect(hub.stateChanges.versions['messages:7'], 2);
    hub.messages
        .add(TrackingHubEvent('rideMessageCreated', _message(1, 'old')));
    await tester.pumpAndSettle();
    expect(chat.messages.single.text, 'committed');
    Get.delete<ChatController>(force: true);
    hub.stateChanges.dispose();
    await hub.messages.close();
    Get.reset();
  });

  testWidgets('late chat history from a previous account cannot be displayed',
      (tester) async {
    final hub = _Hub();
    final api = _Api()..rows = [_message(2, 'current')];
    final session = _Session();
    final chat = Get.put(ChatController(api, session, _Ride(), hub));
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();
    final pending = api.pending = Completer<List<Map<String, Object?>>>();
    final loading = chat.loadOlderMessages();
    api.rows = [];
    api.pending = null;
    session.currentUserId.value = 99;
    pending.complete([_message(1, 'other-account')]);
    await loading;
    await tester.pumpAndSettle();
    expect(chat.messages, isEmpty);
    Get.delete<ChatController>(force: true);
    hub.stateChanges.dispose();
    await hub.messages.close();
    Get.reset();
  });

  testWidgets(
      'live arrival renders with recovery enabled; badges clear only in visible chat',
      (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    final hub = _Hub();
    final api = _Api();
    var sounds = 0;
    final chat = Get.put(
        ChatController(api, _Session(), _Ride(), hub, playSound: () async {
      sounds++;
    }));
    chat.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    hub.supportsStateRecovery.value = true;
    api.rows = [_message(1, 'outside')];
    hub.messages
        .add(TrackingHubEvent('rideMessageCreated', _message(1, 'outside')));
    await tester.pumpAndSettle();
    expect(chat.messages.single.text, 'outside');
    expect(chat.unreadCount.value, 1);
    expect(sounds, 0);
    expect(api.acknowledgments.every((a) => a['markRead'] == false), isTrue);
    chat.setPageVisible(true);
    await tester.pumpAndSettle();
    expect(chat.unreadCount.value, 0);
    expect(sounds, 0);
    api.rows.add(_message(2, 'inside'));
    hub.messages
        .add(TrackingHubEvent('rideMessageCreated', _message(2, 'inside')));
    await tester.pumpAndSettle();
    expect(chat.messages.length, 2);
    expect(sounds, 1);
    expect(chat.messages.last.readAtUtc, isNotNull);
    hub.messages.add(
        TrackingHubEvent('rideMessageCreated', _message(2, 'stale duplicate')));
    await tester.pumpAndSettle();
    expect(sounds, 1);
    expect(chat.messages.last.text, 'inside');
    expect(chat.messages.last.readAtUtc, isNotNull);
    chat.setPageVisible(false);
    api.rows.add(_message(3, 'covered'));
    hub.messages
        .add(TrackingHubEvent('rideMessageCreated', _message(3, 'covered')));
    await tester.pumpAndSettle();
    expect(chat.unreadCount.value, 1);
    expect(chat.messages.last.readAtUtc, isNull);
    expect(sounds, 1);
    Get.delete<ChatController>(force: true);
    hub.stateChanges.dispose();
    await hub.messages.close();
    Get.reset();
  });

  testWidgets('background messages remain unread and silent until chat resumes',
      (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    final hub = _Hub();
    final api = _Api();
    final ride = _Ride();
    var sounds = 0;
    final chat =
        Get.put(ChatController(api, _Session(), ride, hub, playSound: () async {
      sounds++;
    }));
    await tester.pumpAndSettle();
    chat.setPageVisible(true);
    chat.didChangeAppLifecycleState(AppLifecycleState.paused);
    api.rows = [_message(1, 'background')];
    hub.messages
        .add(TrackingHubEvent('rideMessageCreated', _message(1, 'background')));
    await tester.pumpAndSettle();
    expect(api.acknowledgments.single['markRead'], isFalse);
    expect(chat.messages.single.deliveredAtUtc, isNotNull);
    expect(sounds, 0);
    expect(chat.unreadCount.value, 1);
    chat.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(chat.unreadCount.value, 0);
    expect(sounds, 0);
    ride.chatRideId.value = null;
    await tester.pumpAndSettle();
    expect(chat.messages, isEmpty);
    expect(chat.unreadCount.value, 0);
    Get.delete<ChatController>(force: true);
    hub.stateChanges.dispose();
    await hub.messages.close();
    Get.reset();
  });
}
