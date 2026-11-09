import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_drive/core/realtime/state_change_coordinator.dart';

void main() {
  test(
      'screen reads overlap and a slow or failed owner prevents acknowledgement',
      () async {
    final feed = StateChangeCoordinator();
    addTearDown(feed.dispose);
    final first = Completer<void>(), second = Completer<void>();
    final started = <String>[];
    feed.register('ride-panel', (_) {
      started.add('ride');
      return first.future;
    });
    feed.register('payment-panel', (_) {
      started.add('payment');
      return second.future;
    });
    final recovery = feed.recover((_, __) async => {
          'supported': true,
          'hasMore': false,
          'events': [
            {
              'stream': 'ride:7',
              'resource': 'ride',
              'resourceId': 7,
              'version': 1
            }
          ],
        });
    final result = expectLater(recovery, throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(started, ['ride', 'payment']);
    first.completeError(StateError('first read failed'));
    await Future<void>.delayed(Duration.zero);
    expect(feed.versions, isEmpty);
    expect(feed.synchronized, isFalse);
    second.complete();
    await result;
    expect(feed.versions, isEmpty);
    feed.unregister('ride-panel');
    await feed.recover((_, __) async => {
          'supported': true,
          'hasMore': false,
          'events': [
            {
              'stream': 'ride:7',
              'resource': 'ride',
              'resourceId': 7,
              'version': 1
            }
          ],
        });
    expect(feed.versions['ride:7'], 1);
  });

  test('scoped reads survive unrelated events but not relevant events or reset',
      () async {
    final feed = StateChangeCoordinator();
    addTearDown(feed.dispose);
    const resources = {'ride', 'wallet', 'account'};
    final walletRead = feed.epochForResources(resources);
    feed.observe(const StateChange('messages:7', 1, 'messages', 7));
    feed.observe(const StateChange('notifications:3', 1, 'notifications', 3));
    expect(feed.epochForResources(resources), walletRead);
    feed.observe(const StateChange('wallet:3', 1, 'wallet', 3));
    expect(feed.epochForResources(resources), greaterThan(walletRead));
    final afterWallet = feed.epochForResources(resources);
    feed.observe(const StateChange('wallet:3', 1, 'wallet', 3));
    expect(feed.epochForResources(resources), afterWallet);
    feed.disconnected();
    expect(feed.epochForResources(resources), greaterThan(afterWallet));
    final afterDisconnect = feed.epochForResources(resources);
    feed.reset();
    expect(feed.epochForResources(resources), greaterThan(afterDisconnect));
    expect(feed.epochForResources(const {'catalog'}),
        feed.epochForResources(resources));
  });

  test('malformed replay entry cannot be silently skipped as synchronized',
      () async {
    final feed = StateChangeCoordinator();
    addTearDown(feed.dispose);
    await expectLater(
        feed.recover((_, __) async => {
              'supported': true,
              'hasMore': false,
              'events': [null]
            }),
        throwsFormatException);
    expect(feed.synchronized, isFalse);
  });
  test('unknown state schema cannot be treated as applied', () async {
    expect(
        StateChange.parse({
          'stream': 'ride:7',
          'resource': 'ride',
          'resourceId': 7,
          'version': 1,
          'schemaVersion': 2
        }),
        isNull);
    final feed = StateChangeCoordinator();
    addTearDown(feed.dispose);
    await expectLater(
        feed.recover((_, __) async => {
              'supported': true,
              'hasMore': false,
              'events': [
                {
                  'stream': 'ride:7',
                  'resource': 'ride',
                  'resourceId': 7,
                  'version': 1,
                  'schemaVersion': 2
                }
              ]
            }),
        throwsFormatException);
    expect(feed.versions, isEmpty);
    expect(feed.synchronized, isFalse);
  });
  test('replay cursor covers more than the bounded version cache', () async {
    final feed = StateChangeCoordinator();
    addTearDown(feed.dispose);
    final refreshed = <int>{};
    feed.register('rides', (changes) async {
      refreshed.addAll(changes.map((c) => c.resourceId));
    });
    await feed.recover((versions, afterStream) async {
      expect(versions.length, lessThanOrEqualTo(512));
      final start = afterStream == null ? 1 : int.parse(afterStream) + 1;
      final end = start + 127 < 600 ? start + 127 : 600;
      return {
        'supported': true,
        'hasMore': end < 600,
        'nextStream': '$end',
        'events': [
          for (var i = start; i <= end; i++)
            {
              'stream': 'ride:$i',
              'resource': 'ride',
              'resourceId': i,
              'version': 1
            }
        ]
      };
    });
    expect(refreshed.length, 600);
    expect(feed.versions.length, 512);
    expect(feed.synchronized, isTrue);
  });
  StateChange change(int version) => StateChange('ride:7', version, 'ride', 7);
  Map<Object?, Object?> page(List<int> versions) => {
        'supported': true,
        'hasMore': false,
        'events': [
          for (final v in versions)
            {
              'stream': 'ride:7',
              'version': v,
              'resource': 'ride',
              'resourceId': 7
            }
        ]
      };
  test(
      'coalesces duplicates and old events only after canonical refresh finishes',
      () async {
    final feed = StateChangeCoordinator();
    addTearDown(feed.dispose);
    var calls = 0;
    final release = Completer<void>();
    feed.register('trip', (_) async {
      calls++;
      await release.future;
    });
    final recovering = feed.recover((_, __) async => page([1, 2, 1]));
    await Future<void>.delayed(Duration.zero);
    expect(feed.versions, isEmpty);
    expect(feed.synchronized, isFalse);
    release.complete();
    await recovering;
    expect(calls, 1);
    expect(feed.versions['ride:7'], 2);
    expect(feed.synchronized, isTrue);
    feed.observe(change(1));
    await feed.flush();
    expect(calls, 1);
  });
  test('a later event during a snapshot is retained and reconciled again',
      () async {
    final feed = StateChangeCoordinator();
    addTearDown(feed.dispose);
    final release = Completer<void>();
    final started = Completer<void>();
    var calls = 0;
    feed.register('trip', (_) async {
      calls++;
      if (calls == 1) {
        started.complete();
        await release.future;
      }
    });
    final recovering = feed.recover((_, __) async => page([1]));
    await started.future;
    final earlierEpoch = feed.epoch;
    feed.observe(change(2));
    expect(feed.epoch, greaterThan(earlierEpoch));
    release.complete();
    await recovering;
    expect(calls, 2);
    expect(feed.versions['ride:7'], 2);
  });
  test(
      'failed owner is not acknowledged and reconnect retries the same version',
      () async {
    final feed = StateChangeCoordinator();
    addTearDown(feed.dispose);
    var fails = true;
    feed.register('wallet', (_) async {
      if (fails) throw StateError('offline');
    });
    await expectLater(
        feed.recover((_, __) async => page([3])), throwsStateError);
    expect(feed.versions, isEmpty);
    expect(feed.synchronized, isFalse);
    feed.disconnected();
    fails = false;
    await feed.recover((known, _) async {
      expect(known, isEmpty);
      return page([3]);
    });
    expect(feed.versions['ride:7'], 3);
    expect(feed.synchronized, isTrue);
  });
  test('disconnect invalidates old snapshots and reset separates user accounts',
      () async {
    final feed = StateChangeCoordinator();
    addTearDown(feed.dispose);
    final release = Completer<Map<Object?, Object?>>();
    final recovering = feed.recover((_, __) => release.future);
    final epoch = feed.epoch;
    feed.disconnected();
    release.complete(page([4]));
    await recovering;
    expect(feed.epoch, greaterThan(epoch));
    expect(feed.versions, isEmpty);
    await feed.recover((_, __) async => page([5]));
    feed.reset();
    expect(feed.versions, isEmpty);
    expect(feed.synchronized, isFalse);
  });
  test(
      'reconnect during an owner refresh reconciles without acknowledging the old result',
      () async {
    final feed = StateChangeCoordinator();
    addTearDown(feed.dispose);
    final started = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    feed.register('trip', (_) async {
      calls++;
      if (calls == 1) {
        started.complete();
        await release.future;
      }
    });
    final first = feed.recover((_, __) async => page([1]));
    await started.future;
    feed.disconnected();
    final second = feed.recover((_, __) async => page([2]));
    release.complete();
    await Future.wait([first, second]);
    expect(calls, 2);
    expect(feed.versions['ride:7'], 2);
    expect(feed.synchronized, isTrue);
  });
  test('an unsupported older server does not report synchronized', () async {
    final feed = StateChangeCoordinator();
    addTearDown(feed.dispose);
    await expectLater(
        feed.recover((_, __) async => {'supported': false}), throwsStateError);
    expect(feed.synchronized, isFalse);
    expect(feed.versions, isEmpty);
  });
}
