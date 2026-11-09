import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/features/ride/models/ride_models.dart';
import 'package:yemen_drive/features/ride/models/route_deviation_status.dart';
import 'package:yemen_drive/features/ride/models/tracked_driver_motion.dart';
import 'package:yemen_drive/features/ride/widgets/ride_map_shell.dart';

void main() {
  DriverTrackingSnapshot sample(double lat, double lng, {double? heading}) =>
      DriverTrackingSnapshot(
        driverId: '7',
        location: RideCoordinate(latitude: lat, longitude: lng),
        updatedAt: DateTime.utc(2026, 11, 5),
        heading: heading,
      );

  test('moving car gets direction from actual travel even with absent bearing',
      () {
    final previous = sample(15.3, 44.2);
    expect(TrackedDriverMotion.heading(previous, sample(15.3, 44.201)),
        closeTo(90, .01));
    expect(TrackedDriverMotion.heading(previous, sample(15.301, 44.2)),
        closeTo(0, .01));
    expect(TrackedDriverMotion.heading(previous, sample(15.3, 44.199)),
        closeTo(270, .01));
  });

  test(
      'stationary GPS jitter preserves heading and interpolation stays low-lag',
      () {
    expect(
        TrackedDriverMotion.heading(
            sample(15.3, 44.2, heading: 270), sample(15.300001, 44.2)),
        270);
    expect(TrackedDriverMotion.duration(const Duration(seconds: 5)),
        const Duration(milliseconds: 650));
    expect(TrackedDriverMotion.duration(const Duration(milliseconds: 200)),
        const Duration(milliseconds: 130));
  });
  test(
      'reliable bearing wins over multi-meter jitter; missing bearing waits for clear displacement',
      () {
    final previous = sample(15.3, 44.2, heading: 270);
    expect(
        TrackedDriverMotion.heading(
            previous, sample(15.30002, 44.2, heading: 270)),
        270);
    expect(
        TrackedDriverMotion.heading(sample(15.3, 44.2, heading: 0),
            sample(15.3, 44.2000093, heading: 90)),
        90);
    expect(TrackedDriverMotion.heading(previous, sample(15.30002, 44.2)), 270);
    expect(TrackedDriverMotion.heading(previous, sample(15.3001, 44.2)),
        closeTo(0, .01));
  });

  RouteDeviationStatus status(
          {bool deviating = true,
          bool available = true,
          String version = '1'}) =>
      RouteDeviationStatus(
          available: available,
          isDeviating: deviating,
          distanceMeters: 24,
          direction: 'شرق',
          routeVersion: version);

  test(
      'safe acknowledgement stays quiet until verified return or approved route change',
      () {
    final policy = RouteDeviationPromptPolicy();
    expect(policy.shouldPrompt('7', status()), isTrue);
    policy.handled();
    expect(policy.shouldPrompt('7', status()), isFalse);
    expect(policy.shouldPrompt('7', status(available: false)), isFalse);
    expect(policy.shouldPrompt('7', status(available: false, version: '')),
        isFalse);
    expect(policy.shouldPrompt('7', status()), isFalse);
    expect(policy.shouldPrompt('7', status(deviating: false)), isFalse);
    expect(policy.shouldPrompt('7', status()), isFalse);
    policy.shouldPrompt('7', status(deviating: false));
    policy.shouldPrompt('7', status(deviating: false));
    expect(policy.shouldPrompt('7', status()), isTrue);
    policy.handled();
    expect(policy.shouldPrompt('7', status(version: '2')), isTrue);
    policy.handled();
    expect(policy.shouldPrompt('8', status(version: '2')), isTrue);
  });

  testWidgets(
      'trip panel collapses to bottom full-width strip and expands by dragging',
      (tester) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GetMaterialApp(
        home: RideMapShell(
      map: ColoredBox(color: Color(0xFFE9EEF1)),
      allowPanelCollapse: true,
      panelMaxHeightFactor: .6,
      panel: SizedBox(height: 180, child: Text('تفاصيل الرحلة')),
      panelFooter: SizedBox(height: 120, child: Text('إجراءات الرحلة')),
    )));
    await tester.pumpAndSettle();
    final handle = find.byKey(const ValueKey('ride-panel-drag-handle'));
    await tester.drag(handle, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل الرحلة'), findsNothing);
    final handleRect = tester.getRect(handle);
    expect(handleRect.bottom, greaterThan(800));
    expect(handleRect.width, 358);
    final panelSurface =
        find.ancestor(of: handle, matching: find.byType(Material)).first;
    expect(tester.getSize(panelSurface).width, 390);
    expect(tester.getSize(panelSurface).height, closeTo(48, 1));
    await expectLater(find.byType(RideMapShell),
        matchesGoldenFile('goldens/trip-panel-collapsed.png'));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل الرحلة'), findsNothing);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, -55));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -25));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.drag(handle, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل الرحلة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
