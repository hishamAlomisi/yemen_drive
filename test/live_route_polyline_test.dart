import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as maps;

import 'package:yemen_drive/shared/widgets/live_route_polyline.dart';

class _CountingPoints extends ListBase<LatLng> {
  _CountingPoints(int count)
      : _points = List.generate(
          count,
          (index) => LatLng(15.36 + index * .000001, 44.19),
        );

  final List<LatLng> _points;
  int reads = 0;

  @override
  int get length => _points.length;

  @override
  set length(int value) => throw UnsupportedError('read only');

  @override
  LatLng operator [](int index) {
    reads++;
    return _points[index];
  }

  @override
  void operator []=(int index, LatLng value) =>
      throw UnsupportedError('read only');
}

/// Executes the plugin's polyline diff and its stored-snapshot clone each frame.
({Duration elapsed, int vertexReads}) _diffFrames(
  Polyline route,
  _CountingPoints source,
) {
  var previous = <Polyline>{route.clone()};
  source.reads = 0;
  final clock = Stopwatch()..start();
  var changedFrames = 0;
  for (var frame = 0; frame < 120; frame++) {
    final diff = maps.PolylineUpdates.from(previous, <Polyline>{route});
    if (diff.polylinesToChange.isNotEmpty ||
        diff.polylinesToAdd.isNotEmpty ||
        diff.polylineIdsToRemove.isNotEmpty) {
      changedFrames++;
    }
    previous = <Polyline>{route.clone()};
  }
  clock.stop();
  expect(changedFrames, 0);
  return (elapsed: clock.elapsed, vertexReads: source.reads);
}

void main() {
  test('route freezes its inputs and preserves styling, JSON and taps', () {
    final points = <LatLng>[const LatLng(15, 44), const LatLng(15.1, 44.1)];
    final patterns = <PatternItem>[PatternItem.dash(8), PatternItem.gap(4)];
    var taps = 0;
    final original = Polyline(
      polylineId: const PolylineId('route'),
      points: points,
      patterns: patterns,
      color: Colors.blue,
      width: 6,
      zIndex: 2,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
      consumeTapEvents: true,
      onTap: () => taps++,
    );
    final frozen = LiveRoutePolyline.from(original);
    expect(frozen.toJson(), original.toJson());
    expect(identical(frozen.clone(), frozen), isTrue);
    points[0] = const LatLng(10, 40);
    patterns.clear();
    expect(frozen.points.first, const LatLng(15, 44));
    expect(frozen.patterns, hasLength(2));
    expect(() => frozen.points.clear(), throwsUnsupportedError);
    expect(() => frozen.patterns.clear(), throwsUnsupportedError);
    frozen.onTap!();
    expect(taps, 1);
    final restyled = frozen.copyWith(colorParam: Colors.red, widthParam: 4);
    expect(restyled, isA<LiveRoutePolyline>());
    expect(restyled.color, Colors.red);
    expect(restyled.width, 4);
    expect(restyled.points, frozen.points);
    expect(restyled.patterns, frozen.patterns);
    expect(restyled.startCap, Cap.roundCap);
    expect(restyled.consumeTapEvents, isTrue);
    expect(restyled.onTap, original.onTap);
  });

  for (final count in <int>[3000, 10000]) {
    test('plugin diff avoids vertex copies for $count-point marker frames', () {
      final source = _CountingPoints(count);
      final ordinary = Polyline(
        polylineId: const PolylineId('route'),
        points: source,
      );
      final normal = _diffFrames(ordinary, source);
      final frozen = LiveRoutePolyline.from(ordinary);
      final optimized = _diffFrames(frozen, source);
      // Each ordinary frame clones the current vertices for the diff and again
      // for the plugin's stored snapshot. The frozen route shares both safely.
      expect(normal.vertexReads, greaterThanOrEqualTo(count * 120 * 2));
      expect(optimized.vertexReads, 0);
      debugPrint(
        '$count vertices / 120 plugin diffs: ordinary '
        '${normal.elapsed.inMicroseconds}us, frozen '
        '${optimized.elapsed.inMicroseconds}us; input vertex reads '
        '${normal.vertexReads} -> ${optimized.vertexReads}',
      );
    });
  }

  test('plugin diff detects same-length reroutes, restyling and removal', () {
    final route = LiveRoutePolyline(
      polylineId: const PolylineId('route'),
      points: List.generate(
        3000,
        (index) => LatLng(15.36 + index * .000001, 44.19),
      ),
      color: Colors.blue,
      width: 6,
    );
    final rerouted = route.copyWith(
      pointsParam: List.generate(
        3000,
        (index) => LatLng(15.36 + index * .000001, 44.1901),
      ),
    );
    final rerouteDiff = maps.PolylineUpdates.from({route}, {rerouted});
    expect(rerouteDiff.polylinesToChange, {rerouted});
    expect(rerouteDiff.polylinesToAdd, isEmpty);
    expect(rerouteDiff.polylineIdsToRemove, isEmpty);
    expect(rerouted.points.last.longitude, 44.1901);
    final restyled = rerouted.copyWith(colorParam: Colors.red);
    expect(
      maps.PolylineUpdates.from({rerouted}, {restyled}).polylinesToChange,
      {restyled},
    );
    expect(
      maps.PolylineUpdates.from({restyled}, {}).polylineIdsToRemove,
      {const PolylineId('route')},
    );
  });
}
