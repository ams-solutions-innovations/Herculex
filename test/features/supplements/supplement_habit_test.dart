import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/supplements/data/supplement_repository.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/domain/supplement_habit_stats.dart';
import 'package:herculex/features/supplements/domain/supplement_presets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SupplementHabitStats', () {
    final supplements = const [
      Supplement(
        id: 'creatine',
        name: 'Creatine Monohydrate',
        doseAmount: 5,
        doseUnit: 'g',
      ),
      Supplement(
        id: 'vit_d',
        name: 'Vitamin D3',
        doseAmount: 100,
        doseUnit: 'µg',
      ),
    ];

    test('computes currentStreak, bestStreak, consistencyRate, and itemStats', () {
      final today = DateTime(2026, 10, 11);
      String iso(int daysAgo) => SupplementHabitStats.isoForDate(
        today.subtract(Duration(days: daysAgo)),
      );

      // 4 days ago: both taken (100%)
      // 3 days ago: both taken (100%)
      // 2 days ago: only creatine taken (50%)
      // 1 day ago (yesterday): both taken (100%)
      // 0 days ago (today): both taken (100%)
      final history = <String, Set<String>>{
        iso(4): {'creatine', 'vit_d'},
        iso(3): {'creatine', 'vit_d'},
        iso(2): {'creatine'},
        iso(1): {'creatine', 'vit_d'},
        iso(0): {'creatine', 'vit_d'},
      };

      final stats = SupplementHabitStats.compute(
        supplements: supplements,
        historyByIso: history,
        rangeDays: 7,
        today: today,
        earliestTrackedDate: today.subtract(const Duration(days: 4)),
      );

      // Current 100% streak is 2 (yesterday + today), best is 2
      expect(stats.currentStreak, 2);
      expect(stats.bestStreak, 2);
      expect(stats.activeStreak, 5);
      expect(stats.perfectDays, 4);
      expect(stats.activeDays, 5);
      expect(stats.totalDosesTaken, 9);
      expect(stats.effectiveWindowDays, 5);
      // Ratios over 5 active window days: (1 + 1 + 0.5 + 1 + 1) / 5 = 4.5 / 5 = 0.90
      expect(stats.consistencyRate, closeTo(0.90, 0.001));
      expect(stats.dailyPoints.length, 7);
      expect(stats.heatmapPoints.length, 28);

      // Per-supplement breakdown:
      // Creatine was taken all 5 days -> streak 5, 100% adherence
      final creatineStat = stats.itemStats.firstWhere(
        (s) => s.supplement.id == 'creatine',
      );
      expect(creatineStat.currentStreak, 5);
      expect(creatineStat.adherenceRate, closeTo(1.0, 0.001));

      // Vitamin D was taken 4 of 5 days (missed 2 days ago) -> streak 2, 80% adherence
      final vitDStat = stats.itemStats.firstWhere(
        (s) => s.supplement.id == 'vit_d',
      );
      expect(vitDStat.currentStreak, 2);
      expect(vitDStat.adherenceRate, closeTo(0.80, 0.001));
    });

    test('preserves yesterday streak when today is not yet completed', () {
      final today = DateTime(2026, 10, 11);
      String iso(int daysAgo) => SupplementHabitStats.isoForDate(
        today.subtract(Duration(days: daysAgo)),
      );

      final history = <String, Set<String>>{
        iso(3): {'creatine', 'vit_d'},
        iso(2): {'creatine', 'vit_d'},
        iso(1): {'creatine', 'vit_d'},
        iso(0): const {}, // today still in progress
      };

      final stats = SupplementHabitStats.compute(
        supplements: supplements,
        historyByIso: history,
        rangeDays: 7,
        today: today,
      );

      expect(stats.currentStreak, 3);
      expect(stats.bestStreak, 3);
    });
  });

  group('SupplementRepository multi-day history', () {
    test('retains history up to 365 days and toggles past dates', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SupplementRepository(prefs);

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await repo.markTakenForDate('creatine', true, yesterday);
      expect(repo.loadTakenForDate(yesterday), contains('creatine'));

      await repo.markTakenForDate('creatine', false, yesterday);
      expect(repo.loadTakenForDate(yesterday), isEmpty);

      repo.dispose();
    });
  });

  group('Creatine loading phase', () {
    final creatine = SupplementPreset.byKey('creatine')!
        .toSupplement()
        .copyWith(
          loadingDoseAmount: 20,
          loadingDays: 7,
          loadingStartIso: '2026-11-10',
        );

    test('uses the loading dose only inside the loading window', () {
      expect(creatine.isLoadingOn(DateTime(2026, 11, 9)), isFalse);
      expect(creatine.isLoadingOn(DateTime(2026, 11, 10)), isTrue);
      expect(creatine.isLoadingOn(DateTime(2026, 11, 16)), isTrue);
      expect(creatine.isLoadingOn(DateTime(2026, 11, 17)), isFalse);

      expect(creatine.doseLabelFor(DateTime(2026, 11, 12)), '20 g');
      expect(creatine.doseLabelFor(DateTime(2026, 11, 20)), '5 g');
      expect(creatine.loadingEnd, DateTime(2026, 11, 16));
    });

    test('round-trips through JSON and ignores a legacy barcode key', () {
      final back = Supplement.fromJson({
        ...creatine.toJson(),
        'barcode': '0748927023879',
      });
      expect(back.presetKey, 'creatine');
      expect(back.hasLoadingPhase, isTrue);
      expect(back.doseAmountFor(DateTime(2026, 11, 11)), 20);
    });

    test('clearLoading drops the phase', () {
      final plain = creatine.copyWith(clearLoading: true);
      expect(plain.hasLoadingPhase, isFalse);
      expect(plain.doseAmountFor(DateTime(2026, 11, 11)), 5);
    });
  });

  group('SupplementPreset', () {
    test('keys and ids are unique and stable', () {
      final keys = supplementPresets.map((p) => p.key).toList();
      expect(keys.toSet().length, keys.length);
      expect(SupplementPreset.byKey('zma')!.supplementId, 'preset_zma');
    });

    test('only creatine offers a loading phase', () {
      expect(
        supplementPresets.where((p) => p.supportsLoading).map((p) => p.key),
        ['creatine'],
      );
    });
  });
}
