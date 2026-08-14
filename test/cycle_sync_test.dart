import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/health/data/cycle_repository.dart';
import 'package:herculex/features/health/domain/cycle_adjuster.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;
  late CycleRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = CycleRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CyclePredictor Domain Logic', () {
    final periodStart = DateTime(2026, 8, 1);

    test('predicts menstrual phase during period duration (days 0-4)', () {
      // Day 0
      final day0Phase = CyclePredictor.predictPhase(
        date: DateTime(2026, 8, 1),
        lastPeriodStart: periodStart,
        avgCycleDays: 28,
        avgPeriodDays: 5,
      );
      expect(day0Phase, equals(CyclePhase.menstrual));

      // Day 4
      final day4Phase = CyclePredictor.predictPhase(
        date: DateTime(2026, 8, 5),
        lastPeriodStart: periodStart,
        avgCycleDays: 28,
        avgPeriodDays: 5,
      );
      expect(day4Phase, equals(CyclePhase.menstrual));
    });

    test('predicts follicular phase after period until ovulation (days 5-11)', () {
      // Day 5
      final day5Phase = CyclePredictor.predictPhase(
        date: DateTime(2026, 8, 6),
        lastPeriodStart: periodStart,
        avgCycleDays: 28,
        avgPeriodDays: 5,
      );
      expect(day5Phase, equals(CyclePhase.follicular));

      // Day 11
      final day11Phase = CyclePredictor.predictPhase(
        date: DateTime(2026, 8, 12),
        lastPeriodStart: periodStart,
        avgCycleDays: 28,
        avgPeriodDays: 5,
      );
      expect(day11Phase, equals(CyclePhase.follicular));
    });

    test('predicts ovulatory phase during ovulation window (days 12-15)', () {
      // Day 13
      final day13Phase = CyclePredictor.predictPhase(
        date: DateTime(2026, 8, 14),
        lastPeriodStart: periodStart,
        avgCycleDays: 28,
        avgPeriodDays: 5,
      );
      expect(day13Phase, equals(CyclePhase.ovulatory));
    });

    test('predicts luteal phase for second half of cycle (days 16-27)', () {
      // Day 20
      final day20Phase = CyclePredictor.predictPhase(
        date: DateTime(2026, 8, 21),
        lastPeriodStart: periodStart,
        avgCycleDays: 28,
        avgPeriodDays: 5,
      );
      expect(day20Phase, equals(CyclePhase.luteal));
    });

    test('computes days until next period accurately', () {
      final daysLeft = CyclePredictor.daysUntilNextPeriod(
        date: DateTime(2026, 8, 21), // Day 20 of 28
        lastPeriodStart: periodStart,
        avgCycleDays: 28,
      );
      expect(daysLeft, equals(8));
    });
  });

  group('CycleAwareAdjuster Suggestions', () {
    test('provides volume reductions and recovery recommendations for menstrual phase', () {
      final adj = CycleAwareAdjuster.suggest(
        phase: CyclePhase.menstrual,
        dayOfCycle: 1,
        totalCycleDays: 28,
        daysUntilNextPeriod: 27,
      );

      expect(adj.volumeFactor, equals(0.8));
      expect(adj.statusLabel, contains('VOLUME REDUCED 20%'));
      expect(adj.trainingRecommendation, contains('deload volume'));
      expect(adj.nutritionRecommendation, contains('iron'));
    });

    test('provides volume boost and strength recommendations for follicular phase', () {
      final adj = CycleAwareAdjuster.suggest(
        phase: CyclePhase.follicular,
        dayOfCycle: 7,
        totalCycleDays: 28,
        daysUntilNextPeriod: 21,
      );

      expect(adj.volumeFactor, equals(1.1));
      expect(adj.statusLabel, contains('VOLUME BOOSTED +10%'));
      expect(adj.trainingRecommendation, contains('progressive overload'));
    });

    test('provides peak intensity guidance for ovulatory phase', () {
      final adj = CycleAwareAdjuster.suggest(
        phase: CyclePhase.ovulatory,
        dayOfCycle: 14,
        totalCycleDays: 28,
        daysUntilNextPeriod: 14,
      );

      expect(adj.volumeFactor, equals(1.0));
      expect(adj.statusLabel, contains('PEAK INTENSITY'));
      expect(adj.trainingRecommendation, contains('1RM'));
    });

    test('provides steady-state guidance for luteal phase', () {
      final adj = CycleAwareAdjuster.suggest(
        phase: CyclePhase.luteal,
        dayOfCycle: 22,
        totalCycleDays: 28,
        daysUntilNextPeriod: 6,
      );

      expect(adj.volumeFactor, equals(0.85));
      expect(adj.statusLabel, contains('VOLUME REDUCED 15%'));
      expect(adj.trainingRecommendation, contains('steady-state'));
    });
  });

  group('CycleRepository Database Operations & Overrides', () {
    test('saves and watches cycle settings', () async {
      final start = DateTime(2026, 8, 1);
      await repo.saveSettings(
        avgCycleDays: 30,
        avgPeriodDays: 6,
        lastPeriodStart: start,
      );

      final settings = await repo.getSettings();
      expect(settings, isNotNull);
      expect(settings!.avgCycleDays, equals(30));
      expect(settings.avgPeriodDays, equals(6));
      expect(settings.lastPeriodStart.year, equals(2026));

      // Test stream
      final streamed = await repo.watchSettings().first;
      expect(streamed?.avgCycleDays, equals(30));
    });

    test('manual override takes precedence over auto-prediction', () async {
      final start = DateTime(2026, 8, 1);
      await repo.saveSettings(
        avgCycleDays: 28,
        avgPeriodDays: 5,
        lastPeriodStart: start,
      );

      // On August 20 (Day 19), default is luteal (volume 0.85)
      final autoAdj = await repo.getAdjustmentFor(DateTime(2026, 8, 20));
      expect(autoAdj.phase, equals(CyclePhase.luteal));
      expect(autoAdj.isManualOverride, isFalse);

      // Log manual override for August 20 as follicular
      await repo.logManualOverride(
        date: DateTime(2026, 8, 20),
        phase: 'follicular',
        intensity: 4,
      );

      final overriddenAdj = await repo.getAdjustmentFor(DateTime(2026, 8, 20));
      expect(overriddenAdj.phase, equals(CyclePhase.follicular));
      expect(overriddenAdj.isManualOverride, isTrue);
      expect(overriddenAdj.volumeFactor, equals(1.1));

      // Clear override
      await repo.clearManualOverride(DateTime(2026, 8, 20));
      final clearedAdj = await repo.getAdjustmentFor(DateTime(2026, 8, 20));
      expect(clearedAdj.phase, equals(CyclePhase.luteal));
      expect(clearedAdj.isManualOverride, isFalse);
    });

    test('ingesting health / Flo period dates updates cycle settings and logs entries', () async {
      final periodDates = [
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 11),
        DateTime(2026, 8, 12),
      ];

      await repo.ingestHealthPeriodDates(periodDates);

      final settings = await repo.getSettings();
      expect(settings, isNotNull);
      expect(settings!.lastPeriodStart, equals(DateTime(2026, 8, 12)));

      final recentLogs = await repo.watchRecentLogs().first;
      expect(recentLogs.length, equals(3));
      expect(recentLogs.any((l) => l.dateIso == '2026-08-10'), isTrue);
    });
  });
}
