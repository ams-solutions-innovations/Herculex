import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/gamification/data/xp_ledger_repository.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('training level ladder', () {
    test('has five deterministic levels in each band', () {
      expect(trainingLevels, hasLength(15));
      expect(
        trainingLevels.where((level) => level.band == LevelBand.novice),
        hasLength(5),
      );
      expect(
        trainingLevels.where((level) => level.band == LevelBand.intermediate),
        hasLength(5),
      );
      expect(
        trainingLevels.where((level) => level.band == LevelBand.advanced),
        hasLength(5),
      );
    });

    test('calculates a bounded progress segment', () {
      const progress = LevelProgress(totalXp: 175, completedWorkouts: 3);

      expect(progress.level.title, 'Novice II');
      expect(progress.nextLevel?.title, 'Novice III');
      expect(progress.xpRemaining, 75);
      expect(progress.progressToNext, closeTo(0.5, 0.001));
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

    test('reconciles synced sessions idempotently and counts all logged workouts', () async {
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
      final filteredProgress = repository.getProgressForActiveSessions([10, 11]);
      expect(filteredProgress.completedWorkouts, 2);

      repository.dispose();
    });
  });
}
