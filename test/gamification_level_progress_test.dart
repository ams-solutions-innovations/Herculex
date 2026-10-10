import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/gamification/data/level_band_repository.dart';
import 'package:herculex/features/gamification/data/xp_ledger_repository.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('training level ladder', () {
    test('has ranks I to V in each of the four bands', () {
      expect(trainingLevels, hasLength(20));
      for (final band in LevelBand.values) {
        final ranks = trainingLevels.where((level) => level.band == band);
        expect(ranks, hasLength(5));
        expect(ranks.first.xpIntoBand, 0);
        expect(ranks.first.title, '${band.label} I');
      }
    });

    test('calculates a bounded progress segment inside the band', () {
      const progress = LevelProgress(band: LevelBand.novice, xpInBand: 175);

      expect(progress.level.title, 'Novice II');
      expect(progress.nextLevel?.title, 'Novice III');
      expect(progress.xpRemaining, 75);
      expect(progress.progressToNext, closeTo(0.5, 0.001));
    });

    test('rank V never spills into the next band without strength', () {
      const progress = LevelProgress(
        band: LevelBand.intermediate,
        xpInBand: 50000,
      );

      expect(progress.level.title, 'Intermediate V');
      expect(progress.nextLevel, isNull);
      expect(progress.isBandMaxed, isTrue);
      expect(progress.progressToNext, 1);
    });
  });

  group('level band', () {
    test('only promotes, and restarts ranks at the promotion XP', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = LevelBandRepository(prefs);
      final at = DateTime(2026, 10, 8);

      expect(repository.current.band, LevelBand.novice);

      final promoted = await repository.promoteIfHigher(
        band: LevelBand.advanced,
        totalXp: 5000,
        at: at,
      );
      expect(promoted.band, LevelBand.advanced);
      expect(promoted.xpAtEntry, 5000);

      final same = await repository.promoteIfHigher(
        band: LevelBand.advanced,
        totalXp: 6000,
        at: at,
      );
      expect(same.xpAtEntry, 5000);

      final lower = await repository.promoteIfHigher(
        band: LevelBand.novice,
        totalXp: 7000,
        at: at,
      );
      expect(lower.band, LevelBand.advanced);
      expect(LevelBandRepository(prefs).current.band, LevelBand.advanced);
    });
  });

  group('XP ledger', () {
    test('persists a workout award and rejects a duplicate session', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = XpLedgerRepository(prefs);
      const award = XpAward(xp: 52, reasons: ['Workout completed +40 XP']);

      final first = await repository.record(
        id: 'workout:42',
        awardedAt: DateTime(2026, 9, 11),
        award: award,
      );
      final duplicate = await repository.record(
        id: 'workout:42',
        awardedAt: DateTime(2026, 9, 11),
        award: award,
      );
      final restored = XpLedgerRepository(prefs);

      expect(first, isTrue);
      expect(duplicate, isFalse);
      expect(repository.progress.totalXp, 52);
      expect(repository.progress.completedWorkouts, 1);
      expect(restored.progress.totalXp, 52);
      expect(restored.entries.single.reasons, ['Workout completed +40 XP']);

      repository.dispose();
      restored.dispose();
    });

    test(
      'reconciles synced sessions idempotently and counts all logged workouts',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repository = XpLedgerRepository(prefs);

        final sessions = [
          WorkoutSessionData(
            id: 10,
            startedAt: DateTime(2026, 9, 1, 10),
            endedAt: DateTime(2026, 9, 1, 11),
            name: 'Workout 1',
          ),
          WorkoutSessionData(
            id: 11,
            startedAt: DateTime(2026, 9, 3, 10),
            endedAt: DateTime(2026, 9, 3, 11),
            name: 'Workout 2',
          ),
          WorkoutSessionData(
            id: 12,
            startedAt: DateTime(2026, 9, 5, 10),
            endedAt: DateTime(2026, 9, 5, 11),
            name: 'Workout 3',
          ),
          // Active workout not yet ended should be ignored
          WorkoutSessionData(
            id: 13,
            startedAt: DateTime(2026, 9, 6, 10),
            endedAt: null,
            name: 'Ongoing',
          ),
        ];

        final reconciled = await repository.reconcileWithSessions(
          sessions: sessions,
          snapshot: null,
          bodyweightKg: 80,
        );

        expect(reconciled, isTrue);
        // 3 completed sessions reconciled
        expect(repository.progress.completedWorkouts, 3);
        // Base XP is 40 per workout + 10 for consistency when gap is 20-96h
        expect(repository.progress.totalXp, greaterThanOrEqualTo(120));

        // Re-reconciling same sessions must do nothing
        final second = await repository.reconcileWithSessions(
          sessions: sessions,
          snapshot: null,
          bodyweightKg: 80,
        );
        expect(second, isFalse);
        expect(repository.progress.completedWorkouts, 3);

        // Filtering active sessions returns only non-deleted
        final filteredProgress = repository.getProgressForActiveSessions([
          10,
          11,
        ]);
        expect(filteredProgress.completedWorkouts, 2);

        repository.dispose();
      },
    );
  });
}
