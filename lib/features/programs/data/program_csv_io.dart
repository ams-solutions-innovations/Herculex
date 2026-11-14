import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/program_csv.dart';

/// Database glue for program CSV import/export (V2 §12). The pure codec is
/// [ProgramCsv]; this resolves exercise names against the catalog (alias-
/// aware) and materializes weeks/days/exercises.
class ProgramCsvIo {
  final AppDatabase _db;
  final ProgramsRepository _programs;

  ProgramCsvIo(this._db) : _programs = ProgramsRepository(_db);

  Future<String> exportProgram(int programId) async {
    final program = await (_db.select(
      _db.programs,
    )..where((t) => t.id.equals(programId))).getSingle();
    final weeks =
        await (_db.select(_db.programWeeks)
              ..where((t) => t.programId.equals(programId))
              ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
            .get();

    final rows = <ProgramCsvRow>[];
    for (final week in weeks) {
      final days =
          await (_db.select(_db.programDays)
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
          final ex = await (_db.select(
            _db.exerciseCatalog,
          )..where((t) => t.id.equals(resolved.exerciseId))).getSingle();
          final pde = resolved.fromTemplate
              ? null
              : await (_db.select(_db.programDayExercises)
                      ..where(
                        (t) =>
                            t.programDayId.equals(day.id) &
                            t.exerciseId.equals(resolved.exerciseId),
                      )
                      ..limit(1))
                    .getSingleOrNull();
          rows.add(
            ProgramCsvRow(
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
              supersetGroup: pde?.supersetGroup,
              restSeconds: pde?.restSeconds,
              rir: pde?.targetRir,
              slotRole: pde == null || pde.slotRole == 'accessory'
                  ? null
                  : pde.slotRole,
              trainingMethod: pde == null || pde.trainingMethod == 'auto'
                  ? null
                  : pde.trainingMethod,
              notes: pde?.prescriptionWhy,
              gear: _allGear(pde?.variantConfigJson),
              durationSeconds:
                  _config(pde?.variantConfigJson)['target']?['durationSeconds']
                      as int?,
              distanceM:
                  (_config(pde?.variantConfigJson)['target']?['distanceM']
                          as num?)
                      ?.toDouble(),
              calories:
                  _config(pde?.variantConfigJson)['target']?['calories']
                      as int?,
              setMeta: {
                for (final e
                    in ((_config(pde?.variantConfigJson)['downSets'] as Map?) ??
                            const {})
                        .entries)
                  e.key as String: e.value as num,
              },
              tempo: _config(pde?.variantConfigJson)['tempo'] as String?,
              autoWarmups:
                  _config(pde?.variantConfigJson)['autoWarmups'] == true,
            ),
          );
        }
      }
    }

    return ProgramCsv.encode(
      ProgramCsvDocument(
        name: program.name,
        weeks: program.weeks,
        periodizationModel: program.periodizationModel,
        rows: rows,
      ),
    );
  }

