import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_drive/core/cache/persistent_network_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('cached artwork decodes to the display pixel budget',
      (tester) async {
    const url = 'https://example.invalid/large-artwork.png';
    final directory = Directory('build/image-budget-storage').absolute;
    final key = sha256.convert(utf8.encode(url));
    await tester.runAsync(() async {
      final cache = Directory('${directory.path}/yemen_drive_network_images');
      await cache.create(recursive: true);
      await File('assets/images/branding/rider_splash_logo.png')
          .copy('${cache.path}/$key.image');
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    await tester.runAsync(() => tester.pumpWidget(const MaterialApp(
            home: MediaQuery(
          data: MediaQueryData(devicePixelRatio: 2),
          child:
              Center(child: PersistentNetworkImage(url, width: 60, height: 60)),
        ))));
    await tester.runAsync(() async {
      await PersistentNetworkImageCache.fileFor(url)
          .timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.runAsync(() => tester.pump());
    final image = tester.widget<Image>(find.byType(Image));
    final size = await tester.runAsync(() async {
      final result = Completer<Size>();
      final stream = image.image.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        if (!result.isCompleted)
          result.complete(
              Size(info.image.width.toDouble(), info.image.height.toDouble()));
        info.dispose();
      },
          onError: (Object error, StackTrace? stack) =>
              result.completeError(error, stack));
      stream.addListener(listener);
      try {
        return await result.future.timeout(const Duration(seconds: 5));
      } finally {
        stream.removeListener(listener);
      }
    });
    expect(size!.width, lessThanOrEqualTo(120));
    expect(size.height, lessThanOrEqualTo(120));
    expect(size.longestSide, 120);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
