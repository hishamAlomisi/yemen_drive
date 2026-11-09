import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:yemen_drive/shared/widgets/live_tracking_marker_icons.dart';

// Visual export tool: used once to inspect the actual PNGs Google Maps receives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export native map marker bitmaps for visual inspection', () async {
    final font = FontLoader('BeINArabic')
      ..addFont(rootBundle.load('assets/fonts/bein_ar_regular.ttf'));
    await font.load();
    final folder = Directory('E:/Driver/work/map-motion-20261106/rendered')
      ..createSync(recursive: true);
    final icons = <String, BitmapDescriptor>{
      'vehicle-pickup': await LiveTrackingMarkerIcons.build(inProgress: false),
      'vehicle-trip': await LiveTrackingMarkerIcons.build(inProgress: true),
      'pickup-rider': await LiveTrackingMarkerIcons.buildStop(
          destination: false, label: 'أحمد'),
      'pickup-driver': await LiveTrackingMarkerIcons.buildStop(
          destination: false, label: 'نقطة الانطلاق'),
      'destination': await LiveTrackingMarkerIcons.buildStop(
          destination: true, label: 'الوجهة'),
    };
    for (final entry in icons.entries) {
      final bitmap = entry.value as BytesMapBitmap;
      await File('${folder.path}/${entry.key}.png').writeAsBytes(bitmap.byteData);
    }
  });
}