  /// Switches optional gear on or off for every row of [programId]. Gear that
  /// is off stays recorded, so it can be switched back on later.
  Future<void> setProgramGear(int programId, Set<String> enabled) async {
    final weeks = await (_db.select(
      _db.programWeeks,
    )..where((t) => t.programId.equals(programId))).get();
    for (final week in weeks) {
      final days = await (_db.select(
        _db.programDays,
      )..where((t) => t.programWeekId.equals(week.id))).get();
      for (final day in days) {
        final rows = await (_db.select(
          _db.programDayExercises,
        )..where((t) => t.programDayId.equals(day.id))).get();
        for (final row in rows) {
          final all = _allGear(row.variantConfigJson);
          if (all.isEmpty) continue;
          Map<String, dynamic> config;
          try {
            config = jsonDecode(row.variantConfigJson!) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          final on = [
            for (final g in all)
              if (enabled.contains(g)) g,
          ];
          config['gear'] = on;
          final off = [
            for (final g in all)
              if (!on.contains(g)) g,
          ];
          if (off.isEmpty) {
            config.remove('gearOff');
          } else {
            config['gearOff'] = off;
          }
          await (_db.update(
            _db.programDayExercises,
          )..where((t) => t.id.equals(row.id))).write(
            ProgramDayExercisesCompanion(
              variantConfigJson: Value(jsonEncode(config)),
            ),
          );
        }
      }
    }
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
    Set<String>? enabledGear,
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
          .where(
            (e) =>
                e.aka != null &&
                e.aka!
                    .toLowerCase()
                    .split(',')
                    .map((a) => a.trim())
                    .contains(key),
          )
          .firstOrNull;
      if (ex == null) {
        missing.add(row.exerciseName);
      } else {
        resolved[key] = ex;
      }
    }
    if (missing.isNotEmpty) {
      throw ProgramCsvFormatException(
        'Unknown exercises: ${missing.join(', ')}',
      );
    }

    return _db.transaction(() async {
      final programId = await _db
          .into(_db.programs)
          .insert(
            ProgramsCompanion.insert(
              name: doc.name,
              description: Value(description),
              weeks: Value(doc.weeks),
              periodizationModel: Value(model.id),
              createdByUser: Value(createdByUser),
            ),
          );

      for (final week in plan) {
        final weekId = await _db
            .into(_db.programWeeks)
            .insert(
              ProgramWeeksCompanion.insert(
                programId: programId,
                weekIndex: week.weekIndex,
                adjustmentFactor: Value(week.volumeFactor),
                blockPhase: Value(week.blockPhase),
                intensityFactor: Value(week.intensityFactor),
              ),
            );

        final weekRows = doc.rows
            .where((r) => r.weekIndex == week.weekIndex)
            .toList();
        final dayKeys = <(int, String), int>{}; // (dayOfWeek, name) → dayId
        for (final row in weekRows) {
          final key = (row.dayOfWeek, row.dayName);
          var dayId = dayKeys[key];
          if (dayId == null) {
            dayId = await _db
                .into(_db.programDays)
                .insert(
                  ProgramDaysCompanion.insert(
                    programWeekId: weekId,
                    dayOfWeek: row.dayOfWeek,
                    name: row.dayName,
                  ),
                );
            dayKeys[key] = dayId;
          }
          final orderIndex = weekRows
              .where((r) => (r.dayOfWeek, r.dayName) == key)
              .toList()
              .indexOf(row);
          await _db
              .into(_db.programDayExercises)
              .insert(
                ProgramDayExercisesCompanion.insert(
                  programDayId: dayId,
                  exerciseId: resolved[row.exerciseName.toLowerCase()]!.id,
                  targetSets: Value(_effectiveSets(row)),
                  targetRepsMin: Value(row.repsMin),
                  targetRepsMax: Value(row.repsMax),
                  targetRpe: Value(row.rpe),
                  orderIndex: orderIndex,
                  setType: Value(row.setType),
                  percentOf1Rm: Value(row.percentOf1Rm),
                  equipmentVariant: Value(row.equipmentVariant),
                  supersetGroup: Value(row.supersetGroup),
                  restSeconds: Value(row.restSeconds),
                  targetRir: Value(row.rir),
                  slotRole: Value(row.slotRole ?? 'accessory'),
                  trainingMethod: Value(row.trainingMethod ?? 'auto'),
                  prescriptionWhy: Value(row.notes),
                  variantConfigJson: Value(_rowConfigJson(row, enabledGear)),
                ),
              );
        }
      }

      return programId;
    });
  }
}

/// Number of sets a row produces: a down set runs one set per step.
int _effectiveSets(ProgramCsvRow row) {
  final start = row.setMeta['startReps']?.toInt();
  if (row.setType != 'down_sets' || start == null || start <= 0) {
    return row.sets;
  }
  final step = (row.setMeta['decrement']?.toInt() ?? 1).clamp(1, 1000);
  return (start / step).ceil();
}

/// Everything the planner needs beyond the plain columns, as one JSON object:
/// gear (`gear` on, `gearOff` off), `autoWarmups`, `target` (time / distance /
/// calories), `downSets` and `tempo`. Null when a row has none of it.
String? _rowConfigJson(ProgramCsvRow row, Set<String>? enabled) {
  final on = [
    for (final g in row.gear)
      if (enabled == null || enabled.contains(g)) g,
  ];
  final off = [
    for (final g in row.gear)
      if (!on.contains(g)) g,
  ];
  final target = {
    if (row.durationSeconds != null) 'durationSeconds': row.durationSeconds,
    if (row.distanceM != null) 'distanceM': row.distanceM,
    if (row.calories != null) 'calories': row.calories,
  };
  final config = <String, Object?>{
    if (row.gear.isNotEmpty) 'gear': on,
    if (off.isNotEmpty) 'gearOff': off,
    if (row.autoWarmups) 'autoWarmups': true,
    if (target.isNotEmpty) 'target': target,
    if (row.setType == 'down_sets')
      'downSets': {
        'startReps': row.setMeta['startReps'],
        'decrement': row.setMeta['decrement'] ?? 1,
      },
    if (row.tempo != null) 'tempo': row.tempo,
  };
  return config.isEmpty ? null : jsonEncode(config);
}

Map<String, dynamic> _config(String? json) {
  if (json == null) return const {};
  try {
    return jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    return const {};
  }
}

List<String> _allGear(String? json) {
  if (json == null) return const [];
  try {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return [
      ...((m['gear'] as List?) ?? const []).cast<String>(),
      ...((m['gearOff'] as List?) ?? const []).cast<String>(),
    ];
  } catch (_) {
    return const [];
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
