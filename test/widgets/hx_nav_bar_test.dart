import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/theme/app_theme.dart';
import 'package:herculex/ui/hx_nav_bar.dart';

void main() {
  Widget harness({
    int currentIndex = 0,
    ValueChanged<int>? onTap,
    bool quickAddOpen = false,
    VoidCallback? onQuickAddTap,
  }) =>
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          bottomNavigationBar: HxNavBar(
            currentIndex: currentIndex,
            onTap: onTap ?? (_) {},
            quickAddOpen: quickAddOpen,
            onQuickAddTap: onQuickAddTap ?? () {},
          ),
        ),
      );

  testWidgets('renders all 4 destinations plus the quick-add button',
      (tester) async {
    await tester.pumpWidget(harness());

    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('tapping a destination reports its index', (tester) async {
    int? tapped;
    await tester.pumpWidget(harness(onTap: (i) => tapped = i));

    await tester.tap(find.byIcon(Icons.restaurant_rounded));
    expect(tapped, 1);

    await tester.tap(find.byIcon(Icons.fitness_center_rounded));
    expect(tapped, 2);

    await tester.tap(find.byIcon(Icons.person_rounded));
    expect(tapped, 3);
  });

  testWidgets('tapping the + reports quick-add rather than a tab index',
      (tester) async {
    var quickAddTaps = 0;
    int? tabTap;
    await tester.pumpWidget(harness(
      onTap: (i) => tabTap = i,
      onQuickAddTap: () => quickAddTaps++,
    ));

    await tester.tap(find.byIcon(Icons.add_rounded));

    expect(quickAddTaps, 1);
    expect(tabTap, isNull);
  });

  testWidgets('the + rotates open when quickAddOpen is true', (tester) async {
    await tester.pumpWidget(harness(quickAddOpen: true));
    await tester.pumpAndSettle();

    final rotation = tester.widget<AnimatedRotation>(
      find.byType(AnimatedRotation),
    );
    expect(rotation.turns, 0.125);
  });
}
