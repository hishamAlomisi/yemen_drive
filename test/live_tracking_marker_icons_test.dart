import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:yemen_drive/shared/widgets/live_tracking_marker_icons.dart';

Future<Size> _decodeSize(BytesMapBitmap descriptor) async {
  final codec = await ui.instantiateImageCodec(descriptor.byteData);
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    return Size(image.width.toDouble(), image.height.toDouble());
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

void main() {
  testWidgets('vehicle PNGs fit the screen density and keep their logical size',
      (tester) async {
    await tester.runAsync(() async {
      for (final inProgress in <bool>[false, true]) {
        final asset = inProgress ? 'vehicle-trip.png' : 'vehicle-pickup.png';
        final original = await rootBundle.load('assets/images/map/$asset');
        for (final ratio in <double>[1, 2, 2.625, 3, 4, 8]) {
          final descriptor = await LiveTrackingMarkerIcons.build(
            inProgress: inProgress,
            devicePixelRatio: ratio,
          ) as BytesMapBitmap;
          final pixels = (46 * ratio.clamp(1.0, 4.0)).floor();
          expect(await _decodeSize(descriptor), Size.square(pixels.toDouble()));
          expect(descriptor.imagePixelRatio, pixels / 46);
          expect(descriptor.width, 46);
          expect(descriptor.height, 46);
          expect(
            descriptor.byteData.take(8),
            <int>[137, 80, 78, 71, 13, 10, 26, 10],
          );
          expect(descriptor.byteData.length, lessThan(original.lengthInBytes));
          if (ratio == 3) {
            expect(
              descriptor.byteData.length,
              lessThan(original.lengthInBytes * .5),
            );
            debugPrint('$asset at 3x: ${original.lengthInBytes} bytes / 384px '
                '-> ${descriptor.byteData.length} bytes / ${pixels}px');
          }
        }
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('phase and physical pixel size cache the same rasterization',
      (tester) async {
    await tester.runAsync(() async {
      final first = LiveTrackingMarkerIcons.build(
        inProgress: true,
        devicePixelRatio: 3,
      );
      final samePixels = LiveTrackingMarkerIcons.build(
        inProgress: true,
        devicePixelRatio: 3.001,
      );
      expect(identical(first, samePixels), isTrue);
      expect(identical(await first, await samePixels), isTrue);
      final otherPhase = await LiveTrackingMarkerIcons.build(
        inProgress: false,
        devicePixelRatio: 3,
      );
      expect(identical(await first, otherPhase), isFalse);
      final otherDensity = await LiveTrackingMarkerIcons.build(
        inProgress: true,
        devicePixelRatio: 2,
      );
      expect(identical(await first, otherDensity), isFalse);
    });
  });

  testWidgets('invalid ratios use a bounded valid PNG and default view works',
      (tester) async {
    await tester.runAsync(() async {
      for (final ratio in <double>[0, -1, double.nan, double.infinity]) {
        final descriptor = await LiveTrackingMarkerIcons.build(
          inProgress: true,
          devicePixelRatio: ratio,
        ) as BytesMapBitmap;
        expect(await _decodeSize(descriptor), const Size.square(46));
        expect(descriptor.imagePixelRatio, 1);
      }
      final automatic = await LiveTrackingMarkerIcons.build(inProgress: true)
          as BytesMapBitmap;
      final size = await _decodeSize(automatic);
      expect(size.width, inInclusiveRange(46, 184));
      expect(size.height, size.width);
      expect(automatic.imagePixelRatio, size.width / 46);
    });
  });
}
