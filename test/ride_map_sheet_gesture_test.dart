import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:yemen_drive/features/ride/widgets/ride_map_shell.dart';

void main() {
  testWidgets('collapsed trip sheet follows one drag across live updates',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final liveUpdate = ValueNotifier(0);
    addTearDown(liveUpdate.dispose);
    await tester.pumpWidget(
      GetMaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: liveUpdate,
          builder: (_, update, __) => RideMapShell(
            map: const ColoredBox(color: Color(0xFFE9EEF1)),
            panelMaxHeightFactor: .6,
            panel: SizedBox(height: 180, child: Text('Trip update $update')),
            panelFooter:
                const SizedBox(height: 120, child: Text('Trip actions')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final handle = find.byKey(const ValueKey('ride-panel-drag-handle'));
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    final controller = sheet.controller!;
    await tester.drag(handle, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(sheet.minChildSize, .001));

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, -50));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    expect(controller.size, greaterThan(.2));
    final beforeUpdate = controller.size;
    liveUpdate.value++;
    await tester.pump();
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(controller.size, greaterThan(beforeUpdate + .08));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.size, closeTo(.6, .001));
    expect(find.text('Trip update 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
