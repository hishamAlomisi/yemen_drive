import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/core/realtime/realtime_state_binding.dart';
import 'package:yemen_drive/core/realtime/tracking_hub_service.dart';
import 'package:yemen_drive/core/storage/secure_storage_service.dart';

class _Hub extends TrackingHubService {
  _Hub() : super(SecureStorageService());
  final packets = StreamController<TrackingHubEvent>.broadcast();
  final restores = StreamController<void>.broadcast();
  @override
  Stream<TrackingHubEvent> get events => packets.stream;
  @override
  Stream<void> get connectionRestored => restores.stream;
  @override
  Future<void> setUserEventListening(Object owner, bool listen) async {}
  void emit(String name, [int rideId = 7]) =>
      packets.add(TrackingHubEvent(name, {'rideId': rideId}));
  @override
  void onClose() {
    unawaited(packets.close());
    unawaited(restores.close());
    super.onClose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);
  test(
      'GPS does not reload business state and event bursts retain one follow-up',
      () {
    fakeAsync((clock) {
      final hub = Get.put<TrackingHubService>(_Hub()) as _Hub;
      final pending = Completer<void>();
      var reads = 0;
      final binding = RealtimeStateBinding(
          owner: Object(),
          resources: {'ride'},
          accepts: (change) => change.resourceId == 7,
          refresh: () {
            reads++;
            return reads == 1 ? pending.future : Future.value();
          });
      for (var i = 0; i < 100; i++) {
        hub.emit('driverLocationUpdated');
        hub.emit('rideStatusUpdated', 9);
      }
      clock.elapse(const Duration(seconds: 1));
      expect(reads, 0);
      for (var i = 0; i < 100; i++) {
        hub.emit('rideStatusUpdated');
      }
      clock.elapse(const Duration(milliseconds: 110));
      expect(reads, 1);
      final epoch = binding.epoch;
      for (var i = 0; i < 100; i++) {
        hub.emit('rideRouteChangeUpdated');
      }
      clock.elapse(const Duration(milliseconds: 110));
      expect(reads, 1);
      expect(
          () => binding.verify(epoch), throwsA(isA<StateSnapshotSuperseded>()));
      pending.complete();
      clock.elapse(const Duration(milliseconds: 110));
      expect(reads, 2);
      hub.emit('rideStatusUpdated');
      clock.flushMicrotasks();
      binding.dispose();
      clock.elapse(const Duration(seconds: 3));
      expect(reads, 2);
    });
  });
  test('legacy reconnect refreshes once while durable events keep their owner',
      () {
    fakeAsync((clock) {
      final hub = Get.put<TrackingHubService>(_Hub()) as _Hub;
      var reads = 0;
      final binding = RealtimeStateBinding(
          owner: Object(),
          resources: {'ride'},
          accepts: (_) => true,
          refresh: () async {
            reads++;
          });
      hub.restores.add(null);
      hub.restores.add(null);
      clock.elapse(const Duration(milliseconds: 110));
      expect(reads, 1);
      hub.supportsStateRecovery.value = true;
      hub.emit('rideStatusUpdated');
      hub.restores.add(null);
      clock.elapse(const Duration(seconds: 1));
      expect(reads, 1);
      binding.dispose();
    });
  });
}
