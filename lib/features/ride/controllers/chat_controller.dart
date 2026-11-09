import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_models.dart';
import '../../../core/realtime/tracking_hub_service.dart';
import '../../../core/services/auth_session_service.dart';
import '../../../core/services/chat_message_sound.dart';
import 'ride_controller.dart';
import '../models/ride_models.dart';

/// Owns messages and the unread badge for the whole active ride. Reads are
/// acknowledged only after the foreground chat page renders the messages.
class ChatController extends GetxController with WidgetsBindingObserver {
  ChatController(this._client, this._session, this._ride, this._hub,
      {Future<void> Function()? playSound})
      : _playSound = playSound ?? playChatMessageSound;

  static const int _pageSize = 50;
  final ApiClient _client;
  final AuthSessionService _session;
  final RideController _ride;
  final TrackingHubService _hub;
  final Future<void> Function() _playSound;
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final RxList<RideChatMessage> messages = <RideChatMessage>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isLoadingOlder = false.obs;
  final RxBool hasOlderMessages = false.obs;
  final RxBool isSending = false.obs;
  final RxInt unreadCount = 0.obs;
  final RxnString error = RxnString();
  StreamSubscription<TrackingHubEvent>? _eventSubscription;
  StreamSubscription<void>? _connectionSubscription;
  Worker? _scopeWorker;
  Future<void>? _loadTask;
  bool _reloadRequested = false;
  int _generation = 0;
  int _localRevision = 0;
  String? _scope;
  bool _initialLoaded = false;
  bool _pageVisible = false;
  bool _foreground = true;
  bool get _canRead => _pageVisible && _foreground;
  final Map<int, bool> _pendingAcks = {};
  final Map<int, int> _outgoingEchoes = {};
  Future<void>? _ackTask;
  Timer? _ackRetry;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _scopeWorker = everAll([
      _ride.chatRideId,
      _session.currentUserId,
      _session.isAuthenticated,
    ], (_) => _scopeChanged());
    _hub.stateChanges.register(this, (changes) async {
      if (changes.any((change) =>
          change.resource == 'messages' &&
          '${change.resourceId}' == _ride.currentRideId)) {
        await loadMessages(requireSuccess: true);
      }
    });
    _eventSubscription = _hub.events.listen(_handleHubEvent);
    _connectionSubscription = _hub.connectionRestored.listen((_) {
      unawaited(loadMessages());
      _flushAcknowledgments();
    });
    _scopeChanged();
  }

  void _scopeChanged() {
    final scope = _session.isAuthenticated.value
        ? '${_session.currentUserId.value}:${_ride.currentRideId}'
        : null;
    if (_scope != scope) {
      _scope = scope;
      _generation++;
      _localRevision++;
      messages.clear();
      unreadCount.value = 0;
      isSending.value = false;
      hasOlderMessages.value = false;
      _initialLoaded = false;
      _pendingAcks.clear();
      _outgoingEchoes.clear();
      _ackRetry?.cancel();
      messageController.clear();
    }
    if (_session.isAuthenticated.value) {
      unawaited(_hub.setUserEventListening(this, true));
      unawaited(loadMessages());
    } else {
      unawaited(_hub.setUserEventListening(this, false));
    }
  }

  void setPageVisible(bool visible) {
    _pageVisible = visible;
    if (_canRead) {
      unawaited(loadMessages());
      _acknowledgeRenderedMessages();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(loadMessages());
      _acknowledgeRenderedMessages();
      _flushAcknowledgments();
    }
  }

  Future<void> loadMessages({bool requireSuccess = false}) async {
    _reloadRequested = true;
    try {
      var task = _loadTask;
      if (task == null) {
        task = _loadLatest();
        _loadTask = task;
      }
      try {
        await task;
      } finally {
        if (identical(_loadTask, task)) _loadTask = null;
      }
    } catch (_) {
      if (!isClosed)
        error.value = 'تعذر تحديث المحادثة. تحقق من الاتصال وحاول مجدداً.';
      if (requireSuccess) rethrow;
    }
  }

  Future<void> _loadLatest() async {
    do {
      _reloadRequested = false;
      final rideId = int.tryParse(_ride.currentRideId ?? '');
      if (rideId == null || !_session.isAuthenticated.value || isClosed) return;
      final generation = _generation;
      final revision = _localRevision;
      final epoch = _hub.stateChanges.epochForResources(const {'messages'});
      if (messages.isEmpty) isLoading.value = true;
      try {
        final result = await _client.execute<Object?>(
          model: 'RideMessageModel',
          operation: 'list',
          data: {'rideId': rideId, 'pageSize': _pageSize},
        );
        if (isClosed || generation != _generation) continue;
        if (result is! ApiSuccess || result.data is! List)
          throw StateError('Chat recovery failed');
        final page = _parseRows(result.data);
        if (!_initialLoaded) hasOlderMessages.value = page.length == _pageSize;
        _upsertMessages(page,
            announce: _initialLoaded,
            scrollToBottom: messages.isEmpty || _isAtBottom);
        _initialLoaded = true;
        _queueDelivery(page);
        final summary = await _client.execute<Object?>(
          model: 'RideMessageModel',
          operation: 'report',
          data: {'rideId': rideId},
        );
        if (isClosed || generation != _generation) continue;
        if (summary is! ApiSuccess || summary.data is! Map) {
          throw StateError('Unread summary recovery failed');
        }
        if (revision == _localRevision &&
            epoch == _hub.stateChanges.epochForResources(const {'messages'})) {
          unreadCount.value =
              int.tryParse('${(summary.data as Map)['unreadCount']}') ??
                  unreadCount.value;
        }
        if (epoch != _hub.stateChanges.epochForResources(const {'messages'}) ||
            revision != _localRevision) _reloadRequested = true;
        error.value = null;
        _acknowledgeRenderedMessages();
      } catch (_) {
        if (isClosed || generation != _generation) continue;
        rethrow;
      } finally {
        isLoading.value = false;
      }
    } while (_reloadRequested && !isClosed);
  }

  List<RideChatMessage> _parseRows(Object? rows) => rows is List
      ? rows
          .whereType<Map<Object?, Object?>>()
          .map((row) => _parseMessage(Map<Object?, Object?>.from(row)))
          .whereType<RideChatMessage>()
          .toList(growable: false)
      : <RideChatMessage>[];

  Future<void> loadOlderMessages() async {
    final rideId = int.tryParse(_ride.currentRideId ?? '');
    if (rideId == null || messages.isEmpty || isLoadingOlder.value) return;
    final oldest = messages.first;
    final generation = _generation;
    isLoadingOlder.value = true;
    try {
      final result = await _client.execute<Object?>(
        model: 'RideMessageModel',
        operation: 'list',
        data: {
          'rideId': rideId,
          'pageSize': _pageSize,
          'beforeId': oldest.id,
          'beforeCreatedAtUtc': oldest.createdAtUtc,
        },
      );
      if (isClosed || generation != _generation) return;
      if (result is! ApiSuccess || result.data is! List) return;
      final page = _parseRows(result.data);
      _upsertMessages(page);
      _queueDelivery(page);
      hasOlderMessages.value = page.length == _pageSize;
      _acknowledgeRenderedMessages();
    } catch (_) {
      if (!isClosed && generation == _generation)
        error.value = 'تعذر تحميل رسائل أقدم.';
    } finally {
      isLoadingOlder.value = false;
    }
  }

  RideChatMessage? _parseMessage(Map<Object?, Object?> raw) {
    final id = int.tryParse('${raw['id'] ?? ''}');
    final senderId = int.tryParse('${raw['senderId'] ?? ''}');
    final createdAtUtc = raw['createdAtUtc']?.toString();
    final stamp = DateTime.tryParse(createdAtUtc ?? '')?.toLocal();
    if (id == null || senderId == null || stamp == null) return null;
    return RideChatMessage(
      id: id,
      createdAtUtc: createdAtUtc!,
      text: '${raw['content'] ?? ''}',
      timeLabel:
          '${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}',
      isMine: senderId == _session.currentUserId.value,
      deliveredAtUtc: raw['deliveredAtUtc']?.toString(),
      readAtUtc: raw['readAtUtc']?.toString(),
    );
  }

  void _handleHubEvent(TrackingHubEvent event) {
    if (!const {'rideMessageCreated', 'rideMessageUpdated'}
            .contains(event.name) ||
        !_session.isAuthenticated.value ||
        '${event.payload['rideId']}' != _ride.currentRideId) return;
    final userId = _session.currentUserId.value;
    if ('${event.payload['senderId']}' != '$userId' &&
        '${event.payload['recipientId']}' != '$userId') return;
    final message = _parseMessage(Map<Object?, Object?>.from(event.payload));
    if (message == null) {
      unawaited(loadMessages());
      return;
    }
    final existing = messages.any((row) => row.id == message.id);
    if (event.name == 'rideMessageCreated' &&
        message.isMine &&
        isSending.value) {
      for (final row in messages) {
        if (row.isPending && row.text == message.text)
          _outgoingEchoes[row.id] = message.id;
      }
      messages.removeWhere((row) => row.isPending && row.text == message.text);
    }
    _localRevision++;
    // Direct arrival is immediate even while durable recovery is active.
    // Immutable content and monotonic receipts survive stale duplicate events.
    _upsertMessages([message],
        announce: event.name == 'rideMessageCreated',
        scrollToBottom: messages.isEmpty || _isAtBottom);
    if (!existing && !message.isMine && message.readAtUtc == null)
      unreadCount.value++;
    _queueDelivery([message]);
    _acknowledgeRenderedMessages();
    unawaited(loadMessages());
  }

  bool get _isAtBottom =>
      !scrollController.hasClients ||
      scrollController.position.maxScrollExtent -
              scrollController.position.pixels <=
          120;

  void _upsertMessages(Iterable<RideChatMessage> incoming,
      {bool scrollToBottom = false, bool announce = false}) {
    final byId = {for (final message in messages) message.id: message};
    var hasNewInbound = false;
    for (final message in incoming) {
      final old = byId[message.id];
      if (old == null && !message.isMine) hasNewInbound = true;
      byId[message.id] = old?.mergeReceipts(message) ?? message;
    }
    final sorted = byId.values.toList()
      ..sort((a, b) {
        final stamp = DateTime.parse(a.createdAtUtc)
            .compareTo(DateTime.parse(b.createdAtUtc));
        return stamp == 0 ? a.id.compareTo(b.id) : stamp;
      });
    messages.assignAll(sorted);
    if (announce && hasNewInbound && _canRead)
      unawaited(_playSound().catchError((Object _) {}));
    if (scrollToBottom && _pageVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isClosed || !scrollController.hasClients) return;
        scrollController.animateTo(scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      });
    }
  }

  void _queueDelivery(Iterable<RideChatMessage> rows) {
    for (final row in rows) {
      final received =
          messages.firstWhereOrNull((message) => message.id == row.id) ?? row;
      if (!received.isMine &&
          received.deliveredAtUtc == null &&
          received.readAtUtc == null) {
        _pendingAcks.putIfAbsent(row.id, () => false);
      }
    }
    _flushAcknowledgments();
  }

  void _acknowledgeRenderedMessages() {
    if (!_canRead ||
        !messages.any((row) => !row.isMine && row.readAtUtc == null)) return;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isClosed || generation != _generation || !_canRead) return;
      for (final row in messages) {
        if (!row.isMine && row.readAtUtc == null) _pendingAcks[row.id] = true;
      }
      _flushAcknowledgments();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _flushAcknowledgments() {
    if (_ackTask != null || isClosed || _pendingAcks.isEmpty) return;
    late final Future<void> task;
    task = _sendAcknowledgments().whenComplete(() {
      if (identical(_ackTask, task)) _ackTask = null;
      if (_pendingAcks.isNotEmpty && _ackRetry?.isActive != true) {
        scheduleMicrotask(_flushAcknowledgments);
      }
    });
    _ackTask = task;
  }

  Future<void> _sendAcknowledgments() async {
    final generation = _generation;
    final rideId = int.tryParse(_ride.currentRideId ?? '');
    if (rideId == null) return;
    try {
      while (
          _pendingAcks.isNotEmpty && !isClosed && generation == _generation) {
        final read = _canRead && _pendingAcks.values.any((value) => value);
        final ids = _pendingAcks.entries
            .where((e) => !read || e.value)
            .take(100)
            .map((e) => e.key)
            .toList();
        final result = await _client.execute<Object?>(
          model: 'RideMessageModel',
          operation: 'update',
          data: {
            'rideId': rideId,
            'messageIds': ids,
            'markDelivered': true,
            'markRead': read,
          },
        );
        if (isClosed || generation != _generation) return;
        if (result is! ApiSuccess)
          throw StateError('Message acknowledgment failed');
        final rows =
            _parseRows(result.data is Map ? [result.data] : result.data);
        if (rows.isEmpty) throw StateError('Missing acknowledgment receipts');
        if (rows.any((row) => read
            ? row.readAtUtc == null
            : row.deliveredAtUtc == null && row.readAtUtc == null)) {
          throw StateError('Incomplete acknowledgment receipts');
        }
        _upsertMessages(rows);
        for (final row in rows) {
          if (row.readAtUtc != null ||
              (row.deliveredAtUtc != null &&
                  (_pendingAcks[row.id] != true || !_canRead)))
            _pendingAcks.remove(row.id);
        }
        _localRevision++;
      }
      unawaited(loadMessages());
    } catch (_) {
      if (isClosed || generation != _generation) return;
      _ackRetry?.cancel();
      _ackRetry = Timer(const Duration(seconds: 3), _flushAcknowledgments);
    }
  }

  Future<void> sendMessage() async {
    final value = messageController.text.trim();
    if (value.isEmpty || isSending.value) return;
    final rideId = int.tryParse(_ride.currentRideId ?? '');
    if (rideId == null) return;
    final generation = _generation;
    final pendingId = -DateTime.now().microsecondsSinceEpoch;
    final now = DateTime.now();
    isSending.value = true;
    _upsertMessages([
      RideChatMessage(
          id: pendingId,
          createdAtUtc: now.toUtc().toIso8601String(),
          text: value,
          timeLabel:
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
          isMine: true,
          isPending: true)
    ], scrollToBottom: true);
    try {
      final result = await _client.execute<Object?>(
        model: 'RideMessageModel',
        operation: 'add',
        data: {'rideId': rideId, 'content': value},
      );
      if (isClosed || generation != _generation) return;
      if (result is! ApiSuccess || result.data is! Map)
        throw StateError('Send failed');
      final message =
          _parseMessage(Map<Object?, Object?>.from(result.data as Map));
      if (message == null) throw StateError('Incomplete message');
      messages.removeWhere((message) => message.id == pendingId);
      _upsertMessages([message], scrollToBottom: true);
      if (messageController.text.trim() == value) messageController.clear();
      error.value = null;
    } catch (_) {
      if (!isClosed && generation == _generation) {
        if (_outgoingEchoes.containsKey(pendingId)) {
          // The authenticated live echo already proves this message committed,
          // even when the HTTP acknowledgment was lost. Do not invite a resend.
          if (messageController.text.trim() == value) messageController.clear();
          error.value = null;
        } else {
          error.value =
              'تعذر إرسال الرسالة. بقي النص في الحقل لإعادة المحاولة.';
        }
      }
    } finally {
      if (!isClosed && generation == _generation) {
        messages.removeWhere((message) => message.id == pendingId);
        _outgoingEchoes.remove(pendingId);
        isSending.value = false;
      }
    }
  }

  @override
  void onClose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _scopeWorker?.dispose();
    _ackRetry?.cancel();
    _hub.stateChanges.unregister(this);
    unawaited(_hub.setUserEventListening(this, false));
    messageController.dispose();
    scrollController.dispose();
    unawaited(_eventSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    super.onClose();
  }
}
