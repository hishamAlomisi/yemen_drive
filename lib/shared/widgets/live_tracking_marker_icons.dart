import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Supplied north-facing vehicles keep their arrow and passenger badge inside
/// one rotating bitmap. The halo belongs to that same marker.
abstract final class LiveTrackingMarkerIcons {
  static const vehicleSize = 46.0;
  static const stopAnchor = ui.Offset(.5, .90);
  static const _ratio = 3.0;
  static final _vehicles = <(bool, int), Future<BitmapDescriptor>>{};
  static final _stops = <String, Future<BitmapDescriptor>>{};

  static Future<BitmapDescriptor> build({
    required bool inProgress,
    double? devicePixelRatio,
  }) {
    final dispatcher = ui.PlatformDispatcher.instance;
    final ratio = devicePixelRatio ??
        dispatcher.implicitView?.devicePixelRatio ??
        (dispatcher.views.isEmpty
            ? 1.0
            : dispatcher.views.first.devicePixelRatio);
    final safeRatio = ratio.isFinite && ratio > 0 ? ratio : 1.0;
    // Android's marker width conversion truncates logical pixels * density.
    // Match it so a normal-density screen needs no further native resizing.
    final pixels = (vehicleSize * safeRatio.clamp(1.0, 4.0)).floor();
    return _vehicles.putIfAbsent(
      (inProgress, pixels),
      () => _renderVehicle(inProgress, pixels),
    );
  }

  static Future<BitmapDescriptor> _renderVehicle(
    bool inProgress,
    int pixels,
  ) async {
    final asset = inProgress ? 'vehicle-trip.png' : 'vehicle-pickup.png';
    final data = await rootBundle.load('assets/images/map/$asset');
    // Moving a marker makes the native plugin decode its icon again. Rasterize
    // once at the display size instead of retransmitting and decoding 384px.
    final codec = await ui.instantiateImageCodec(
      Uint8List.sublistView(data),
      targetWidth: pixels,
      targetHeight: pixels,
      allowUpscaling: false,
    );
    ui.Image? image;
    try {
      image = (await codec.getNextFrame()).image;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('Unable to render vehicle marker');
      return BitmapDescriptor.bytes(
        Uint8List.sublistView(png),
        imagePixelRatio: image.width / vehicleSize,
        width: vehicleSize,
        height: vehicleSize,
      );
    } finally {
      image?.dispose();
      codec.dispose();
    }
  }

  /// The label stays over the coordinate as the map moves or tilts.
  static Future<BitmapDescriptor> buildStop({
    required bool destination,
    required String label,
  }) {
    final normalized = label.trim().replaceAll(RegExp(r'\s+'), ' ');
    final text = normalized.isEmpty
        ? (destination ? 'الوجهة' : 'نقطة الانطلاق')
        : normalized;
    final key = '${destination ? 1 : 0}:$text';
    if (_stops.length > 80) _stops.clear();
    return _stops.putIfAbsent(key, () => _renderStop(destination, text));
  }

  static Future<BitmapDescriptor> _renderStop(
      bool destination, String label) async {
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: ui.TextDirection.rtl,
      textAlign: ui.TextAlign.center,
      fontFamily: 'BeINArabic',
      fontSize: 13,
      fontWeight: ui.FontWeight.w600,
      maxLines: 1,
      ellipsis: '…',
    ))
      ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF16233E)))
      ..addText(label);
    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 160));
    final pillWidth = (paragraph.longestLine + 24).clamp(66.0, 184.0);
    final width = pillWidth + 12;
    const height = 100.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(_ratio);
    final pill = ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(6, 3, pillWidth, 27), const ui.Radius.circular(14));
    final pillPath = ui.Path()..addRRect(pill);
    canvas.drawShadow(pillPath, const ui.Color(0x55142A4C), 4, false);
    canvas.drawRRect(pill, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    canvas.drawPath(
        ui.Path()
          ..moveTo(width / 2 - 5, 29)
          ..lineTo(width / 2, 35)
          ..lineTo(width / 2 + 5, 29)
          ..close(),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    paragraph.layout(ui.ParagraphConstraints(width: pillWidth - 12));
    canvas.drawParagraph(
        paragraph, ui.Offset(12, 3 + (27 - paragraph.height) / 2));
    final asset = destination ? 'destination-pin.png' : 'pickup-pin.png';
    final data = await rootBundle.load('assets/images/map/$asset');
    final codec = await ui.instantiateImageCodec(Uint8List.sublistView(data));
    final frame = await codec.getNextFrame();
    canvas.drawImageRect(
      frame.image,
      ui.Rect.fromLTWH(
          0, 0, frame.image.width.toDouble(), frame.image.height.toDouble()),
      ui.Rect.fromLTWH((width - 56) / 2, 37, 56, 63),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    frame.image.dispose();
    codec.dispose();
    paragraph.dispose();
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
        (width * _ratio).ceil(), (height * _ratio).round());
    picture.dispose();
    final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    if (png == null) throw StateError('Unable to render stop marker');
    return BitmapDescriptor.bytes(Uint8List.sublistView(png),
        imagePixelRatio: _ratio, width: width, height: height);
  }
}
