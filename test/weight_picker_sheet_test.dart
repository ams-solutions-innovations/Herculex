import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/measurements/presentation/weight_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('WeightPickerSheet', () {
    testWidgets('renders initial weight and components', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => WeightPickerSheet.show(
                    context,
                    initialKg: 80.0,
                    previousKg: 80.5,
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

      // Check header and title
      expect(find.text('Log weight'), findsOneWidget);
      expect(find.text('KG'), findsOneWidget);

      // Check step buttons
      expect(find.text('-1.0'), findsOneWidget);
      expect(find.text('-0.1'), findsOneWidget);
      expect(find.text('+0.1'), findsOneWidget);
      expect(find.text('+1.0'), findsOneWidget);

      // Check action buttons
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save 80.0 kg'), findsOneWidget);
    });

    testWidgets('step buttons adjust weight and save returns kg', (
      tester,
    ) async {
      double? loggedKg;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    loggedKg = await WeightPickerSheet.show(
                      context,
                      initialKg: 75.0,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap +1.0
      await tester.tap(find.text('+1.0'));
      await tester.pumpAndSettle();
      expect(find.text('Save 76.0 kg'), findsOneWidget);

      // Tap +0.1
      await tester.tap(find.text('+0.1'));
      await tester.pumpAndSettle();
      expect(find.text('Save 76.1 kg'), findsOneWidget);

      // Tap -1.0
      await tester.tap(find.text('-1.0'));
      await tester.pumpAndSettle();
      expect(find.text('Save 75.1 kg'), findsOneWidget);

      // Tap Save
      await tester.tap(find.text('Save 75.1 kg'));
      await tester.pumpAndSettle();

      expect(find.text('Log weight'), findsNothing);
      expect(loggedKg, closeTo(75.1, 0.05));
    });

    testWidgets('unit toggle switches between KG and LB', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () =>
                      WeightPickerSheet.show(context, initialKg: 70.0),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('KG'), findsOneWidget);

      // Tap unit switch
      await tester.tap(find.text('KG'));
      await tester.pumpAndSettle();

      expect(find.text('LB'), findsOneWidget);

      // Tap unit switch back
      await tester.tap(find.text('LB'));
      await tester.pumpAndSettle();

      expect(find.text('KG'), findsOneWidget);
    });
  });
}
