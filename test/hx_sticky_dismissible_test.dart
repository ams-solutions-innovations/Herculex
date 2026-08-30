import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/ui/hx_sticky_dismissible.dart';

void main() {
  testWidgets('HxStickyDismissible renders child and responds to drag gestures',
      (tester) async {
    bool dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 60,
              child: HxStickyDismissible(
                key: const ValueKey('test_dismissible'),
                onDismissed: () => dismissed = true,
                child: Container(
                  color: Colors.blue,
                  child: const Center(child: Text('Swipe Me')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Swipe Me'), findsOneWidget);

    // 1. Partial swipe below threshold -> snaps back, dismissed is false
    await tester.drag(find.text('Swipe Me'), const Offset(-50, 0));
    await tester.pumpAndSettle();
    expect(dismissed, isFalse);
    expect(find.text('Swipe Me'), findsOneWidget);

    // 2. Full swipe past threshold -> dismisses
    await tester.drag(find.text('Swipe Me'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });
}
