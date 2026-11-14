import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/features/nutrition/domain/daily_totals.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/presentation/sheets/quick_add_sheet.dart';
import 'package:herculex/features/nutrition/presentation/views/macro_trend_view.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_database.dart';

class _FixedClock implements Clock {
  _FixedClock(this.fixed);
  final DateTime fixed;
  @override
  DateTime now() => fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NutritionRepository quick add', () {
    late AppDatabase db;
    late NutritionRepository repo;
    final today = DateTime(2026, 11, 14);

    setUp(() async {
      db = await openTestDatabase();
      repo = NutritionRepository(db, OpenFoodFactsClient(), _FixedClock(today));
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'logQuickAdd stores kcal and protein and updates daily & range totals',
      () async {
        await repo.logQuickAdd(
          date: today,
          kcal: 650,
          proteinG: 45,
          mealKey: 'lunch',
          name: 'Restaurant Lunch',
        );

        final entries = await repo.watchEntriesForDate(today).first;
        expect(entries, hasLength(1));
        expect(entries.first.foodId, isNull);
        expect(entries.first.recipeId, isNull);
        expect(entries.first.snapshotBasis, NutritionRepository.quickAddBasis);
        expect(entries.first.snapshotName, 'Restaurant Lunch');

        final totals = await repo.watchDailyTotals(today).first;
        expect(totals.kcal, 650);
        expect(totals.proteinG, 45);
        expect(totals.carbsG, 0);
        expect(totals.fatG, 0);

        final rangeTotals = await repo
            .watchDailyTotalsForRange(today, today)
            .first;
        final iso = DateFormat('yyyy-MM-dd').format(today);
        expect(rangeTotals[iso]?.kcal, 650);
        expect(rangeTotals[iso]?.proteinG, 45);
      },
    );

    test(
      'logQuickAdd full-day estimate uses quickAddDayBasis and can be updated',
      () async {
        await repo.logQuickAdd(
          date: today,
          kcal: 2400,
          proteinG: 170,
          mealKey: 'snack',
          isFullDay: true,
        );

        final entries = await repo.watchEntriesForDate(today).first;
        expect(entries, hasLength(1));
        final entry = entries.first;
        expect(entry.snapshotBasis, NutritionRepository.quickAddDayBasis);
        expect(entry.snapshotName, 'Full Day Estimate');

        await repo.updateQuickAddEntry(
          id: entry.id,
          kcal: 2600,
          proteinG: 180,
          isFullDay: true,
        );

        final updatedTotals = await repo.watchDailyTotals(today).first;
        expect(updatedTotals.kcal, 2600);
        expect(updatedTotals.proteinG, 180);
      },
    );
  });

  group('MacroTrendView range average', () {
    testWidgets('excludes today and unlogged days from range average', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final twoDaysAgo = today.subtract(const Duration(days: 2));

      // Today has a small partial log (400 kcal), yesterday 2400, twoDaysAgo 2600,
      // and the other 4 days in the 7D window are unlogged.
      final historyMap = <String, DailyTotals>{
        DateFormat('yyyy-MM-dd').format(today): const DailyTotals(
          kcal: 400,
          proteinG: 20,
        ),
        DateFormat('yyyy-MM-dd').format(yesterday): const DailyTotals(
          kcal: 2400,
          proteinG: 160,
        ),
        DateFormat('yyyy-MM-dd').format(twoDaysAgo): const DailyTotals(
          kcal: 2600,
          proteinG: 180,
        ),
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            nutritionHistoryProvider.overrideWith(
              (ref) => Stream.value(historyMap),
            ),
            effectiveTargetsProvider(today).overrideWith(
              (ref) => Future.value(
                const MacroTargets(
                  kcal: 2500,
                  proteinG: 180,
                  carbsG: 250,
                  fatG: 70,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: MacroTrendView(macro: 'kcal')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('2 of 7 days logged in range'),
        200,
      );
      expect(find.text('2 of 7 days logged in range'), findsOneWidget);
      expect(find.text('Avg: 2500 kcal'), findsOneWidget);
    });
  });

  group('QuickAddSheet widget', () {
    testWidgets('submits quick add calories and protein', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = await tester.runAsync(openTestDatabase);
      addTearDown(() => tester.runAsync(db!.close));
      final today = DateTime(2026, 11, 14);
      final repo = NutritionRepository(
        db!,
        OpenFoodFactsClient(),
        _FixedClock(today),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            nutritionRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: QuickAddSheet(
                date: today,
                mealKey: 'snack',
                isFullDay: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quick Add · Full Day'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories (kcal)'),
        '2350',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Protein (g)'),
        '165',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Log Full Day Estimate'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      final totals = await tester.runAsync(
        () => repo.watchDailyTotals(today).first,
      );
      expect(totals?.kcal, 2350);
      expect(totals?.proteinG, 165);
    });
  });
}
