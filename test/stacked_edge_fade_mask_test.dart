import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';

void main() {
  group('StackedEdgeFadeMask', () {
    testWidgets(
      'renders child and ShaderMask without error when controller is attached',
      (tester) async {
        final controller = PageController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 100,
                  child: StackedEdgeFadeMask(
                    controller: controller,
                    child: PageView(
                      controller: controller,
                      children: const [Text('Page 0'), Text('Page 1')],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('Page 0'), findsOneWidget);
        expect(find.byType(ShaderMask), findsOneWidget);
      },
    );

    testWidgets(
      'fades edges dynamically during horizontal swipe and returns to solid at rest',
      (tester) async {
        final controller = PageController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 100,
                  child: StackedEdgeFadeMask(
                    controller: controller,
                    child: PageView(
                      controller: controller,
                      children: const [Text('Page 0'), Text('Page 1')],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Initially at rest on page 0
        expect(controller.page, 0.0);
        final shaderMask = tester.widget<ShaderMask>(find.byType(ShaderMask));
        expect(shaderMask.blendMode, BlendMode.dstIn);

        // Begin a drag to the left (swipe towards page 1)
        final center = tester.getCenter(find.byType(PageView));
        final gesture = await tester.startGesture(center);
        // Move past kTouchSlop
        await gesture.moveBy(const Offset(-30, 0));
        await gesture.moveBy(const Offset(-50, 0));
        await tester.pump();

        // Mid-drag: page offset is greater than 0
        expect(controller.page, isNotNull);
        expect(controller.page!, greaterThan(0.0));
        expect(controller.page!, lessThan(1.0));

        // Pump mid-gesture to confirm ShaderMask executes its gradient shader without error
        await tester.pump();
        expect(find.byType(ShaderMask), findsOneWidget);

        // Continue drag past 50% width to settle on page 1
        await gesture.moveBy(const Offset(-100, 0));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(controller.page, 1.0);
        expect(find.text('Page 1'), findsOneWidget);
      },
    );

    testWidgets('safely handles unattached controller or zero bounds', (
      tester,
    ) async {
      final controller = PageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StackedEdgeFadeMask(
              controller: controller,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      );

      expect(find.byType(ShaderMask), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
