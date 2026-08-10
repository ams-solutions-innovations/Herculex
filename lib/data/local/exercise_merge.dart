import 'package:drift/drift.dart';

import 'database.dart';

/// One catalog row folded into another.
///
/// [loser] and [winner] are slugs where possible; [loser] also accepts a bare
/// exercise name so rows that predate slugs (or were auto-created by watch
/// sync) can still be merged.
class ExerciseMerge {
  /// Slug or name of the row being removed.
  final String loser;

  /// Slug of the row that absorbs it.
  final String winner;

  const ExerciseMerge({required this.loser, required this.winner});
}

/// Result of running one merge, for logging and tests.
class ExerciseMergeOutcome {
  final ExerciseMerge merge;
  final bool applied;

  /// Why the merge was skipped — unresolved slug, or loser == winner.
  final String? skippedReason;

  /// How many logged workout-exercise rows were repointed.
  final int repointedWorkoutExercises;

  const ExerciseMergeOutcome({
    required this.merge,
    required this.applied,
    this.skippedReason,
    this.repointedWorkoutExercises = 0,
  });
}

/// Folds duplicate catalog rows together without losing history.
///
/// Deleting a catalog row outright is not an option: six tables reference
/// [ExerciseCatalog], and `workout_exercises` carries every logged set. So the
/// loser's references are repointed at the winner first, then the loser row is
/// removed.
///
/// The subtle part is [WorkoutExercises.equipmentVariant]. When it is null,
/// `TrainingSnapshot` resolves the variant through the catalog row's *current*
/// modality — so repointing a Dumbbell Row log at a Barbell Row row would
/// silently reclassify its history and merge two distinct per-equipment PRs.
/// Every repoint therefore backfills the loser's modality into any null
/// variant first, and never overwrites one that was already set.
class ExerciseMergeEngine {
  final AppDatabase _db;

  ExerciseMergeEngine(this._db);

  /// Applies [merges] in order, each in its own transaction so one bad entry
  /// cannot leave a half-merged catalog behind.
  Future<List<ExerciseMergeOutcome>> apply(List<ExerciseMerge> merges) async {
    final outcomes = <ExerciseMergeOutcome>[];
    for (final merge in merges) {
      outcomes.add(await _applyOne(merge));
    }
    return outcomes;
  }

  Future<ExerciseMergeOutcome> _applyOne(ExerciseMerge merge) async {
    return _db.transaction(() async {
      final winner = await _resolve(merge.winner);
      final loser = await _resolve(merge.loser);

      if (winner == null) {
        return ExerciseMergeOutcome(
          merge: merge,
          applied: false,
          skippedReason: 'winner "${merge.winner}" not found',
        );
      }
      if (loser == null) {
        // Already merged on a previous run — this is the idempotent path, not
        // an error.
        return ExerciseMergeOutcome(
          merge: merge,
          applied: false,
          skippedReason: 'loser "${merge.loser}" not found',
        );
      }
      if (loser.id == winner.id) {
        return ExerciseMergeOutcome(
          merge: merge,
          applied: false,
          skippedReason: 'loser and winner are the same row',
        );
      }

      // 1. Logged history. Backfill the variant before repointing, so the
      //    equipment this set was actually performed with survives.
      final repointed = await _repointWithVariant(
        'workout_exercises',
        loser.id,
        winner.id,
        loser.modality,
      );

      // 2. Program templates carry their own equipment variant.
      await _repointWithVariant(
        'program_day_exercises',
        loser.id,
        winner.id,
        loser.modality,
      );

      // 3. Plain references — nothing equipment-specific to preserve.
      //    machine_settings belongs here, not below: it is keyed per gym, not
      //    per exercise, so the loser's saved seat/angle settings are real
      //    user data that must survive the merge.
      for (final table in const [
        'rotation_members',
        'micro_workouts',
        'template_exercises',
        'machine_settings',
      ]) {
        await _repoint(table, loser.id, winner.id);
      }

      // 4. exercise_progressions is unique on exercise_id, so a repoint would
      //    violate the constraint. The winner's override is authoritative.
      await _repointUnique('exercise_progressions', loser.id, winner.id);

      // 5. Keep the loser's name resolvable. Program CSV import throws on
      //    unknown names and watch sync falls back to name matching, so
      //    without this a merge breaks both.
      await _addAliasIfMissing(winner.id, loser.name);
      for (final alias in _splitAka(loser.aka)) {
        await _addAliasIfMissing(winner.id, alias);
      }

      // 6. The importer rewrites the winner's muscle and alias rows anyway;
      //    the loser's would be orphaned.
      await (_db.delete(_db.exerciseMuscles)
            ..where((t) => t.exerciseId.equals(loser.id)))
          .go();
      await (_db.delete(_db.exerciseAliases)
            ..where((t) => t.exerciseId.equals(loser.id)))
          .go();

      await (_db.delete(_db.exerciseCatalog)
            ..where((t) => t.id.equals(loser.id)))
          .go();

      return ExerciseMergeOutcome(
        merge: merge,
        applied: true,
        repointedWorkoutExercises: repointed,
      );
    });
  }

