import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/widgets/floating_nav_bar.dart';

void main() {
  testWidgets('FloatingNavBar renders all 5 tabs and responds to tap', (
    WidgetTester tester,
  ) async {
    int tappedIndex = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: FloatingNavBar(
            currentIndex: 0,
            onTap: (index) {
              tappedIndex = index;
            },
          ),
        ),
      ),
    );

    // Verify all 5 tab icons are displayed
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
    expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);

    // Tap Nutrition tab (index 1)
    await tester.tap(find.byIcon(Icons.restaurant_rounded));
    await tester.pumpAndSettle();

    expect(tappedIndex, equals(1));
  });
}
