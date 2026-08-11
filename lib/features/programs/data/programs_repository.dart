import 'package:drift/drift.dart';

import '../../../data/local/database.dart';
import '../domain/periodization.dart';
import '../domain/schedule_status.dart';
import '../domain/schedule_walk.dart';
import '../domain/scheduled_workout_row.dart';
import '../domain/split_template.dart';

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

class ProgramsRepository {
  final AppDatabase _db;

  ProgramsRepository(this._db);

  // ── Template CRUD ────────────────────────────────────────────────────────

  Future<int> createProgram({
    required String name,
    required String? description,
    required int weeks,
    required String type, // rotating | block
    required String progressionStrategy, // volume | intensity | dynamic
    String? periodizationModel, // none | linear | concurrent | block | max_effort
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
              archived: const Value(false),
              splitType: Value(plan.type.id),
              scheduleMode: Value(plan.mode.id),
              cycleLength: Value(
                plan.mode == ScheduleMode.cycle ? plan.cycleLength : null,
              ),
              daysPerWeek: Value(plan.trainingDayCount),
              startDateIso: Value(_formatDateIso(startDate)),
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
            cycleDayIndex:
                plan.mode == ScheduleMode.cycle ? spec.index : null,
          );
        }
      }
      return id;
    });

    if (activate) await setActiveProgram(programId);
    await materializeProgram(programId, startDate);
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
            (t) => OrderingTerm(expression: t.isActive, mode: OrderingMode.desc),
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
    await (_db.update(_db.programs)..where((t) => t.id.equals(programId)))
        .write(
          ProgramsCompanion(
            archived: Value(archived),
            // An archived block can never be the active one.
            isActive: archived ? const Value(false) : const Value.absent(),
          ),
        );
  }

  Future<void> deleteProgram(int programId) async {
    await _db.transaction(() async {
      final weekIds = (await (_db.select(
        _db.programWeeks,
      )..where((t) => t.programId.equals(programId))).get())
          .map((w) => w.id)
          .toList();

      final dayIds = weekIds.isEmpty
          ? <int>[]
          : (await (_db.select(_db.programDays)
                    ..where((t) => t.programWeekId.isIn(weekIds)))
                .get())
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
      await (_db.delete(_db.programs)..where((t) => t.id.equals(programId)))
          .go();
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
          ),
        );
  }

  Future<int> _nextProgramDayOrder(
    int programWeekId,
    int dayOfWeek,
    int? cycleDayIndex,
  ) async {
    final rows = await (_db.select(_db.programDays)
          ..where(
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
    await (_db.update(_db.programDays)..where((t) => t.id.equals(programDayId)))
        .write(
          ProgramDaysCompanion(
            name: name == null ? const Value.absent() : Value(name),
            slotLabel: slotLabel == null
                ? const Value.absent()
                : Value(slotLabel),
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
    await (_db.update(_db.scheduledWorkouts)
          ..where((t) => t.id.equals(scheduleId)))
        .write(ScheduledWorkoutsCompanion(templateIdOverride: Value(templateId)));
  }

  Future<void> setWeekAdjustment(
    int programWeekId, {
    double? adjustmentFactor,
    double? intensityFactor,
  }) async {
    await (_db.update(_db.programWeeks)
          ..where((t) => t.id.equals(programWeekId)))
        .write(
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

  // ── Content resolution ───────────────────────────────────────────────────

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
                ),
              );
        }
      }

      await (_db.update(_db.programs)..where((t) => t.id.equals(programId)))
          .write(
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
    final dates = await (_db.selectOnly(_db.scheduledWorkouts, distinct: true)
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
      final targetCount = await (_db.select(_db.scheduledWorkouts)
            ..where(
              (t) => t.dateIso.equals(newDateIso) & t.id.equals(scheduleId).not(),
            ))
          .get()
          .then((r) => r.length);

      await (_db.update(_db.scheduledWorkouts)
            ..where((t) => t.id.equals(scheduleId)))
          .write(
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
          inlineCounts[c.read(pde.programDayId)!] =
              c.read(pde.id.count()) ?? 0;
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
    if (toIso != null) query.where((t) => t.dateIso.isSmallerOrEqualValue(toIso));
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
    final events = await (_db.select(_db.externalEvents)..where(
          (t) => t.type.isIn(const ['vacation', 'rest']),
        ))
        .get();
    if (events.isEmpty) return;

    for (final e in events) {
      await (_db.update(_db.scheduledWorkouts)..where(
            (t) =>
                t.dateIso.isBiggerOrEqualValue(e.dateFromIso) &
                t.dateIso.isSmallerOrEqualValue(e.dateToIso) &
                t.status.equals(ScheduleStatus.planned),
          ))
          .write(const ScheduledWorkoutsCompanion(
            status: Value(ScheduleStatus.skipped),
          ));
    }
  }

  Stream<List<ExternalEventData>> watchExternalEvents() {
    return (_db.select(_db.externalEvents)
          ..orderBy([(t) => OrderingTerm(expression: t.dateFromIso)]))
        .watch();
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
