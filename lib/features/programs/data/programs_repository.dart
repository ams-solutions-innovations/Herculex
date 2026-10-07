import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/schedule_walk.dart';
import 'package:herculex/features/programs/domain/scheduled_workout_row.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_prescription_codec.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/domain/wave_label.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

/// One exercise a program day will produce, from whichever source the day uses
/// (a linked template, or its own inline [ProgramDayExercises]).
class ResolvedExercise {
  const ResolvedExercise({
    required this.exerciseId,
    required this.orderIndex,
    required this.targetSets,
    this.targetRepsMin,
    this.targetRepsMax,
    this.fromTemplate = false,
  });

  final int exerciseId;
  final int orderIndex;
  final int targetSets;
  final int? targetRepsMin;
  final int? targetRepsMax;
  final bool fromTemplate;
}

/// How far an exercise choice should reach within a rotating program slot.
///
/// A wave is the contiguous run of weeks that currently uses the same
/// rotation assignment. This keeps a review-stage adjustment from silently
/// erasing the rest of a planned rotation.
enum ProgramExerciseReplacementScope {
  thisWave,
  thisAndFutureWaves,
  entireBlock,
}

class ProgramLiftProgress {
  const ProgramLiftProgress({required this.label, required this.e1RmKg});

  final String label;
  final double e1RmKg;
}

class ProgramDayExerciseSummary {
  const ProgramDayExerciseSummary({
    required this.id,
    required this.exerciseId,
    required this.name,
    required this.role,
    required this.method,
    required this.targetSets,
    this.targetRepsMin,
    this.targetRepsMax,
    this.why,
  });

  /// The underlying `ProgramDayExercises` row id — the target of a
  /// per-exercise replacement.
  final int id;

  /// The catalog exercise id currently filling this slot — used to resolve
  /// `current` for `ExerciseReplacementSheet`.
  final int exerciseId;
  final String name;
  final String role;
  final String method;
  final int targetSets;
  final int? targetRepsMin;
  final int? targetRepsMax;
  final String? why;

  String get targetLabel {
    final reps = switch ((targetRepsMin, targetRepsMax)) {
      (final int min, final int max) when min != max => '$min–$max',
      (final int min, _) => '$min',
      (_, final int max) => '$max',
      _ => '—',
    };
    return '$targetSets × $reps';
  }
}

class ProgramTrackingSnapshot {
  const ProgramTrackingSnapshot({
    required this.plannedSessions,
    required this.completedSessions,
    required this.skippedSessions,
    required this.currentWeekIndex,
    required this.qualitySets,
    required this.maxEffortTopSets,
    required this.exercisePrs,
    required this.movementFamilyTrends,
    this.phase,
    this.nextRotation,
  });

  final int plannedSessions;
  final int completedSessions;
  final int skippedSessions;
  final int currentWeekIndex;
  final String? phase;
  final int qualitySets;
  final int maxEffortTopSets;
  final List<ProgramLiftProgress> exercisePrs;
  final List<ProgramLiftProgress> movementFamilyTrends;
  final String? nextRotation;

  double get adherence => plannedSessions == 0
      ? 0
      : (completedSessions / plannedSessions).clamp(0, 1);
}

class ProgramsRepository {
  final AppDatabase _db;

  ProgramsRepository(this._db);

