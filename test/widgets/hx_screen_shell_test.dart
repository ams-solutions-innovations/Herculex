import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/theme/app_theme.dart';
import 'package:herculex/ui/ui.dart';

/// The fade-on-scroll header is the shell's whole reason to exist, so its
/// direction handling is pinned down here.
void main() {
  Widget harness({Widget? pinnedBottom, int itemCount = 30}) => MaterialApp(
        theme: AppTheme.darkTheme,
        home: HxScreenShell(
          title: 'Calorie Trends',
          pinnedBottom: pinnedBottom,
          children: [
            for (var i = 0; i < itemCount; i++)
              SizedBox(height: 100, child: Text('item $i')),
          ],
        ),
      );

  /// Opacity the floating header is currently rendered at.
  double headerOpacity(WidgetTester tester) {
    final finder = find
        .ancestor(
          of: find.byType(HxBackButton),
          matching: find.byType(Opacity),
        )
        .first;
    return tester.widget<Opacity>(finder).opacity;
  }

  Future<void> scroll(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(CustomScrollView), Offset(0, dy));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the title and a back affordance', (tester) async {
    await tester.pumpWidget(harness());

    expect(find.text('Calorie Trends'), findsOneWidget);
    expect(find.byType(HxBackButton), findsOneWidget);
    expect(headerOpacity(tester), 1.0);
  });

  testWidgets('header hides on scroll down and returns on scroll up',
      (tester) async {
    await tester.pumpWidget(harness());
    expect(headerOpacity(tester), 1.0);

    // Scrolling down (dragging content up) hides the header.
    await scroll(tester, -600);
    expect(headerOpacity(tester), 0.0);

    // Scrolling back up returns it, without needing to reach the top.
    await scroll(tester, 120);
    expect(headerOpacity(tester), 1.0);
  });

  testWidgets('header stays hidden while scrolling further down',
      (tester) async {
    await tester.pumpWidget(harness());

    await scroll(tester, -400);
    expect(headerOpacity(tester), 0.0);
    await scroll(tester, -400);
    expect(headerOpacity(tester), 0.0);
  });

  testWidgets('a drag under the threshold does not flicker the header',
      (tester) async {
    await tester.pumpWidget(harness());

    // Below the 12px threshold: ballistic jitter must not toggle the header.
    await scroll(tester, -8);
    expect(headerOpacity(tester), 1.0);
  });

  testWidgets('returning to the top always shows the header', (tester) async {
    await tester.pumpWidget(harness());

    await scroll(tester, -600);
    expect(headerOpacity(tester), 0.0);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(headerOpacity(tester), 1.0);
  });

  testWidgets('a page shorter than the viewport keeps its header',
      (tester) async {
    await tester.pumpWidget(harness(itemCount: 1));

    await scroll(tester, -300);
    expect(headerOpacity(tester), 1.0);
  });

  testWidgets('pinnedBottom stays on screen while the header hides',
      (tester) async {
    await tester.pumpWidget(
      harness(pinnedBottom: const Text('START FAST')),
    );

    expect(find.text('START FAST'), findsOneWidget);
    await scroll(tester, -600);
    expect(headerOpacity(tester), 0.0);
    expect(find.text('START FAST'), findsOneWidget);
  });
}
