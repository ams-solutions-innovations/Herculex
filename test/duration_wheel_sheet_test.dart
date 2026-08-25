import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workouts/domain/set_metric_format.dart';
import 'package:herculex/features/workouts/presentation/duration_wheel_sheet.dart';

void main() {
  group('DurationWheelSheet', () {
    testWidgets('renders initial seconds and presets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => DurationWheelSheet.show(
                  context,
                  initialSeconds: 45,
                  exerciseName: 'Assault Bike',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      // Open sheet
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Check exercise title and initial duration
      expect(find.text('Set Duration'), findsOneWidget);
      expect(find.text('Assault Bike'), findsOneWidget);
      expect(find.text('45s'), findsWidgets);
      expect(find.text('45 seconds'), findsOneWidget);

      // Check preset chips
      expect(find.text('15s'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
      expect(find.text('1:00'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);

      // Tap preset chip 1:30 (90 seconds)
      await tester.tap(find.text('1:30'));
      await tester.pumpAndSettle();

      expect(find.text('1:30'), findsWidgets);
      expect(find.text('1 min 30 sec'), findsOneWidget);

      // Tap Save button
      await tester.tap(find.text('Save 1:30'));
      await tester.pumpAndSettle();

      // Sheet should be dismissed
      expect(find.text('Set Duration'), findsNothing);
    });

    testWidgets('step buttons adjust duration properly', (tester) async {
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await DurationWheelSheet.show(
                    context,
                    initialSeconds: 30,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap +15s
      await tester.tap(find.text('+15s'));
      await tester.pumpAndSettle();
      expect(find.text('45s'), findsWidgets);

      // Tap +1m (adds 60s -> 105s => 1:45)
      await tester.tap(find.text('+1m'));
      await tester.pumpAndSettle();
      expect(find.text('1:45'), findsWidgets);

      // Save
      await tester.tap(find.text('Save 1:45'));
      await tester.pumpAndSettle();

      expect(result, 105);
    });
  });
}