  /// Looks up by slug first, then by exact name.
  Future<ExerciseCatalogData?> _resolve(String slugOrName) async {
    final bySlug = await (_db.select(_db.exerciseCatalog)
          ..where((t) => t.slug.equals(slugOrName)))
        .getSingleOrNull();
    if (bySlug != null) return bySlug;
    return (_db.select(_db.exerciseCatalog)
          ..where((t) => t.name.equals(slugOrName)))
        .getSingleOrNull();
  }

  Future<int> _repointWithVariant(
    String table,
    int loserId,
    int winnerId,
    String loserModality,
  ) async {
    final count = await _countReferences(table, loserId);
    await _db.customUpdate(
      'UPDATE $table SET equipment_variant = COALESCE(equipment_variant, ?), '
      'exercise_id = ? WHERE exercise_id = ?',
      variables: [
        Variable<String>(loserModality),
        Variable<int>(winnerId),
        Variable<int>(loserId),
      ],
    );
    return count;
  }

  Future<void> _repoint(String table, int loserId, int winnerId) async {
    await _db.customUpdate(
      'UPDATE $table SET exercise_id = ? WHERE exercise_id = ?',
      variables: [Variable<int>(winnerId), Variable<int>(loserId)],
    );
  }

  /// For tables with a uniqueness constraint on `exercise_id`: the winner's
  /// existing row is authoritative, so the loser's is discarded rather than
  /// repointed into a conflict.
  Future<void> _repointUnique(String table, int loserId, int winnerId) async {
    final winnerHasRow = await _countReferences(table, winnerId) > 0;
    if (winnerHasRow) {
      await _db.customUpdate(
        'DELETE FROM $table WHERE exercise_id = ?',
        variables: [Variable<int>(loserId)],
      );
      return;
    }
    await _repoint(table, loserId, winnerId);
  }

  Future<int> _countReferences(String table, int exerciseId) async {
    final rows = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM $table WHERE exercise_id = ?',
      variables: [Variable<int>(exerciseId)],
    ).get();
    return rows.first.read<int>('c');
  }

  Future<void> _addAliasIfMissing(int exerciseId, String alias) async {
    final trimmed = alias.trim();
    if (trimmed.isEmpty) return;
    final existing =
        await (_db.select(_db.exerciseAliases)
              ..where(
                (t) => t.exerciseId.equals(exerciseId) & t.alias.equals(trimmed),
              ))
            .getSingleOrNull();
    if (existing != null) return;
    await _db
        .into(_db.exerciseAliases)
        .insert(
          ExerciseAliasesCompanion.insert(
            exerciseId: exerciseId,
            alias: trimmed,
          ),
        );
  }

  static List<String> _splitAka(String? aka) {
    if (aka == null || aka.trim().isEmpty) return const [];
    return [
      for (final part in aka.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }
}
