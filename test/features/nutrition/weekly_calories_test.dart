import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/daily_totals.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/presentation/nutrition_providers.dart';
import 'package:herculex/features/nutrition/presentation/weekly_calories_view.dart';
import 'package:herculex/features/nutrition/presentation/widgets/macro_chart.dart';

void main() {
  testWidgets('MacroTrendChart renders with data', (tester) async {
    final history = {
      '2026-08-20': const DailyTotals(
        kcal: 2200,
        proteinG: 160,
        carbsG: 220,
        fatG: 70,
        fiberG: 30,
        sodiumMg: 2000,
        potassiumMg: 3000,
        cholesterolMg: 200,
        micros: {},
      ),
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MacroTrendChart(
            historyMap: history,
            macro: 'kcal',
            range: '7D',
            targetValue: 2500,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MacroTrendChart), findsOneWidget);
  });

  testWidgets('MacroTrendChart renders empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: MacroTrendChart(
            historyMap: {},
            macro: 'kcal',
            range: '7D',
            targetValue: 2500,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No logged nutrition entries in the selected timeframe.'),
      findsOneWidget,
    );
  });

  testWidgets('WeeklyCaloriesView renders with data', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionHistoryProvider.overrideWith(
            (ref) => Stream.value({
              '2026-08-20': const DailyTotals(
                kcal: 2200,
                proteinG: 160,
                carbsG: 220,
                fatG: 70,
                fiberG: 30,
                sodiumMg: 2000,
                potassiumMg: 3000,
                cholesterolMg: 200,
                micros: {},
              ),
            }),
          ),
          effectiveTargetsProvider(today).overrideWith(
            (ref) => Future.value(
              const MacroTargets(
                kcal: 2500,
                proteinG: 180,
                carbsG: 250,
                fatG: 80,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: WeeklyCaloriesView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Calorie Trends'), findsOneWidget);
  });

  testWidgets('MacroTrendView renders for protein, carbs, and fat', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final historyData = {
      '2026-08-20': const DailyTotals(
        kcal: 2200,
        proteinG: 160,
        carbsG: 220,
        fatG: 70,
        fiberG: 30,
        sodiumMg: 2000,
        potassiumMg: 3000,
        cholesterolMg: 200,
        micros: {},
      ),
    };

    final targetData = const MacroTargets(
      kcal: 2500,
      proteinG: 180,
      carbsG: 250,
      fatG: 80,
    );

    // 1. Protein
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionHistoryProvider.overrideWith(
            (ref) => Stream.value(historyData),
          ),
          effectiveTargetsProvider(
            today,
          ).overrideWith((ref) => Future.value(targetData)),
        ],
        child: const MaterialApp(home: MacroTrendView(macro: 'protein')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Protein Trends'), findsOneWidget);
    expect(find.textContaining('PROTEIN'), findsWidgets);

    // 2. Carbs
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionHistoryProvider.overrideWith(
            (ref) => Stream.value(historyData),
          ),
          effectiveTargetsProvider(
            today,
          ).overrideWith((ref) => Future.value(targetData)),
        ],
        child: const MaterialApp(home: MacroTrendView(macro: 'carbs')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Carb Trends'), findsOneWidget);
    expect(find.textContaining('CARBS'), findsWidgets);

    // 3. Fat
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionHistoryProvider.overrideWith(
            (ref) => Stream.value(historyData),
          ),
          effectiveTargetsProvider(
            today,
          ).overrideWith((ref) => Future.value(targetData)),
        ],
        child: const MaterialApp(home: MacroTrendView(macro: 'fat')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fat Trends'), findsOneWidget);
    expect(find.textContaining('FATS'), findsWidgets);
  });
}
