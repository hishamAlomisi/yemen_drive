// Diagnostic entry point only. It does not run in the normal application.
// Build with flutter build apk --profile --target tool/performance_probe.dart
// --target-platform android-x64 --split-per-abi, install, and exercise the UI.
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:yemen_drive/main.dart' as application;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final frames = <FrameTiming>[];
  void collect(List<FrameTiming> timings) => frames.addAll(timings);
  // Exclude startup and renderer warmup from the interactive sample.
  Timer(const Duration(seconds: 12), () {
    WidgetsBinding.instance.addTimingsCallback(collect);
    debugPrint('RIDER_PERFORMANCE_BEGIN');
    Timer(const Duration(seconds: 30), () {
      WidgetsBinding.instance.removeTimingsCallback(collect);
      Map<String, Object> summarize(List<double> values) {
        if (values.isEmpty) return {'frames': 0};
        values.sort();
        double percentile(double p) =>
            values[((values.length - 1) * p).round()];
        return {
          'frames': values.length,
          'p50_ms': percentile(.50),
          'p90_ms': percentile(.90),
          'p99_ms': percentile(.99),
          'over_16_67ms': values.where((x) => x > 16.67).length,
        };
      }

      debugPrint('RIDER_PERFORMANCE_RESULT ${jsonEncode({
            'mode': kProfileMode ? 'profile' : 'other',
            'build': summarize(frames
                .map((x) => x.buildDuration.inMicroseconds / 1000)
                .toList()),
            'raster': summarize(frames
                .map((x) => x.rasterDuration.inMicroseconds / 1000)
                .toList()),
          })}');
    });
  });
  await application.main();
}
