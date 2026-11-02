import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../lib/core/network/api_client.dart';
import '../lib/core/network/api_models.dart';
import '../lib/core/realtime/tracking_hub_service.dart';
import '../lib/core/services/ride_arrival_notifier.dart';
import '../lib/core/storage/secure_storage_service.dart';

class _Storage implements GetStorage {
  @override
  T? read<T>(String key) => null;
  @override
  Future<void> write(String key, dynamic value) async {}
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
  Future<void> setForeground(bool foreground) async {}
}

class _Sound extends ArrivalSound {
  bool playing = false;
  @override
  Future<void> start() async => playing = true;
  @override
  Future<void> stop() async => playing = false;
}

class _Api extends ApiClient {
  _Api() : super(SecureStorageService());
  Completer<Map<String, Object?>>? pending;
  Map<String, Object?> get alert => {
        'rideId': 7,
        'arrived': true,
        'alertActive': true,
        'alertId': 'arrival-7',
        'driverName': 'أحمد',
        'acknowledged': false,
      };
  @override
  Future<ApiResult<T>> execute<T>(
          {required String model,
          required String operation,
          Object? data,
          T Function(Object?)? parse}) async =>
      ApiSuccess<T>((pending == null ? alert : await pending!.future) as T);
}

void main() {
  for (final driverStarts in [false, true]) {
    testWidgets(
        'arrival sound stops on ${driverStarts ? 'driver start' : 'rider boarding'} and stale fetch cannot restart it',
        (tester) async {
      final hub = _Hub();
      final api = _Api();
      final sound = _Sound();
      await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
      final notifier = Get.put(RideArrivalNotifier(api, hub,
          sound: sound, storage: _Storage(), userId: 1));
      await notifier.refresh(7);
      await tester.pumpAndSettle();
      expect(sound.playing, isTrue);
      expect(find.byKey(const ValueKey('arrival-fullscreen-alert')),
          findsOneWidget);
      final pending = api.pending = Completer<Map<String, Object?>>();
      final refreshing = notifier.refresh(7);
      hub.messages.add(TrackingHubEvent('rideStatusUpdated', {
        'rideId': 7,
        'rideStatus': driverStarts ? 5 : 9,
        'passengerBoardedAtUtc': '2026-11-02T18:00:00Z',
      }));
      await tester.pumpAndSettle();
      expect(sound.playing, isFalse);
      expect(
          find.byKey(const ValueKey('arrival-fullscreen-alert')), findsNothing);
      pending.complete(api.alert);
      await refreshing;
      await tester.pumpAndSettle();
      expect(sound.playing, isFalse);
      expect(notifier.view.value, isNull);
      Get.delete<RideArrivalNotifier>(force: true);
      await tester.pumpWidget(const SizedBox());
      Get.reset();
      await hub.messages.close();
    });
  }
}
