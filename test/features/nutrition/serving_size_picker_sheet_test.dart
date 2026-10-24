import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/presentation/sheets/serving_size_picker_sheet.dart';

void main() {
  group('ServingSizePickerSheet', () {
    testWidgets('renders in dial mode by default with steps and unit chips', (
      tester,
    ) async {
      final ctrl = TextEditingController(text: '40');
      String selectedUnit = 'g';

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ServingSizePickerSheet.show(
                    context,
                    quantityController: ctrl,
                    isFood: true,
                    selectedUnit: selectedUnit,
                    availableUnits: const ['g', 'ml', 'oz'],
                    onUnitSelected: (u) => selectedUnit = u,
                    foodTitle: "'z bregov Protein Snack",
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Check title and food subtitle
      expect(find.text('Serving Size & Unit'), findsOneWidget);
      expect(find.text("'z bregov Protein Snack"), findsOneWidget);

      // Check mode toggle buttons
      expect(find.text('Dial'), findsOneWidget);
      expect(find.text('Keypad'), findsOneWidget);

      // Check digital readout
      expect(find.text('40'), findsOneWidget);
      expect(find.text('g'), findsWidgets);

      // Check gram step buttons (-10, -1, +1, +10)
      expect(find.text('-10'), findsOneWidget);
      expect(find.text('-1'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('+10'), findsOneWidget);

      // Check units
      expect(find.text('Unit'), findsOneWidget);
      expect(find.text('ml'), findsOneWidget);
      expect(find.text('oz'), findsOneWidget);

      // Check Done button
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('stepper buttons adjust amount and sync with controller', (
      tester,
    ) async {
      final ctrl = TextEditingController(text: '40');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ServingSizePickerSheet.show(
                    context,
                    quantityController: ctrl,
                    isFood: true,
                    selectedUnit: 'g',
                    availableUnits: const ['g'],
                    onUnitSelected: (_) {},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap +10
      await tester.tap(find.text('+10'));
      await tester.pumpAndSettle();
      expect(ctrl.text, '50');
      expect(find.text('50'), findsOneWidget);

      // Tap +1
      await tester.tap(find.text('+1'));
      await tester.pumpAndSettle();
      expect(ctrl.text, '51');
      expect(find.text('51'), findsOneWidget);

      // Tap -10
      await tester.tap(find.text('-10'));
      await tester.pumpAndSettle();
      expect(ctrl.text, '41');
      expect(find.text('41'), findsOneWidget);
    });

    testWidgets('switching between Dial and Keypad modes works seamlessly', (
      tester,
    ) async {
      final ctrl = TextEditingController(text: '40');

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ServingSizePickerSheet.show(
                    context,
                    quantityController: ctrl,
                    isFood: true,
                    selectedUnit: 'g',
                    availableUnits: const ['g', 'oz'],
                    onUnitSelected: (_) {},
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Keypad toggle
      await tester.tap(find.text('Keypad'));
      await tester.pumpAndSettle();

      // TextField is now displayed
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('40'), findsOneWidget);

      // Enter new text in TextField
      await tester.enterText(find.byType(TextField), '75');
      await tester.pumpAndSettle();
      expect(ctrl.text, '75');

      // Switch back to Dial mode
      await tester.tap(find.text('Dial'));
      await tester.pumpAndSettle();

      // TextField should disappear, dial readout shows 75
      expect(find.byType(TextField), findsNothing);
      expect(find.text('75'), findsOneWidget);

      // Tapping the readout badge switches back to Keypad
      await tester.tap(find.text('75'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // Tap Done
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Serving Size & Unit'), findsNothing);
      expect(ctrl.text, '75');
    });

    testWidgets(
      'unit selection calls onUnitSelected and updates step buttons',
      (tester) async {
        final ctrl = TextEditingController(text: '2');
        String selectedUnit = 'servings';

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => ServingSizePickerSheet.show(
                      context,
                      quantityController: ctrl,
                      isFood: true,
                      selectedUnit: selectedUnit,
                      availableUnits: const ['servings', 'g'],
                      onUnitSelected: (u) {
                        selectedUnit = u;
                        if (u == 'g') {
                          ctrl.text = '100';
                        }
                      },
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // In decimal unit ('servings'), step buttons are -1.0, -0.1, +0.1, +1.0
        expect(find.text('-1.0'), findsOneWidget);
        expect(find.text('+1.0'), findsOneWidget);

        // Tap 'g'
        await tester.tap(find.text('g'));
        await tester.pumpAndSettle();

        // Now it's integer unit ('g'), step buttons are -10, -1, +1, +10
        expect(find.text('-10'), findsOneWidget);
        expect(find.text('+10'), findsOneWidget);
        expect(ctrl.text, '100');
      },
    );
  });
}
