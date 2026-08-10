import 'package:drift/drift.dart' show Value, OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/dashboard/domain/dashboard_config.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/workouts/data/scheduled_workout_service.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

class _FixedClock implements Clock {
  DateTime fixed;
  _FixedClock(this.fixed);
  @override
  DateTime now() => fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DashboardConfig', () {
    test('encode → decode round-trips visibility and order', () {
      final cfg = DashboardConfig.defaults
          .toggle(DashboardWidgetType.cnsLoad, true)
          .reorder(0, 3);
      final decoded = DashboardConfig.decode(cfg.encode());
      expect(decoded.widgets.map((w) => w.type),
          cfg.widgets.map((w) => w.type));
      expect(decoded.widgets.map((w) => w.visible),
          cfg.widgets.map((w) => w.visible));
    });

    test('toggle flips a single widget', () {
      final cfg =
          DashboardConfig.defaults.toggle(DashboardWidgetType.bodyweight, true);
      expect(
        cfg.widgets
            .singleWhere((w) => w.type == DashboardWidgetType.bodyweight)
            .visible,
        isTrue,
      );
      // Others untouched.
      expect(
        cfg.widgets
            .singleWhere((w) => w.type == DashboardWidgetType.macros)
            .visible,
        isTrue,
      );
    });

    test('reorder moves a widget without dropping any', () {
      final cfg = DashboardConfig.defaults.reorder(0, 4);
      expect(cfg.widgets, hasLength(DashboardConfig.defaults.widgets.length));
      expect(cfg.widgets.map((w) => w.type).toSet(),
          DashboardConfig.defaults.widgets.map((w) => w.type).toSet());
      // The first widget (fastingTimer) moved later.
      expect(cfg.widgets.first.type,
          isNot(DashboardWidgetType.fastingTimer));
    });

    test('visibleWidgets filters hidden slots, preserving order', () {
      final cfg =
          DashboardConfig.defaults.toggle(DashboardWidgetType.fastingTimer, false);
      expect(
        cfg.visibleWidgets.any((w) => w.type == DashboardWidgetType.fastingTimer),
        isFalse,
      );
    });

    test('decode of empty/garbage falls back to defaults', () {
      expect(DashboardConfig.decode(null).widgets.map((w) => w.type),
          DashboardConfig.defaults.widgets.map((w) => w.type));
      expect(DashboardConfig.decode('   ').widgets,
          isNotEmpty);
    });

