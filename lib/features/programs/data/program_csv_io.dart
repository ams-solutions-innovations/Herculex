import 'package:drift/drift.dart';

import '../../../data/local/database.dart';
import '../domain/periodization.dart';
import '../domain/program_csv.dart';
import 'programs_repository.dart';

/// Database glue for program CSV import/export (V2 §12). The pure codec is
/// [ProgramCsv]; this resolves exercise names against the catalog (alias-
/// aware) and materializes weeks/days/exercises.
class ProgramCsvIo {
  final AppDatabase _db;
  final ProgramsRepository _programs;

  ProgramCsvIo(this._db) : _programs = ProgramsRepository(_db);

  Future<String> exportProgram(int programId) async {
    final program = await (_db.select(_db.programs)
          ..where((t) => t.id.equals(programId)))
        .getSingle();
    final weeks = await (_db.select(_db.programWeeks)
          ..where((t) => t.programId.equals(programId))
          ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
        .get();

    final rows = <ProgramCsvRow>[];
    for (final week in weeks) {
      final days = await (_db.select(_db.programDays)
            ..where((t) => t.programWeekId.equals(week.id))
            ..orderBy([(t) => OrderingTerm(expression: t.dayOfWeek)]))
          .get();
      for (final day in days) {
        // Resolved rather than read from ProgramDayExercises directly, so a
        // day whose content comes from a linked template still exports. The
        // CSV format is inline-only, so the link itself is flattened away —
        // re-importing produces an equivalent program with inline exercises.
        final exercises = await _programs.resolveDayExercises(day.id);
        for (final resolved in exercises) {
          final ex = await (_db.select(_db.exerciseCatalog)
                ..where((t) => t.id.equals(resolved.exerciseId)))
              .getSingle();
          final pde = resolved.fromTemplate
              ? null
              : await (_db.select(_db.programDayExercises)
                    ..where((t) =>
                        t.programDayId.equals(day.id) &
                        t.exerciseId.equals(resolved.exerciseId))
                    ..limit(1))
                  .getSingleOrNull();
          rows.add(ProgramCsvRow(
            weekIndex: week.weekIndex,
            dayOfWeek: day.dayOfWeek,
            dayName: day.name,
            exerciseName: ex.name,
            sets: resolved.targetSets,
            repsMin: resolved.targetRepsMin,
            repsMax: resolved.targetRepsMax,
            rpe: pde?.targetRpe,
            setType: pde?.setType ?? 'standard',
            percentOf1Rm: pde?.percentOf1Rm,
            equipmentVariant: pde?.equipmentVariant,
          ));
        }
      }
    }

    return ProgramCsv.encode(ProgramCsvDocument(
      name: program.name,
      weeks: program.weeks,
      periodizationModel: program.periodizationModel,
      rows: rows,
    ));
  }

  /// Imports a CSV document as a new program. Exercise names resolve against
  /// the catalog by exact name first, then alias. Unknown names throw with a
  /// readable message listing every miss. Week rows get intensity/volume
  /// factors from the declared periodization model.
  ///
  /// [createdByUser] is false for marketplace presets so they can be told
  /// apart from user-authored programs; [description] optionally overrides
  /// the program description (presets pass their catalog blurb).
  Future<int> importProgram(
    String csv, {
    bool createdByUser = true,
    String? description,
  }) async {
    final doc = ProgramCsv.decode(csv);
    final model = PeriodizationModel.fromId(doc.periodizationModel);
    final plan = Periodization.plan(model, doc.weeks);

    // Resolve all exercise names up front.
    final catalog = await _db.select(_db.exerciseCatalog).get();
    final byName = <String, ExerciseCatalogData>{
      for (final e in catalog) e.name.toLowerCase(): e,
    };
    final missing = <String>{};
    final resolved = <String, ExerciseCatalogData>{};
    for (final row in doc.rows) {
      final key = row.exerciseName.toLowerCase();
      var ex = byName[key];
      ex ??= catalog
          .where((e) =>
              e.aka != null &&
              e.aka!.toLowerCase().split(',').map((a) => a.trim()).contains(key))
          .firstOrNull;
      if (ex == null) {
        missing.add(row.exerciseName);
      } else {
        resolved[key] = ex;
      }
    }
    if (missing.isNotEmpty) {
      throw ProgramCsvFormatException(
          'Unknown exercises: ${missing.join(', ')}');
    }

    return _db.transaction(() async {
      final programId = await _db.into(_db.programs).insert(
            ProgramsCompanion.insert(
              name: doc.name,
              description: Value(description),
              weeks: Value(doc.weeks),
              periodizationModel: Value(model.id),
              createdByUser: Value(createdByUser),
            ),
          );

      for (final week in plan) {
        final weekId = await _db.into(_db.programWeeks).insert(
              ProgramWeeksCompanion.insert(
                programId: programId,
                weekIndex: week.weekIndex,
                adjustmentFactor: Value(week.volumeFactor),
                blockPhase: Value(week.blockPhase),
                intensityFactor: Value(week.intensityFactor),
              ),
            );

        final weekRows =
            doc.rows.where((r) => r.weekIndex == week.weekIndex).toList();
        final dayKeys = <(int, String), int>{}; // (dayOfWeek, name) → dayId
        for (final row in weekRows) {
          final key = (row.dayOfWeek, row.dayName);
          var dayId = dayKeys[key];
          if (dayId == null) {
            dayId = await _db.into(_db.programDays).insert(
                  ProgramDaysCompanion.insert(
                    programWeekId: weekId,
                    dayOfWeek: row.dayOfWeek,
                    name: row.dayName,
                  ),
                );
            dayKeys[key] = dayId;
          }
          final orderIndex =
              weekRows.where((r) => (r.dayOfWeek, r.dayName) == key).toList()
                  .indexOf(row);
          await _db.into(_db.programDayExercises).insert(
                ProgramDayExercisesCompanion.insert(
                  programDayId: dayId,
                  exerciseId:
                      resolved[row.exerciseName.toLowerCase()]!.id,
                  targetSets: Value(row.sets),
                  targetRepsMin: Value(row.repsMin),
                  targetRepsMax: Value(row.repsMax),
                  targetRpe: Value(row.rpe),
                  orderIndex: orderIndex,
                  setType: Value(row.setType),
                  percentOf1Rm: Value(row.percentOf1Rm),
                  equipmentVariant: Value(row.equipmentVariant),
                ),
              );
        }
      }

      return programId;
    });
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