  Stream<List<ProgramDayExerciseSummary>> watchDayExerciseSummaries(
    int programDayId,
  ) {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.programDayExercises,
            _db.exerciseCatalog,
            _db.rotationAssignments,
          },
        )
        .watch()
        .asyncMap((_) async {
          final rows =
              await (_db.select(_db.programDayExercises)
                    ..where((t) => t.programDayId.equals(programDayId))
                    ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
                  .get();
          if (rows.isEmpty) return const <ProgramDayExerciseSummary>[];
          final ids = rows.map((row) => row.exerciseId).toSet();
          final catalog = await (_db.select(
            _db.exerciseCatalog,
          )..where((t) => t.id.isIn(ids))).get();
          final byId = {for (final exercise in catalog) exercise.id: exercise};
          return [
            for (final row in rows)
              ProgramDayExerciseSummary(
                id: row.id,
                exerciseId: row.exerciseId,
                name: byId[row.exerciseId]?.name ?? 'Unknown exercise',
                role: row.slotRole,
                method: row.trainingMethod,
                targetSets: row.targetSets,
                targetRepsMin: row.targetRepsMin,
                targetRepsMax: row.targetRepsMax,
                why: row.prescriptionWhy,
              ),
          ];
        });
  }

  Stream<ProgramTrackingSnapshot> watchProgramTracking(int programId) {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.scheduledWorkouts,
            _db.programDays,
            _db.programWeeks,
            _db.programExerciseSlots,
            _db.rotationAssignments,
            _db.workoutExercises,
            _db.setEntries,
            _db.exerciseCatalog,
          },
        )
        .watch()
        .asyncMap((_) => _loadProgramTracking(programId));
  }

  Future<ProgramTrackingSnapshot> _loadProgramTracking(int programId) async {
    final schedules =
        await (_db.select(_db.scheduledWorkouts)
              ..where((t) => t.programId.equals(programId))
              ..orderBy([(t) => OrderingTerm(expression: t.dateIso)]))
            .get();
    final completed = schedules
        .where((row) => row.status == ScheduleStatus.done)
        .length;
    final skipped = schedules
        .where((row) => row.status == ScheduleStatus.skipped)
        .length;
    final today = _formatDateIso(_todayDate());
    final currentSchedule = schedules.firstWhere(
      (row) =>
          row.dateIso.compareTo(today) >= 0 &&
          row.status != ScheduleStatus.skipped,
      orElse: () => schedules.lastOrNull ?? _emptySchedule,
    );

    ProgramWeekData? currentWeek;
    if (currentSchedule.id != -1) {
      final day =
          await (_db.select(_db.programDays)
                ..where((t) => t.id.equals(currentSchedule.programDayId)))
              .getSingleOrNull();
      if (day != null) {
        currentWeek = await (_db.select(
          _db.programWeeks,
        )..where((t) => t.id.equals(day.programWeekId))).getSingleOrNull();
      }
    }
    currentWeek ??=
        await (_db.select(_db.programWeeks)
              ..where((t) => t.programId.equals(programId))
              ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)])
              ..limit(1))
            .getSingleOrNull();

    final sessionIds = schedules
        .map((row) => row.completedSessionId)
        .whereType<int>()
        .toSet();
    final workoutExercises = sessionIds.isEmpty
        ? const <WorkoutExerciseData>[]
        : await (_db.select(
            _db.workoutExercises,
          )..where((t) => t.sessionId.isIn(sessionIds))).get();
    final workoutExerciseIds = workoutExercises.map((row) => row.id).toSet();
    final sets = workoutExerciseIds.isEmpty
        ? const <SetEntryData>[]
        : await (_db.select(_db.setEntries)..where(
                (t) =>
                    t.workoutExerciseId.isIn(workoutExerciseIds) &
                    t.isCompleted.equals(true) &
                    t.isWarmup.equals(false),
              ))
              .get();
    final exerciseIds = workoutExercises.map((row) => row.exerciseId).toSet();
    final catalog = exerciseIds.isEmpty
        ? const <ExerciseCatalogData>[]
        : await (_db.select(
            _db.exerciseCatalog,
          )..where((t) => t.id.isIn(exerciseIds))).get();
    final exerciseById = {for (final row in catalog) row.id: row};
    final workoutExerciseById = {
      for (final row in workoutExercises) row.id: row,
    };
    final bestByExercise = <int, double>{};
    final bestByFamily = <String, double>{};
    var qualitySets = 0;
    var maxEffortTopSets = 0;
    for (final set in sets) {
      final exercise = workoutExerciseById[set.workoutExerciseId];
      if (exercise == null) continue;
      final targetMet =
          (set.plannedRepsMin == null || set.reps >= set.plannedRepsMin!) &&
          (set.plannedRpeX10 == null ||
              set.rpeX10 == null ||
              set.rpeX10! <= set.plannedRpeX10! + 5);
      if (targetMet) qualitySets++;
      if (exercise.plannedTrainingMethod == 'max_effort' &&
          set.plannedIntent == 'ramp_to_max') {
        maxEffortTopSets++;
      }
      if (set.weightKg <= 0 || set.reps <= 0) continue;
      final e1Rm = set.weightKg * (1 + set.reps / 30);
      bestByExercise.update(
        exercise.exerciseId,
        (value) => value > e1Rm ? value : e1Rm,
        ifAbsent: () => e1Rm,
      );
      final family = exerciseById[exercise.exerciseId]?.movementFamily;
      if (family != null && family.isNotEmpty) {
        bestByFamily.update(
          family,
          (value) => value > e1Rm ? value : e1Rm,
          ifAbsent: () => e1Rm,
        );
      }
    }

    List<ProgramLiftProgress> sortedProgress(Map<String, double> values) {
      final result = [
        for (final entry in values.entries)
          ProgramLiftProgress(label: entry.key, e1RmKg: entry.value),
      ]..sort((a, b) => b.e1RmKg.compareTo(a.e1RmKg));
      return result.take(3).toList(growable: false);
    }

    final exerciseProgress = <String, double>{};
    for (final entry in bestByExercise.entries) {
      exerciseProgress[exerciseById[entry.key]?.name ?? 'Exercise'] =
          entry.value;
    }

    String? nextRotation;
    final slots = await (_db.select(
      _db.programExerciseSlots,
    )..where((t) => t.programId.equals(programId))).get();
    if (slots.isNotEmpty) {
      final slotIds = slots.map((slot) => slot.id).toSet();
      final assignments =
          await (_db.select(_db.rotationAssignments)
                ..where((t) => t.slotId.isIn(slotIds))
                ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
              .get();
      final currentIndex = currentWeek?.weekIndex ?? 0;
      RotationAssignmentData? nearest;
      for (final slot in slots) {
        final rows = assignments
            .where((assignment) => assignment.slotId == slot.id)
            .toList(growable: false);
        final active = rows.lastWhere(
          (assignment) => assignment.weekIndex <= currentIndex,
          orElse: () => rows.firstOrNull ?? _emptyAssignment,
        );
        if (active.id == -1) continue;
        for (final candidate in rows) {
          if (candidate.weekIndex > currentIndex &&
              candidate.exerciseId != active.exerciseId &&
              (nearest == null || candidate.weekIndex < nearest.weekIndex)) {
            nearest = candidate;
            break;
          }
        }
      }
      if (nearest != null) {
        var exercise = exerciseById[nearest.exerciseId];
        exercise ??= await (_db.select(
          _db.exerciseCatalog,
        )..where((t) => t.id.equals(nearest!.exerciseId))).getSingleOrNull();
        nextRotation =
            'Week ${nearest.weekIndex + 1} · ${exercise?.name ?? 'planned variation'}';
      }
    }

    return ProgramTrackingSnapshot(
      plannedSessions: schedules.length,
      completedSessions: completed,
      skippedSessions: skipped,
      currentWeekIndex: currentWeek?.weekIndex ?? 0,
      phase: currentWeek?.blockPhase,
      qualitySets: qualitySets,
      maxEffortTopSets: maxEffortTopSets,
      exercisePrs: sortedProgress(exerciseProgress),
      movementFamilyTrends: sortedProgress(bestByFamily),
      nextRotation: nextRotation,
    );
  }

  static final _emptySchedule = ScheduledWorkoutData(
    id: -1,
    syncUuid: null,
    updatedAt: null,
    syncedAt: null,
    deletedAt: null,
    dateIso: '',
    programDayId: -1,
    completedSessionId: null,
    status: ScheduleStatus.planned,
    programId: null,
    orderIndex: 0,
    occurrenceIndex: 0,
    templateIdOverride: null,
    startTimeMinutes: null,
  );

  static final _emptyAssignment = RotationAssignmentData(
    syncUuid: null,
    updatedAt: null,
    syncedAt: null,
    deletedAt: null,
    id: -1,
    slotId: -1,
    exerciseId: -1,
    weekIndex: -1,
    source: 'planned',
    reason: '',
    variantConfigJson: null,
  );

  // ── Template CRUD ────────────────────────────────────────────────────────

  Future<int> createProgram({
    required String name,
    required String? description,
    required int weeks,
    required String type, // rotating | block
    required String progressionStrategy, // volume | intensity | dynamic
    String?
    periodizationModel, // none | linear | concurrent | block | max_effort
    SplitType splitType = SplitType.custom,
    ScheduleMode scheduleMode = ScheduleMode.weekly,
    int? cycleLength,
    int? daysPerWeek,
  }) async {
    return _db.transaction(() async {
      final model = PeriodizationModel.fromId(periodizationModel);
      final programId = await _db
          .into(_db.programs)
          .insert(
            ProgramsCompanion.insert(
              name: name,
              description: Value(description),
              weeks: Value(weeks),
              type: Value(type),
              progressionStrategy: Value(progressionStrategy),
              periodizationModel: Value(model.id),
              createdByUser: const Value(true),
              archived: const Value(false),
              splitType: Value(splitType.id),
              scheduleMode: Value(scheduleMode.id),
              cycleLength: Value(cycleLength),
              daysPerWeek: Value(daysPerWeek),
            ),
          );

      await _insertPeriodizedWeeks(programId, model, weeks, type);
      return programId;
    });
  }

  /// Creates a program and its whole weekly skeleton from a generated
  /// [SplitPlan], attaching one template per split slot, then materializes it.
  ///
  /// This replaces the old builder path, which wrote a raw display string into
  /// `ProgramDays.name` and never attached any content — so every block built
  /// in-app produced empty sessions.
  Future<int> createProgramFromSplit({
    required String name,
    String? description,
    required int weeks,
    required SplitPlan plan,
    required DateTime startDate,
    String? periodizationModel,
    String progressionStrategy = 'volume',

    /// Template id per `SplitDaySpec.slotIndex`; a missing or null entry leaves
    /// the day empty for inline exercises.
    Map<int, int?> templateIdsBySlot = const {},
    bool activate = true,
    bool archived = false,
    bool materialize = true,
    int? defaultStartTimeMinutes,
    ProgramBuildMode buildMode = ProgramBuildMode.manual,
    TrainingGoal trainingGoal = TrainingGoal.hypertrophy,
    ExperienceLevel experienceLevel = ExperienceLevel.intermediate,
    AdaptationMode adaptationMode = AdaptationMode.reviewStructural,
  }) async {
    final programId = await _db.transaction(() async {
      final model = PeriodizationModel.fromId(periodizationModel);
      final id = await _db
          .into(_db.programs)
          .insert(
            ProgramsCompanion.insert(
              name: name,
              description: Value(description),
              weeks: Value(weeks),
              type: const Value('block'),
              progressionStrategy: Value(progressionStrategy),
              periodizationModel: Value(model.id),
              createdByUser: const Value(true),
              archived: Value(archived),
              splitType: Value(plan.type.id),
              scheduleMode: Value(plan.mode.id),
              cycleLength: Value(
                plan.mode == ScheduleMode.cycle ? plan.cycleLength : null,
              ),
              daysPerWeek: Value(plan.trainingDayCount),
              startDateIso: Value(_formatDateIso(startDate)),
              buildMode: Value(buildMode.id),
              trainingGoal: Value(trainingGoal.id),
              experienceLevel: Value(experienceLevel.id),
              adaptationMode: Value(adaptationMode.id),
            ),
          );

      final weekIds = await _insertPeriodizedWeeks(id, model, weeks, 'block');

      // The skeleton is written once per week so each week can later be edited
      // independently (swap a template, add a day) without touching the others.
      for (final weekId in weekIds) {
        var order = 0;
        for (final spec in plan.days) {
          if (spec.isRest) continue;
          await _insertProgramDay(
            programWeekId: weekId,
            dayOfWeek: spec.dayOfWeek,
            name: spec.label,
            slotLabel: spec.label,
            orderIndex: order++,
            templateId: templateIdsBySlot[spec.slotIndex],
            cycleDayIndex: plan.mode == ScheduleMode.cycle ? spec.index : null,
            startTimeMinutes: defaultStartTimeMinutes,
          );
        }
      }
      return id;
    });

    if (activate) await setActiveProgram(programId);
    if (materialize) await materializeProgram(programId, startDate);
    return programId;
  }

  Future<List<int>> _insertPeriodizedWeeks(
    int programId,
    PeriodizationModel model,
    int weeks,
    String type,
  ) async {
    final totalWeeks = type == 'rotating' ? 1 : weeks;
    final prescriptions = Periodization.plan(model, totalWeeks);
    final ids = <int>[];
    for (int i = 0; i < totalWeeks; i++) {
      final p = prescriptions[i];
      ids.add(
        await _db
            .into(_db.programWeeks)
            .insert(
              ProgramWeeksCompanion.insert(
                programId: programId,
                weekIndex: i,
                adjustmentFactor: Value(p.volumeFactor),
                intensityFactor: Value(p.intensityFactor),
                blockPhase: Value(p.blockPhase),
              ),
            ),
      );
    }
    return ids;
  }

  Future<List<ProgramData>> getActivePrograms() {
    return (_db.select(_db.programs)
          ..where((t) => t.archived.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
  }

  Stream<List<ProgramData>> watchPrograms() {
    return (_db.select(_db.programs)
          ..where((t) => t.archived.equals(false))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.isActive, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.name),
          ]))
        .watch();
  }

  Stream<ProgramData?> watchActiveProgram() {
    return (_db.select(_db.programs)
          ..where((t) => t.archived.equals(false) & t.isActive.equals(true))
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<ProgramData?> getProgram(int id) {
    return (_db.select(
      _db.programs,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Makes [programId] the block shown in the Blocks tab. The single-active
  /// invariant lives here and nowhere else — never write `Programs.isActive`
  /// directly.
  Future<void> setActiveProgram(int programId) async {
    await _db.transaction(() async {
      await _db
          .update(_db.programs)
          .write(const ProgramsCompanion(isActive: Value(false)));
      await (_db.update(_db.programs)..where((t) => t.id.equals(programId)))
          .write(const ProgramsCompanion(isActive: Value(true)));
    });
  }

  Future<void> archiveProgram(int programId, {bool archived = true}) async {
    await (_db.update(
      _db.programs,
    )..where((t) => t.id.equals(programId))).write(
      ProgramsCompanion(
        archived: Value(archived),
        // An archived block can never be the active one.
        isActive: archived ? const Value(false) : const Value.absent(),
      ),
    );
  }

  Future<void> deleteProgram(int programId) async {
    await _db.transaction(() async {
      final weekIds =
          (await (_db.select(
                _db.programWeeks,
              )..where((t) => t.programId.equals(programId))).get())
              .map((w) => w.id)
              .toList();

      final dayIds = weekIds.isEmpty
          ? <int>[]
          : (await (_db.select(
                  _db.programDays,
                )..where((t) => t.programWeekId.isIn(weekIds))).get())
                .map((d) => d.id)
                .toList();

      if (dayIds.isNotEmpty) {
        await (_db.delete(
          _db.programDayExercises,
        )..where((t) => t.programDayId.isIn(dayIds))).go();
      }

      // scheduled_workouts has two independent CASCADE edges into this tree
      // (program_id and program_day_id) — both must be swept.
      await (_db.delete(_db.scheduledWorkouts)..where(
            (t) => dayIds.isEmpty
                ? t.programId.equals(programId)
                : t.programId.equals(programId) | t.programDayId.isIn(dayIds),
          ))
          .go();

      if (dayIds.isNotEmpty) {
        await (_db.delete(
          _db.programDays,
        )..where((t) => t.id.isIn(dayIds))).go();
      }
      if (weekIds.isNotEmpty) {
        await (_db.delete(
          _db.programWeeks,
        )..where((t) => t.id.isIn(weekIds))).go();
      }
      await (_db.delete(
        _db.programs,
      )..where((t) => t.id.equals(programId))).go();
    });
  }

  Future<List<ProgramWeekData>> getProgramWeeks(int programId) {
    return (_db.select(_db.programWeeks)
          ..where((t) => t.programId.equals(programId))
          ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
        .get();
  }

  Stream<List<ProgramWeekData>> watchProgramWeeks(int programId) {
    return (_db.select(_db.programWeeks)
          ..where((t) => t.programId.equals(programId))
          ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
        .watch();
  }

  Future<List<ProgramDayData>> getProgramDaysForWeek(int weekId) {
    return (_db.select(_db.programDays)
          ..where((t) => t.programWeekId.equals(weekId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.cycleDayIndex),
            (t) => OrderingTerm(expression: t.dayOfWeek),
            (t) => OrderingTerm(expression: t.orderIndex),
          ]))
        .get();
  }

  /// D-05's "Exercise wave X of Y · Weeks A–B" indicator for one viewed week.
  ///
  /// Resolves the week's anchor `main` slot ([WaveLabel.selectAnchorSlot]),
  /// then walks its [RotationAssignments] across every week to derive the
  /// current wave via [WaveLabel.compute]. Returns `null` when the week has
  /// no anchor `main` slot at all — the wave-strip line is omitted entirely
  /// in that case, never rendered with a misleading default.
  Future<WaveLabelInfo?> getWaveLabelInfo({
    required int programId,
    required int programWeekId,
    required int weekIndex,
    required int totalWeeks,
  }) async {
    final days = await getProgramDaysForWeek(programWeekId);
    final allSlots = await (_db.select(
      _db.programExerciseSlots,
    )..where((t) => t.programId.equals(programId))).get();
    final anchor = WaveLabel.selectAnchorSlot(
      daysInOrder: days,
      allSlots: allSlots,
    );
    if (anchor == null) return null;

    final assignments = await (_db.select(
      _db.rotationAssignments,
    )..where((t) => t.slotId.equals(anchor.id))).get();
    final exerciseIdByWeek = <int, int?>{
      for (final assignment in assignments)
        assignment.weekIndex: assignment.exerciseId,
    };
    return WaveLabel.compute(
      totalWeeks: totalWeeks,
      currentWeekIndex: weekIndex,
      exerciseIdByWeek: exerciseIdByWeek,
    );
  }

  Stream<List<ProgramDayData>> watchProgramDaysForWeek(int weekId) {
    return (_db.select(_db.programDays)
          ..where((t) => t.programWeekId.equals(weekId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.cycleDayIndex),
            (t) => OrderingTerm(expression: t.dayOfWeek),
            (t) => OrderingTerm(expression: t.orderIndex),
          ]))
        .watch();
  }

  /// The one write path for program days, so the `dayOfWeek` filler convention
  /// for cycle programs is applied in exactly one place.
  Future<int> addProgramDay({
    required int programWeekId,
    required int dayOfWeek,
    required String name,
    String? slotLabel,
    int? templateId,
    int? cycleDayIndex,
    bool isRest = false,
    int? orderIndex,
    int? startTimeMinutes,
  }) async {
    final order =
        orderIndex ??
        await _nextProgramDayOrder(programWeekId, dayOfWeek, cycleDayIndex);
    return _insertProgramDay(
      programWeekId: programWeekId,
      dayOfWeek: dayOfWeek,
      name: name,
      slotLabel: slotLabel,
      templateId: templateId,
      cycleDayIndex: cycleDayIndex,
      isRest: isRest,
      orderIndex: order,
      startTimeMinutes: startTimeMinutes,
    );
  }

  Future<int> _insertProgramDay({
    required int programWeekId,
    required int dayOfWeek,
    required String name,
    String? slotLabel,
    int? templateId,
    int? cycleDayIndex,
    bool isRest = false,
    required int orderIndex,
    int? startTimeMinutes,
  }) {
    // For cycle programs `cycleDayIndex` is authoritative and `dayOfWeek` is a
    // filler the NOT NULL column demands — see the note on ProgramDays.
    final storedDayOfWeek = cycleDayIndex != null
        ? (cycleDayIndex % 7) + 1
        : dayOfWeek;
    return _db
        .into(_db.programDays)
        .insert(
          ProgramDaysCompanion.insert(
            programWeekId: programWeekId,
            dayOfWeek: storedDayOfWeek,
            name: name,
            slotLabel: Value(slotLabel ?? name),
            templateId: Value(templateId),
            cycleDayIndex: Value(cycleDayIndex),
            isRest: Value(isRest),
            orderIndex: Value(orderIndex),
            startTimeMinutes: Value(startTimeMinutes),
          ),
        );
  }

  Future<int> _nextProgramDayOrder(
    int programWeekId,
    int dayOfWeek,
    int? cycleDayIndex,
  ) async {
    final rows =
        await (_db.select(_db.programDays)..where(
              (t) =>
                  t.programWeekId.equals(programWeekId) &
                  (cycleDayIndex != null
                      ? t.cycleDayIndex.equals(cycleDayIndex)
                      : t.dayOfWeek.equals(dayOfWeek)),
            ))
            .get();
    return rows.length;
  }

  Future<void> updateProgramDay(
    int programDayId, {
    String? name,
    String? slotLabel,
  }) async {
    await (_db.update(
      _db.programDays,
    )..where((t) => t.id.equals(programDayId))).write(
      ProgramDaysCompanion(
        name: name == null ? const Value.absent() : Value(name),
        slotLabel: slotLabel == null ? const Value.absent() : Value(slotLabel),
      ),
    );
  }

  Future<void> deleteProgramDay(int programDayId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.programDayExercises,
      )..where((t) => t.programDayId.equals(programDayId))).go();
      await (_db.delete(
        _db.scheduledWorkouts,
      )..where((t) => t.programDayId.equals(programDayId))).go();
      await (_db.delete(
        _db.programDays,
      )..where((t) => t.id.equals(programDayId))).go();
    });
  }

  /// Links (or unlinks with null) the live template a program day generates its
  /// sessions from. Callers must follow this with [rematerializeProgram] so
  /// future scheduled rows pick the change up.
  Future<void> setProgramDayTemplate(int programDayId, int? templateId) async {
    await (_db.update(_db.programDays)..where((t) => t.id.equals(programDayId)))
        .write(ProgramDaysCompanion(templateId: Value(templateId)));
  }

  /// Swaps the template for one scheduled occurrence only.
  Future<void> setScheduleTemplateOverride(
    int scheduleId,
    int? templateId,
  ) async {
    await (_db.update(
      _db.scheduledWorkouts,
    )..where((t) => t.id.equals(scheduleId))).write(
      ScheduledWorkoutsCompanion(templateIdOverride: Value(templateId)),
    );
  }

  /// Sets the day's default start time. Callers that want this to reach
  /// already-materialized future sessions must follow with
  /// [rematerializeProgram] — same two-step pattern as
  /// [setProgramDayTemplate].
  Future<void> setProgramDayStartTime(
    int programDayId,
    int? startTimeMinutes,
  ) async {
    await (_db.update(_db.programDays)..where((t) => t.id.equals(programDayId)))
        .write(ProgramDaysCompanion(startTimeMinutes: Value(startTimeMinutes)));
  }

  /// Sets this one occurrence's start time, independent of the day's
  /// default.
  Future<void> setScheduleStartTime(
    int scheduleId,
    int? startTimeMinutes,
  ) async {
    await (_db.update(
      _db.scheduledWorkouts,
    )..where((t) => t.id.equals(scheduleId))).write(
      ScheduledWorkoutsCompanion(startTimeMinutes: Value(startTimeMinutes)),
    );
  }

  Future<void> setWeekAdjustment(
    int programWeekId, {
    double? adjustmentFactor,
    double? intensityFactor,
  }) async {
    await (_db.update(
      _db.programWeeks,
    )..where((t) => t.id.equals(programWeekId))).write(
      ProgramWeeksCompanion(
        adjustmentFactor: adjustmentFactor == null
            ? const Value.absent()
            : Value(adjustmentFactor),
        intensityFactor: intensityFactor == null
            ? const Value.absent()
            : Value(intensityFactor),
      ),
    );
  }

  Future<int> addExerciseToProgramDay({
    required int programDayId,
    required int exerciseId,
    required int targetSets,
    int? targetRepsMin,
    int? targetRepsMax,
    int? targetRpe,
    required int orderIndex,
  }) {
    return _db
        .into(_db.programDayExercises)
        .insert(
          ProgramDayExercisesCompanion.insert(
            programDayId: programDayId,
            exerciseId: exerciseId,
            targetSets: Value(targetSets),
            targetRepsMin: Value(targetRepsMin),
            targetRepsMax: Value(targetRepsMax),
            targetRpe: Value(targetRpe),
            orderIndex: orderIndex,
          ),
        );
  }

  Future<List<ProgramDayExerciseData>> getExercisesForDay(int programDayId) {
    return (_db.select(_db.programDayExercises)
          ..where((t) => t.programDayId.equals(programDayId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
  }

  /// Applies a review-stage exercise replacement at the requested [scope].
  ///
  /// A stable slot is shared by every week, but its assignments are not: the
  /// default [ProgramExerciseReplacementScope.thisWave] changes only the
  /// contiguous wave containing [programDayExerciseId]. This preserves the
  /// later planned variations. Program-day blueprints are updated alongside
  /// the assignments; already-created workout sessions are deliberately not
  /// touched here.
  Future<void> replaceProgramExerciseSlot({
    required int programDayExerciseId,
    required int replacementExerciseId,
    ProgramExerciseReplacementScope scope =
        ProgramExerciseReplacementScope.thisWave,
  }) async {
    final original = await (_db.select(
      _db.programDayExercises,
    )..where((t) => t.id.equals(programDayExerciseId))).getSingleOrNull();
    if (original == null || original.exerciseId == replacementExerciseId) {
      return;
    }

    final originalDay = await (_db.select(
      _db.programDays,
    )..where((t) => t.id.equals(original.programDayId))).getSingleOrNull();
    if (originalDay == null) return;
    final originalWeek = await (_db.select(
      _db.programWeeks,
    )..where((t) => t.id.equals(originalDay.programWeekId))).getSingleOrNull();
    if (originalWeek == null) return;

    await _db.transaction(() async {
      final slotId = original.programExerciseSlotId;
      if (slotId == null) {
        await (_db.update(
          _db.programDayExercises,
        )..where((t) => t.id.equals(programDayExerciseId))).write(
          ProgramDayExercisesCompanion(
            exerciseId: Value(replacementExerciseId),
            equipmentVariant: const Value(null),
          ),
        );
        return;
      }

      final slot = await (_db.select(
        _db.programExerciseSlots,
      )..where((t) => t.id.equals(slotId))).getSingleOrNull();
      if (slot == null) return;
      final weeks =
          await (_db.select(_db.programWeeks)
                ..where((t) => t.programId.equals(slot.programId))
                ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
              .get();
      if (weeks.isEmpty) return;
      final assignments =
          await (_db.select(_db.rotationAssignments)
                ..where((t) => t.slotId.equals(slotId))
                ..orderBy([(t) => OrderingTerm(expression: t.weekIndex)]))
              .get();
      final assignmentByWeek = {
        for (final assignment in assignments) assignment.weekIndex: assignment,
      };
      final allWeekIndices = weeks.map((week) => week.weekIndex).toList();
      final activeExerciseId =
          assignmentByWeek[originalWeek.weekIndex]?.exerciseId ??
          original.exerciseId;
      var waveStart = originalWeek.weekIndex;
      var waveEnd = originalWeek.weekIndex;
      while (assignmentByWeek[waveStart - 1]?.exerciseId == activeExerciseId) {
        waveStart--;
      }
      while (assignmentByWeek[waveEnd + 1]?.exerciseId == activeExerciseId) {
        waveEnd++;
      }
      final targetWeekIndices = switch (scope) {
        ProgramExerciseReplacementScope.thisWave => [
          for (final week in allWeekIndices)
            if (week >= waveStart && week <= waveEnd) week,
        ],
        ProgramExerciseReplacementScope.thisAndFutureWaves => [
          for (final week in allWeekIndices)
            if (week >= waveStart) week,
        ],
        ProgramExerciseReplacementScope.entireBlock => allWeekIndices,
      };
      final targetWeekIds = [
        for (final week in weeks)
          if (targetWeekIndices.contains(week.weekIndex)) week.id,
      ];
      final targetDayIds = targetWeekIds.isEmpty
          ? <int>[]
          : (await (_db.select(
                  _db.programDays,
                )..where((t) => t.programWeekId.isIn(targetWeekIds))).get())
                .map((day) => day.id)
                .toList();

      await (_db.update(_db.programDayExercises)..where(
            (t) =>
                t.programExerciseSlotId.equals(slotId) &
                t.programDayId.isIn(targetDayIds),
          ))
          .write(
            ProgramDayExercisesCompanion(
              exerciseId: Value(replacementExerciseId),
              // A variant belongs to the original choice. A review replacement
              // starts with the selected catalog exercise's default, so
              // "weighted" is never carried onto a barbell or machine movement.
              equipmentVariant: const Value(null),
            ),
          );
      await (_db.update(_db.programExerciseSlots)
            ..where((t) => t.id.equals(slotId)))
          .write(const ProgramExerciseSlotsCompanion(userLocked: Value(true)));

      await (_db.update(_db.programSlotPoolMembers)
            ..where((t) => t.slotId.equals(slotId)))
          .write(const ProgramSlotPoolMembersCompanion(pinned: Value(false)));
      final member =
          await (_db.select(_db.programSlotPoolMembers)..where(
                (t) =>
                    t.slotId.equals(slotId) &
                    t.exerciseId.equals(replacementExerciseId),
              ))
              .getSingleOrNull();
      if (member == null) {
        await _db
            .into(_db.programSlotPoolMembers)
            .insert(
              ProgramSlotPoolMembersCompanion.insert(
                slotId: slotId,
                exerciseId: replacementExerciseId,
                orderIndex: const Value(0),
                pinned: const Value(true),
              ),
            );
      } else {
        await (_db.update(
          _db.programSlotPoolMembers,
        )..where((t) => t.id.equals(member.id))).write(
          const ProgramSlotPoolMembersCompanion(
            orderIndex: Value(0),
            pinned: Value(true),
          ),
        );
      }

      // This is an explicit pre-approval choice, not a random rotation. Only
      // update the assignments covered by the selected scope; later waves
      // retain their planned variations unless the user explicitly includes
      // them.
      await (_db.update(_db.rotationAssignments)..where(
            (t) =>
                t.slotId.equals(slotId) & t.weekIndex.isIn(targetWeekIndices),
          ))
          .write(
            RotationAssignmentsCompanion(
              exerciseId: Value(replacementExerciseId),
              source: const Value('user'),
              reason: Value(
                'Chosen during plan review (${_replacementScopeReason(scope)}).',
              ),
            ),
          );
    });
  }

  static String _replacementScopeReason(
    ProgramExerciseReplacementScope scope,
  ) => switch (scope) {
    ProgramExerciseReplacementScope.thisWave => 'this wave',
    ProgramExerciseReplacementScope.thisAndFutureWaves =>
      'this and future waves',
    ProgramExerciseReplacementScope.entireBlock => 'entire block',
  };

  // ── Content resolution ───────────────────────────────────────────────────

  /// Converts every linked workout template in a newly-created program into
  /// an owned inline blueprint. Legacy programs keep their live links because
  /// this is only called explicitly by the new builder.
  Future<void> snapshotLinkedTemplates(int programId) async {
    final weeks = await (_db.select(
      _db.programWeeks,
    )..where((t) => t.programId.equals(programId))).get();
    if (weeks.isEmpty) return;
    final weekIds = weeks.map((week) => week.id).toList(growable: false);
    final days =
        await (_db.select(_db.programDays)..where(
              (t) => t.programWeekId.isIn(weekIds) & t.templateId.isNotNull(),
            ))
            .get();

    await _db.transaction(() async {
      for (final day in days) {
        final templateId = day.templateId!;
        final template = await (_db.select(
          _db.workoutTemplates,
        )..where((t) => t.id.equals(templateId))).getSingleOrNull();
        final exercises =
            await (_db.select(_db.templateExercises)
                  ..where((t) => t.templateId.equals(templateId))
                  ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
                .get();

        await (_db.delete(
          _db.programDayExercises,
        )..where((t) => t.programDayId.equals(day.id))).go();
        for (final exercise in exercises) {
          final sets =
              await (_db.select(_db.templateSets)
                    ..where((t) => t.templateExerciseId.equals(exercise.id))
                    ..orderBy([(t) => OrderingTerm(expression: t.setOrder)]))
                  .get();
          final copiedSets = [
            for (final set in sets)
              <String, Object?>{
                'setOrder': set.setOrder,
                'setType': set.setType,
                'setTypeMetaJson': set.setTypeMetaJson,
                'targetReps': set.targetReps,
                'targetRepsMin': set.targetRepsMin,
                'targetRepsMax': set.targetRepsMax,
                'targetWeightKg': set.targetWeightKg,
                'isWarmup': set.isWarmup,
              },
          ];
          // The prescription codec (Phase 18, PRES-01) has no field for a
          // literal per-set target weight or an isWarmup flag — it describes
          // reps/intent/%1RM archetypes, not a copied workout-template blob.
          // Non-warmup sets survive the freeze as one segment each (sets: 1)
          // so the exact rep target and set type is still immutable against
          // future template edits; warmup sets are dropped here since
          // automatic warmup computation (WarmupResolver) now owns that.
          final workingTemplateSets = sets
              .where((set) => !set.isWarmup)
              .toList(growable: false);
          final codecPrescription = workingTemplateSets.isEmpty
              ? null
              : SlotPrescription(
                  name: 'Copied template',
                  segments: [
                    for (final set in workingTemplateSets)
                      WorkSegment(
                        sets: 1,
                        repsMin:
                            set.targetRepsMin ??
                            set.targetReps ??
                            exercise.targetRepsMin ??
                            8,
                        repsMax:
                            set.targetRepsMax ??
                            set.targetReps ??
                            set.targetRepsMin ??
                            exercise.targetRepsMax ??
                            exercise.targetRepsMin,
                        setType: SetType.fromId(set.setType),
                      ),
                  ],
                );
          await _db
              .into(_db.programDayExercises)
              .insert(
                ProgramDayExercisesCompanion.insert(
                  programDayId: day.id,
                  exerciseId: exercise.exerciseId,
                  orderIndex: exercise.orderIndex,
                  targetSets: Value(
                    sets.isEmpty ? exercise.targetSets : sets.length,
                  ),
                  targetRepsMin: Value(exercise.targetRepsMin),
                  targetRepsMax: Value(exercise.targetRepsMax),
                  restSeconds: Value(exercise.targetRestSeconds),
                  slotRole: const Value('accessory'),
                  trainingMethod: const Value('straight_sets'),
                  prescriptionWhy: Value(
                    'Copied from "${template?.name ?? 'workout template'}" when this program was created.',
                  ),
                  prescriptionJson: copiedSets.isEmpty
                      ? const Value.absent()
                      : Value(jsonEncode({'templateSets': copiedSets})),
                  prescriptionCodecJson: codecPrescription == null
                      ? const Value.absent()
                      : Value(SlotPrescriptionCodec.encode(codecPrescription)),
                ),
              );
        }
        await (_db.update(_db.programDays)..where((t) => t.id.equals(day.id)))
            .write(const ProgramDaysCompanion(templateId: Value(null)));
      }
    });
  }

  /// The exercises a program day will produce, from its linked template or its
  /// inline rows.
  ///
  /// Every consumer must go through here. Reading `ProgramDayExercises`
  /// directly makes template-linked days look empty, which is how conflict
  /// detection, exercise counts and CSV export silently break.
  Future<List<ResolvedExercise>> resolveDayExercises(
    int programDayId, {
    int? templateOverride,
  }) async {
    var templateId = templateOverride;
    if (templateId == null) {
      final day = await (_db.select(
        _db.programDays,
      )..where((t) => t.id.equals(programDayId))).getSingleOrNull();
      templateId = day?.templateId;
    }

    if (templateId != null) {
      final rows =
          await (_db.select(_db.templateExercises)
                ..where((t) => t.templateId.equals(templateId!))
                ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
              .get();
      return [
        for (final r in rows)
          ResolvedExercise(
            exerciseId: r.exerciseId,
            orderIndex: r.orderIndex,
            targetSets: r.targetSets,
            targetRepsMin: r.targetRepsMin,
            targetRepsMax: r.targetRepsMax,
            fromTemplate: true,
          ),
      ];
    }

    final rows = await getExercisesForDay(programDayId);
    return [
      for (final r in rows)
        ResolvedExercise(
          exerciseId: r.exerciseId,
          orderIndex: r.orderIndex,
          targetSets: r.targetSets,
          targetRepsMin: r.targetRepsMin,
          targetRepsMax: r.targetRepsMax,
        ),
    ];
  }

  Future<int> countDayExercises(
    int programDayId, {
    int? templateOverride,
  }) async {
    final resolved = await resolveDayExercises(
      programDayId,
      templateOverride: templateOverride,
    );
    return resolved.length;
  }

  // ── Scheduler Engine ─────────────────────────────────────────────────────

  /// Generates scheduled workouts for [programId] starting at [startDate].
  ///
  /// Only this program's untouched `planned` rows are replaced. Anything the
  /// user has acted on — started, completed, moved or skipped — is preserved,
  /// and the occurrences those rows represent are not generated a second time.
  /// [from] limits regeneration to dates on or after it, so editing a live
  /// block never rewrites its history.
  Future<void> materializeProgram(
    int programId,
    DateTime startDate, {
    DateTime? from,
  }) async {
    final program = await getProgram(programId);
    if (program == null) return;

    final fromIso = from == null ? null : _formatDateIso(from);

    await _db.transaction(() async {
      await (_db.delete(_db.scheduledWorkouts)..where((t) {
            var predicate =
                t.programId.equals(programId) &
                t.status.equals(ScheduleStatus.planned) &
                t.completedSessionId.isNull();
            if (fromIso != null) {
              predicate = predicate & t.dateIso.isBiggerOrEqualValue(fromIso);
            }
            return predicate;
          }))
          .go();

      // Whatever survived stays authoritative: never regenerate an occurrence
      // the user has already touched.
      final survivors = await (_db.select(
        _db.scheduledWorkouts,
      )..where((t) => t.programId.equals(programId))).get();
      final taken = {
        for (final s in survivors) (s.programDayId, s.occurrenceIndex),
      };

      final weeks = await getProgramWeeks(programId);
      if (weeks.isEmpty) return;

      final mode = ScheduleMode.fromId(program.scheduleMode);
      final cycleLength = program.cycleLength ?? 7;
      final duration = program.weeks;

      // Week 0's template days define the slot layout for the whole walk; each
      // occurrence then resolves back to its own week's copy of that day.
      final daysByWeek = <int, List<ProgramDayData>>{};
      for (final week in weeks) {
        daysByWeek[week.weekIndex] = await getProgramDaysForWeek(week.id);
      }
      final layout = daysByWeek[0] ?? const <ProgramDayData>[];
      final slotIndices = <int>{
        for (final d in layout)
          if (!d.isRest) d.cycleDayIndex ?? (d.dayOfWeek - 1),
      }.toList();

      final occurrences = ScheduleWalker.walk(
        mode: mode,
        dayIndices: slotIndices,
        totalWeeks: duration,
        cycleLength: cycleLength,
        startWeekday: startDate.weekday,
      );

      for (final occ in occurrences) {
        // Rotating programs keep a single template week; block programs map
        // week for week, falling back to week 0 for any gap.
        final weekDays = program.type == 'rotating'
            ? layout
            : (daysByWeek[occ.weekIndex] ?? layout);

        final slotDays =
            weekDays
                .where(
                  (d) =>
                      !d.isRest &&
                      (d.cycleDayIndex ?? (d.dayOfWeek - 1)) == occ.dayIndex,
                )
                .toList()
              ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

        final date = startDate.add(Duration(days: occ.dayOffset));
        final dateIso = _formatDateIso(date);
        if (fromIso != null && dateIso.compareTo(fromIso) < 0) continue;

        for (final day in slotDays) {
          if (taken.contains((day.id, occ.occurrenceIndex))) continue;
          await _db
              .into(_db.scheduledWorkouts)
              .insert(
                ScheduledWorkoutsCompanion.insert(
                  dateIso: dateIso,
                  programDayId: day.id,
                  programId: Value(programId),
                  status: const Value(ScheduleStatus.planned),
                  orderIndex: Value(day.orderIndex),
                  occurrenceIndex: Value(occ.occurrenceIndex),
                  startTimeMinutes: Value(day.startTimeMinutes),
                ),
              );
        }
      }

      await (_db.update(
        _db.programs,
      )..where((t) => t.id.equals(programId))).write(
        ProgramsCompanion(startDateIso: Value(_formatDateIso(startDate))),
      );
    });

    await _reindexDates(programId);
  }

  /// Regenerates the schedule after the block was edited, using the start date
  /// the program was originally materialized from.
  Future<void> rematerializeProgram(
    int programId, {
    bool futureOnly = true,
    DateTime? today,
  }) async {
    final program = await getProgram(programId);
    if (program == null) return;
    final startIso = program.startDateIso;
    if (startIso == null) return;
    final start = DateTime.parse(startIso);
    await materializeProgram(
      programId,
      start,
      from: futureOnly ? (today ?? _todayDate()) : null,
    );
  }

  /// Rewrites `orderIndex` densely for every date the program touches, so the
  /// per-date ordering stays 0..n-1 across programs after a generation pass.
  Future<void> _reindexDates(int programId) async {
    final dates =
        await (_db.selectOnly(_db.scheduledWorkouts, distinct: true)
              ..addColumns([_db.scheduledWorkouts.dateIso])
              ..where(_db.scheduledWorkouts.programId.equals(programId)))
            .map((row) => row.read(_db.scheduledWorkouts.dateIso)!)
            .get();
    for (final dateIso in dates) {
      await _reindexDate(dateIso);
    }
  }

  Future<void> _reindexDate(String dateIso) async {
    final rows =
        await (_db.select(_db.scheduledWorkouts)
              ..where((t) => t.dateIso.equals(dateIso))
              ..orderBy([
                (t) => OrderingTerm(expression: t.orderIndex),
                (t) => OrderingTerm(expression: t.id),
              ]))
            .get();
    await _db.transaction(() async {
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].orderIndex == i) continue;
        await (_db.update(_db.scheduledWorkouts)
              ..where((t) => t.id.equals(rows[i].id)))
            .write(ScheduledWorkoutsCompanion(orderIndex: Value(i)));
      }
    });
  }

  // ── Ordering & moving ────────────────────────────────────────────────────

  /// Reorders the sessions sharing one date. Mirrors
  /// `WorkoutsRepository.reorderWorkoutExercises`, including the
  /// `ReorderableListView` index adjustment.
  Future<void> reorderScheduledOnDate({
    required String dateIso,
    required int oldIndex,
    required int newIndex,
  }) async {
    final rows =
        await (_db.select(_db.scheduledWorkouts)
              ..where((t) => t.dateIso.equals(dateIso))
              ..orderBy([
                (t) => OrderingTerm(expression: t.orderIndex),
                (t) => OrderingTerm(expression: t.id),
              ]))
            .get();
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex -= 1;
    targetIndex = targetIndex.clamp(0, rows.length - 1);
    if (targetIndex == oldIndex) return;

    final reordered = List<ScheduledWorkoutData>.from(rows);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, moved);

    await _db.transaction(() async {
      for (var i = 0; i < reordered.length; i++) {
        await (_db.update(_db.scheduledWorkouts)
              ..where((t) => t.id.equals(reordered[i].id)))
            .write(ScheduledWorkoutsCompanion(orderIndex: Value(i)));
      }
    });
  }

  /// Moves one session to another date, appending it there unless
  /// [newOrderIndex] says otherwise, and reindexing both dates.
  ///
  /// Only an untouched `planned` row becomes `moved`; a completed or skipped
  /// session keeps its status.
  Future<void> moveScheduledWorkout({
    required int scheduleId,
    required DateTime newDate,
    int? newOrderIndex,
  }) async {
    final row = await (_db.select(
      _db.scheduledWorkouts,
    )..where((t) => t.id.equals(scheduleId))).getSingleOrNull();
    if (row == null) return;

    final oldDateIso = row.dateIso;
    final newDateIso = _formatDateIso(newDate);

    await _db.transaction(() async {
      final targetCount =
          await (_db.select(_db.scheduledWorkouts)..where(
                (t) =>
                    t.dateIso.equals(newDateIso) &
                    t.id.equals(scheduleId).not(),
              ))
              .get()
              .then((r) => r.length);

      await (_db.update(
        _db.scheduledWorkouts,
      )..where((t) => t.id.equals(scheduleId))).write(
        ScheduledWorkoutsCompanion(
          dateIso: Value(newDateIso),
          orderIndex: Value(newOrderIndex ?? targetCount),
          status: row.status == ScheduleStatus.planned
              ? const Value(ScheduleStatus.moved)
              : const Value.absent(),
        ),
      );
    });

    await _reindexDate(newDateIso);
    if (oldDateIso != newDateIso) await _reindexDate(oldDateIso);
  }

  /// Reorders the program days sharing one slot. [dayKey] is a `dayOfWeek`
  /// (1–7) for weekly programs or a `cycleDayIndex` for cycle ones.
  Future<void> reorderProgramDays({
    required int programWeekId,
    required int dayKey,
    required bool isCycle,
    required int oldIndex,
    required int newIndex,
  }) async {
    final rows =
        await (_db.select(_db.programDays)
              ..where(
                (t) =>
                    t.programWeekId.equals(programWeekId) &
                    (isCycle
                        ? t.cycleDayIndex.equals(dayKey)
                        : t.dayOfWeek.equals(dayKey)),
              )
              ..orderBy([
                (t) => OrderingTerm(expression: t.orderIndex),
                (t) => OrderingTerm(expression: t.id),
              ]))
            .get();
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex -= 1;
    targetIndex = targetIndex.clamp(0, rows.length - 1);
    if (targetIndex == oldIndex) return;

    final reordered = List<ProgramDayData>.from(rows);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, moved);

    await _db.transaction(() async {
      for (var i = 0; i < reordered.length; i++) {
        await (_db.update(_db.programDays)
              ..where((t) => t.id.equals(reordered[i].id)))
            .write(ProgramDaysCompanion(orderIndex: Value(i)));
      }
    });
  }

  Future<void> setScheduleStatus(int scheduleId, String status) async {
    await (_db.update(_db.scheduledWorkouts)
          ..where((t) => t.id.equals(scheduleId)))
        .write(ScheduledWorkoutsCompanion(status: Value(status)));
  }

  Future<void> deleteScheduledWorkout(int scheduleId) async {
    final row = await (_db.select(
      _db.scheduledWorkouts,
    )..where((t) => t.id.equals(scheduleId))).getSingleOrNull();
    if (row == null) return;
    await (_db.delete(
      _db.scheduledWorkouts,
    )..where((t) => t.id.equals(scheduleId))).go();
    await _reindexDate(row.dateIso);
  }

  // ── Schedule reads ───────────────────────────────────────────────────────

  /// Every scheduled session in a date range, joined to its day, week, program
  /// and resolved template in one query.
  Stream<List<ScheduledWorkoutRow>> watchScheduleRange({
    required String fromIso,
    required String toIso,
    int? programId,
  }) {
    final sw = _db.scheduledWorkouts;
    final pd = _db.programDays;
    final pw = _db.programWeeks;
    final pr = _db.programs;

    final query =
        _db.select(sw).join([
          innerJoin(pd, pd.id.equalsExp(sw.programDayId)),
          innerJoin(pw, pw.id.equalsExp(pd.programWeekId)),
          innerJoin(pr, pr.id.equalsExp(pw.programId)),
        ])..where(
          sw.dateIso.isBiggerOrEqualValue(fromIso) &
              sw.dateIso.isSmallerOrEqualValue(toIso),
        );
    if (programId != null) query.where(pw.programId.equals(programId));
    query.orderBy([
      OrderingTerm(expression: sw.dateIso),
      OrderingTerm(expression: sw.orderIndex),
    ]);

    return query.watch().asyncMap((rows) async {
      if (rows.isEmpty) return const <ScheduledWorkoutRow>[];

      final schedules = [for (final r in rows) r.readTable(sw)];
      final days = [for (final r in rows) r.readTable(pd)];

      // Two batched lookups instead of a query per row.
      final templateIds = <int>{
        for (var i = 0; i < rows.length; i++)
          if ((schedules[i].templateIdOverride ?? days[i].templateId) != null)
            (schedules[i].templateIdOverride ?? days[i].templateId)!,
      };
      final templates = <int, WorkoutTemplateData>{};
      final templateCounts = <int, int>{};
      if (templateIds.isNotEmpty) {
        final ts = await (_db.select(
          _db.workoutTemplates,
        )..where((t) => t.id.isIn(templateIds))).get();
        for (final t in ts) {
          templates[t.id] = t;
        }
        final te = _db.templateExercises;
        final counts =
            await (_db.selectOnly(te)
                  ..addColumns([te.templateId, te.id.count()])
                  ..where(te.templateId.isIn(templateIds))
                  ..groupBy([te.templateId]))
                .get();
        for (final c in counts) {
          templateCounts[c.read(te.templateId)!] = c.read(te.id.count()) ?? 0;
        }
      }

      final inlineDayIds = <int>{
        for (var i = 0; i < rows.length; i++)
          if ((schedules[i].templateIdOverride ?? days[i].templateId) == null)
            days[i].id,
      };
      final inlineCounts = <int, int>{};
      if (inlineDayIds.isNotEmpty) {
        final pde = _db.programDayExercises;
        final counts =
            await (_db.selectOnly(pde)
                  ..addColumns([pde.programDayId, pde.id.count()])
                  ..where(pde.programDayId.isIn(inlineDayIds))
                  ..groupBy([pde.programDayId]))
                .get();
        for (final c in counts) {
          inlineCounts[c.read(pde.programDayId)!] = c.read(pde.id.count()) ?? 0;
        }
      }

      return [
        for (var i = 0; i < rows.length; i++)
          () {
            final templateId =
                schedules[i].templateIdOverride ?? days[i].templateId;
            return ScheduledWorkoutRow(
              schedule: schedules[i],
              day: days[i],
              week: rows[i].readTable(pw),
              program: rows[i].readTable(pr),
              template: templateId == null ? null : templates[templateId],
              exerciseCount: templateId != null
                  ? (templateCounts[templateId] ?? 0)
                  : (inlineCounts[days[i].id] ?? 0),
            );
          }(),
      ];
    });
  }

  // ── Fatigue Conflict Checking ──

  /// Flags a fatigue conflict when two sessions hitting the same primary muscle
  /// group land within 48 hours of each other.
  ///
  /// Resolves content through [resolveDayExercises], so template-linked days are
  /// covered too, and only compares sessions that are actually close in time.
  Future<List<Map<String, dynamic>>> detectRecoveryConflicts({
    String? fromIso,
    String? toIso,
    int? programId,
  }) async {
    final query = _db.select(_db.scheduledWorkouts)
      ..orderBy([(t) => OrderingTerm(expression: t.dateIso)]);
    if (fromIso != null) {
      query.where((t) => t.dateIso.isBiggerOrEqualValue(fromIso));
    }
    if (toIso != null) {
      query.where((t) => t.dateIso.isSmallerOrEqualValue(toIso));
    }
    if (programId != null) query.where((t) => t.programId.equals(programId));
    final scheduled = await query.get();
    if (scheduled.length < 2) return const [];

    // Resolve each distinct program day once, not once per pair.
    final musclesByDay = <int, Set<String>>{};
    for (final s in scheduled) {
      final key = s.programDayId;
      if (musclesByDay.containsKey(key)) continue;
      musclesByDay[key] = await _muscleGroupsForDay(
        key,
        templateOverride: s.templateIdOverride,
      );
    }

    final conflicts = <Map<String, dynamic>>[];
    for (var i = 0; i < scheduled.length; i++) {
      final w1 = scheduled[i];
      final d1 = DateTime.parse(w1.dateIso);
      // The list is date-ordered, so stop as soon as the window is exceeded.
      for (var j = i + 1; j < scheduled.length; j++) {
        final w2 = scheduled[j];
        final d2 = DateTime.parse(w2.dateIso);
        if (d2.difference(d1).inHours > 48) break;

        final overlaps = musclesByDay[w1.programDayId]!.intersection(
          musclesByDay[w2.programDayId]!,
        );
        if (overlaps.isEmpty) continue;
        conflicts.add({
          'scheduledWorkoutId1': w1.id,
          'scheduledWorkoutId2': w2.id,
          'dateIso': w2.dateIso,
          'muscles': overlaps.toList(),
          'message':
              'Fatigue conflict: Same muscle group (${overlaps.join(", ")}) '
              'hit within 48h.',
        });
      }
    }
    return conflicts;
  }

  Future<Set<String>> _muscleGroupsForDay(
    int programDayId, {
    int? templateOverride,
  }) async {
    final resolved = await resolveDayExercises(
      programDayId,
      templateOverride: templateOverride,
    );
    if (resolved.isEmpty) return const {};
    final ids = resolved.map((e) => e.exerciseId).toSet();
    final catalog = await (_db.select(
      _db.exerciseCatalog,
    )..where((t) => t.id.isIn(ids))).get();
    return {for (final c in catalog) c.primaryMuscle};
  }

  // ── External Events / Deload Trips ──

  Future<int> addExternalEvent({
    required DateTime from,
    required DateTime to,
    required String type, // vacation | deload | rest | high_activity
    String? notes,
  }) async {
    final eventId = await _db
        .into(_db.externalEvents)
        .insert(
          ExternalEventsCompanion.insert(
            dateFromIso: _formatDateIso(from),
            dateToIso: _formatDateIso(to),
            type: type,
            notes: Value(notes),
          ),
        );

    await _applyEventAdjustments();
    return eventId;
  }

  Future<void> deleteExternalEvent(int eventId) async {
    await (_db.delete(
      _db.externalEvents,
    )..where((t) => t.id.equals(eventId))).go();
  }

  /// Marks planned sessions falling inside a vacation or rest range as skipped.
  /// Sessions the user has already acted on are left alone.
  Future<void> _applyEventAdjustments() async {
    final events = await (_db.select(
      _db.externalEvents,
    )..where((t) => t.type.isIn(const ['vacation', 'rest']))).get();
    if (events.isEmpty) return;

    for (final e in events) {
      await (_db.update(_db.scheduledWorkouts)..where(
            (t) =>
                t.dateIso.isBiggerOrEqualValue(e.dateFromIso) &
                t.dateIso.isSmallerOrEqualValue(e.dateToIso) &
                t.status.equals(ScheduleStatus.planned),
          ))
          .write(
            const ScheduledWorkoutsCompanion(
              status: Value(ScheduleStatus.skipped),
            ),
          );
    }
  }

  Stream<List<ExternalEventData>> watchExternalEvents() {
    return (_db.select(
      _db.externalEvents,
    )..orderBy([(t) => OrderingTerm(expression: t.dateFromIso)])).watch();
  }

  DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _formatDateIso(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-"
        "${dt.day.toString().padLeft(2, '0')}";
  }
}