    test('decode drops unknown ids and appends newly-added types as hidden', () {
      // Stored config knows only two widgets; the rest must be appended hidden.
      final decoded = DashboardConfig.decode('macros:1,bogus_widget:1,cns_load:0');
      final types = decoded.widgets.map((w) => w.type).toList();
      expect(types.contains(DashboardWidgetType.macros), isTrue);
      expect(types.first, DashboardWidgetType.macros); // preserved first
      // Every known type is present exactly once.
      expect(types.toSet().length, DashboardWidgetType.values.length);
      // Appended types are hidden.
      final appended = decoded.widgets
          .firstWhere((w) => w.type == DashboardWidgetType.bodyweight);
      expect(appended.visible, isFalse);
      // Explicit hidden flag preserved.
      expect(
        decoded.widgets
            .firstWhere((w) => w.type == DashboardWidgetType.cnsLoad)
            .visible,
        isFalse,
      );
    });
  });

  group('ScheduledWorkoutService (smart launcher)', () {
    late AppDatabase db;
    late _FixedClock clock;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.customStatement('PRAGMA foreign_keys = ON');
      clock = _FixedClock(DateTime(2026, 6, 15, 8));
    });
    tearDown(() => db.close());

    ScheduledWorkoutService makeService() => ScheduledWorkoutService(
          db,
          clock,
          ProgramsRepository(db),
          TemplatesRepository(db),
        );

    Future<int> makeExercise(String name) => db.into(db.exerciseCatalog).insert(
          ExerciseCatalogCompanion.insert(
            name: name,
            primaryMuscle: 'Quads',
            equipment: 'Barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'axial',
          ),
        );

    /// Builds a program with one day "Leg Day" scheduled for [iso].
    Future<int> scheduleLegDay(String iso, List<int> exerciseIds) async {
      final programId = await db.into(db.programs).insert(
          ProgramsCompanion.insert(name: 'Test Program'));
      final weekId = await db.into(db.programWeeks).insert(
          ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0));
      final dayId = await db.into(db.programDays).insert(
          ProgramDaysCompanion.insert(
              programWeekId: weekId, dayOfWeek: 1, name: 'Leg Day'));
      for (final (i, exId) in exerciseIds.indexed) {
        await db.into(db.programDayExercises).insert(
            ProgramDayExercisesCompanion.insert(
                programDayId: dayId, exerciseId: exId, orderIndex: i));
      }
      return db.into(db.scheduledWorkouts).insert(
          ScheduledWorkoutsCompanion.insert(dateIso: iso, programDayId: dayId));
    }

    test('reads today\'s scheduled workout with exercise count', () async {
      final svc = makeService();
      final squat = await makeExercise('Test Squat');
      final rdl = await makeExercise('Test RDL');
      await scheduleLegDay('2026-06-15', [squat, rdl]);

      final today = await svc.todaysWorkout();
      expect(today, isNotNull);
      expect(today!.programDay.name, 'Leg Day');
      expect(today.exerciseCount, 2);
      expect(today.isDone, isFalse);
    });

    test('nothing scheduled today → null', () async {
      final svc = makeService();
      final squat = await makeExercise('Test Squat');
      await scheduleLegDay('2026-06-20', [squat]); // different day
      expect(await svc.todaysWorkout(), isNull);
    });

    test('starting pre-populates a session and marks the schedule in progress',
        () async {
      final svc = makeService();
      final squat = await makeExercise('Test Squat');
      final rdl = await makeExercise('Test RDL');
      await scheduleLegDay('2026-06-15', [squat, rdl]);

      final today = (await svc.todaysWorkout())!;
      final sessionId = await svc.startScheduledWorkout(today);

      // Session created with the program day's exercises in order.
      final exercises = await (db.select(db.workoutExercises)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      expect(exercises.map((e) => e.exerciseId), [squat, rdl]);
      expect(
          (await db.select(db.workoutSessions).get()).single.notes, 'Leg Day');

      // Linked, but starting is not finishing.
      final refreshed = await svc.todaysWorkout();
      expect(refreshed!.schedule.completedSessionId, sessionId);
      expect(refreshed.isInProgress, isTrue);
      expect(refreshed.isDone, isFalse);
    });

    test('the schedule only becomes done when the session ends', () async {
      final svc = makeService();
      final squat = await makeExercise('Test Squat');
      await scheduleLegDay('2026-06-15', [squat]);

      final today = (await svc.todaysWorkout())!;
      final sessionId = await svc.startScheduledWorkout(today);
      expect((await svc.todaysWorkout())!.isDone, isFalse);

      await WorkoutsRepository(db, clock).endSession(sessionId);

      final finished = (await svc.todaysWorkout())!;
      expect(finished.isDone, isTrue);
      expect(finished.isInProgress, isFalse);
    });

    test('a template-linked day starts a session with the template content',
        () async {
      final svc = makeService();
      final squat = await makeExercise('Test Squat');
      final rdl = await makeExercise('Test RDL');
      await scheduleLegDay('2026-06-15', const []); // no inline exercises

      // Link a template with two exercises, the second carrying explicit sets.
      final templateId = await db
          .into(db.workoutTemplates)
          .insert(WorkoutTemplatesCompanion.insert(name: 'Leg Template'));
      final te1 = await db.into(db.templateExercises).insert(
          TemplateExercisesCompanion.insert(
              templateId: templateId, exerciseId: squat, orderIndex: 0));
      await db.into(db.templateExercises).insert(
          TemplateExercisesCompanion.insert(
              templateId: templateId, exerciseId: rdl, orderIndex: 1));
      await db.into(db.templateSets).insert(TemplateSetsCompanion.insert(
          templateExerciseId: te1, setOrder: 1, targetReps: const Value(5)));

      final dayId =
          (await db.select(db.programDays).get()).single.id;
      await ProgramsRepository(db).setProgramDayTemplate(dayId, templateId);

      // The count comes from the template, not from the (empty) inline rows.
      final today = (await svc.todaysWorkout())!;
      expect(today.exerciseCount, 2);
      expect(today.template?.name, 'Leg Template');

      final sessionId = await svc.startScheduledWorkout(today);
      final exercises = await (db.select(db.workoutExercises)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .get();
      expect(exercises.map((e) => e.exerciseId), [squat, rdl]);

      // Template sets came across too — the reason this path delegates to
      // TemplatesRepository instead of copying exercises itself.
      final sets = await db.select(db.setEntries).get();
      expect(sets.any((s) => s.reps == 5), isTrue);
    });

    test('a schedule template override wins over the day link', () async {
      final svc = makeService();
      final squat = await makeExercise('Test Squat');
      final rdl = await makeExercise('Test RDL');
      await scheduleLegDay('2026-06-15', const []);

      Future<int> template(String name, List<int> ids) async {
        final id = await db
            .into(db.workoutTemplates)
            .insert(WorkoutTemplatesCompanion.insert(name: name));
        for (final (i, ex) in ids.indexed) {
          await db.into(db.templateExercises).insert(
              TemplateExercisesCompanion.insert(
                  templateId: id, exerciseId: ex, orderIndex: i));
        }
        return id;
      }

      final linked = await template('Linked', [squat]);
      final override = await template('Override', [rdl]);

      final repo = ProgramsRepository(db);
      final dayId = (await db.select(db.programDays).get()).single.id;
      final scheduleId = (await db.select(db.scheduledWorkouts).get()).single.id;
      await repo.setProgramDayTemplate(dayId, linked);
      await repo.setScheduleTemplateOverride(scheduleId, override);

      final today = (await svc.todaysWorkout())!;
      expect(today.template?.name, 'Override');

      final sessionId = await svc.startScheduledWorkout(today);
      final exercises = await (db.select(db.workoutExercises)
            ..where((t) => t.sessionId.equals(sessionId)))
          .get();
      expect(exercises.map((e) => e.exerciseId), [rdl]);
    });

    test('a day with neither template nor exercises starts an empty session',
        () async {
      final svc = makeService();
      await scheduleLegDay('2026-06-15', const []);

      final today = (await svc.todaysWorkout())!;
      expect(today.exerciseCount, 0);

      final sessionId = await svc.startScheduledWorkout(today);
      expect(
        await (db.select(db.workoutExercises)
              ..where((t) => t.sessionId.equals(sessionId)))
            .get(),
        isEmpty,
      );
      expect((await svc.todaysWorkout())!.isInProgress, isTrue);
    });

    test('tags the session with the chosen gym', () async {
      final svc = makeService();
      final squat = await makeExercise('Test Squat');
      await scheduleLegDay('2026-06-15', [squat]);
      final gymId = await db.into(db.gyms).insert(
          GymsCompanion.insert(name: 'Gym A', isDefault: const Value(true)));

      final today = (await svc.todaysWorkout())!;
      final sessionId = await svc.startScheduledWorkout(today, gymId: gymId);
      final session = await (db.select(db.workoutSessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingle();
      expect(session.gymId, gymId);
    });
  });
}
