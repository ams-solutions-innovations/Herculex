import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';

class ExercisePreferencesRepository {
  ExercisePreferencesRepository(this._db);

  final AppDatabase _db;

  Stream<ExerciseAffinity> watchGlobalAffinity(int exerciseId) {
    return (_db.select(
          _db.exercisePreferences,
        )..where((t) => t.exerciseId.equals(exerciseId) & t.programId.isNull()))
        .watch()
        .map(
          (rows) => rows.isEmpty
              ? ExerciseAffinity.okay
              : ExerciseAffinity.fromId(rows.last.affinity),
        );
  }

  Future<void> setAffinity({
    required int exerciseId,
    required ExerciseAffinity affinity,
    int? programId,
  }) async {
    final existing =
        await (_db.select(_db.exercisePreferences)..where(
              (t) =>
                  t.exerciseId.equals(exerciseId) &
                  (programId == null
                      ? t.programId.isNull()
                      : t.programId.equals(programId)),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.exercisePreferences)
          .insert(
            ExercisePreferencesCompanion.insert(
              exerciseId: exerciseId,
              programId: Value(programId),
              affinity: Value(affinity.id),
            ),
          );
    } else {
      await (_db.update(_db.exercisePreferences)
            ..where((t) => t.id.equals(existing.id)))
          .write(ExercisePreferencesCompanion(affinity: Value(affinity.id)));
    }
  }
}
