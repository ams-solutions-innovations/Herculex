import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/shell/main_scaffold.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/scheduled_workout_service.dart';
import 'package:herculex/features/workouts/presentation/views/planned_workout_preview_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/test_database.dart';

class _FakeScheduledWorkoutService extends Fake
    implements ScheduledWorkoutService {
  _FakeScheduledWorkoutService({this.workoutResult, this.previewResult});

  TodaysScheduledWorkout? workoutResult;
  PlannedSessionSnapshot? previewResult;
  int? lastStartedScheduleId;
  int startCalls = 0;

  @override
  Future<TodaysScheduledWorkout?> workoutForSchedule(int scheduleId) async =>
      workoutResult;

  @override
  Future<PlannedSessionSnapshot?> previewScheduledWorkout(
    int scheduleId,
  ) async => previewResult;

  @override
  Future<int> startScheduledWorkoutById(int scheduleId, {int? gymId}) async {
    lastStartedScheduleId = scheduleId;
    startCalls++;
    return 999;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
  });

  tearDown(() => db.close());

  Future<TodaysScheduledWorkout> buildWorkout({
    required int scheduleId,
    required String status,
  }) async {
    final programId = await db
        .into(db.programs)
        .insert(ProgramsCompanion.insert(name: 'Test Program'));
    final weekId = await db
        .into(db.programWeeks)
        .insert(
          ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
        );
    final dayId = await db
        .into(db.programDays)
        .insert(
          ProgramDaysCompanion.insert(
            programWeekId: weekId,
            dayOfWeek: 1,
            name: 'Upper Body A',
          ),
        );
    final day = await (db.select(
      db.programDays,
    )..where((t) => t.id.equals(dayId))).getSingle();

    return TodaysScheduledWorkout(
      schedule: ScheduledWorkoutData(
        id: scheduleId,
        programDayId: dayId,
        dateIso: '2026-09-16',
        orderIndex: 0,
        occurrenceIndex: 0,
        status: status,
      ),
      programDay: day,
      exerciseCount: 1,
    );
  }

  Future<int> insertExercise(String name) {
    return db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: name,
            primaryMuscle: 'chest',
            equipment: 'barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'sagittal',
          ),
        );
  }

  Widget wrap(ProviderContainer container, Widget child) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: child),
    );
  }

  testWidgets(
    'renders every exercise name and set summary; creates no session from rendering alone',
    (tester) async {
      final exerciseId = await insertExercise('Bench Press');
      final workout = await buildWorkout(
        scheduleId: 401,
        status: ScheduleStatus.planned,
      );
      final fakeService = _FakeScheduledWorkoutService(
        workoutResult: workout,
        previewResult: PlannedSessionSnapshot(
          name: 'Upper Body A',
          exercises: [
            PlannedExerciseSnapshot(
              exerciseId: exerciseId,
              orderIndex: 0,
              restSeconds: 90,
              slotRole: 'primary',
              trainingMethod: 'straight_sets',
              why: 'test',
              allowsAdvancedTechniques: true,
              sets: const [
                PlannedSetSnapshot(
                  index: 1,
                  repsMin: 8,
                  repsMax: 8,
                  isWarmup: false,
                  setType: 'standard',
                  intent: 'rir2',
                ),
              ],
            ),
          ],
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          scheduledWorkoutServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        wrap(container, const PlannedWorkoutPreviewView(scheduleId: 401)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.textContaining('1x8'), findsOneWidget);
      expect(fakeService.startCalls, 0);
    },
  );

  testWidgets(
    'renders an empty state without throwing when the scheduleId no longer resolves',
    (tester) async {
      final fakeService = _FakeScheduledWorkoutService(workoutResult: null);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          scheduledWorkoutServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        wrap(container, const PlannedWorkoutPreviewView(scheduleId: 999)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('no longer exists'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tapping Start workout calls startScheduledWorkoutById once and switches to Workouts tab',
    (tester) async {
      final exerciseId = await insertExercise('Squat');
      final workout = await buildWorkout(
        scheduleId: 501,
        status: ScheduleStatus.planned,
      );
      final fakeService = _FakeScheduledWorkoutService(
        workoutResult: workout,
        previewResult: PlannedSessionSnapshot(
          name: 'Lower Body A',
          exercises: [
            PlannedExerciseSnapshot(
              exerciseId: exerciseId,
              orderIndex: 0,
              restSeconds: 120,
              slotRole: 'primary',
              trainingMethod: 'straight_sets',
              why: 'test',
              allowsAdvancedTechniques: true,
              sets: const [
                PlannedSetSnapshot(
                  index: 1,
                  repsMin: 5,
                  repsMax: 5,
                  isWarmup: false,
                  setType: 'standard',
                  intent: 'rir2',
                ),
              ],
            ),
          ],
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          scheduledWorkoutServiceProvider.overrideWithValue(fakeService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        wrap(container, const PlannedWorkoutPreviewView(scheduleId: 501)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start workout'), findsOneWidget);
      expect(find.byType(PremiumButton), findsOneWidget);

      await tester.tap(find.text('Start workout'));
      await tester.pumpAndSettle();

      expect(fakeService.lastStartedScheduleId, 501);
      expect(fakeService.startCalls, 1);
      expect(container.read(mainTabIndexProvider), 2);
    },
  );

  testWidgets('on the web the preview shows the plan but no Start workout', (
    tester,
  ) async {
    final exerciseId = await insertExercise('Squat');
    final workout = await buildWorkout(
      scheduleId: 502,
      status: ScheduleStatus.planned,
    );
    final fakeService = _FakeScheduledWorkoutService(
      workoutResult: workout,
      previewResult: PlannedSessionSnapshot(
        name: 'Lower Body A',
        exercises: [
          PlannedExerciseSnapshot(
            exerciseId: exerciseId,
            orderIndex: 0,
            restSeconds: 120,
            slotRole: 'primary',
            trainingMethod: 'straight_sets',
            why: 'test',
            allowsAdvancedTechniques: true,
            sets: const [
              PlannedSetSnapshot(
                index: 1,
                repsMin: 5,
                repsMax: 5,
                isWarmup: false,
                setType: 'standard',
                intent: 'rir2',
              ),
            ],
          ),
        ],
      ),
    );

    final container = ProviderContainer(
      overrides: [
        platformCapabilitiesProvider.overrideWithValue(
          const PlatformCapabilities.web(),
        ),
        appDatabaseProvider.overrideWithValue(db),
        scheduledWorkoutServiceProvider.overrideWithValue(fakeService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      wrap(container, const PlannedWorkoutPreviewView(scheduleId: 502)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
    expect(find.byType(PremiumButton), findsNothing);
  });

  testWidgets(
    'editing and applying to every wave rebinds after rematerializeProgram without showing missing state',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final benchRows = await (db.select(
        db.exerciseCatalog,
      )..where((t) => t.name.equals('Barbell Bench Press'))).get();
      final benchId = benchRows.isNotEmpty
          ? benchRows.first.id
          : await insertExercise('Barbell Bench Press');
      final dbBenchRows = await (db.select(
        db.exerciseCatalog,
      )..where((t) => t.name.equals('Dumbbell Bench Press'))).get();
      if (dbBenchRows.isEmpty) {
        await db
            .into(db.exerciseCatalog)
            .insert(
              ExerciseCatalogCompanion.insert(
                name: 'Dumbbell Bench Press',
                primaryMuscle: 'Chest',
                equipment: 'Dumbbell',
                mechanics: 'compound',
                force: 'push',
                plane: 'horizontal',
              ),
            );
      }

      final programId = await db
          .into(db.programs)
          .insert(
            ProgramsCompanion.insert(
              name: 'Upper Split',
              startDateIso: const Value('2026-09-14'),
            ),
          );
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
          );
      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              cycleDayIndex: const Value(0),
              name: 'Chest Day',
            ),
          );
      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: benchId,
              orderIndex: 0,
              targetSets: const Value(3),
              targetRepsMin: const Value(8),
              targetRepsMax: const Value(8),
            ),
          );

      final programsRepo = ProgramsRepository(db);
      final start = DateTime(2026, 9, 14);
      await programsRepo.materializeProgram(
        programId,
        start,
        from: start,
      );
      final initialScheduleId = await programsRepo.findScheduledWorkoutId(
        programDayId: dayId,
        dateIso: '2026-09-14',
      );
      expect(initialScheduleId, isNotNull);

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        wrap(
          container,
          PlannedWorkoutPreviewView(scheduleId: initialScheduleId!),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Barbell Bench Press'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Substitute exercise'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Dumbbell Bench Press'));
      await tester.tap(find.text('Dumbbell Bench Press'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Single-week program with no exercise rotation offers only one session vs every wave.
      expect(find.textContaining('This wave'), findsNothing);
      await tester.tap(find.text('Every wave'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no longer exists'), findsNothing);
      expect(find.text('Dumbbell Bench Press'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multi-wave program with exercise rotation offers This wave (Weeks 1–2) and updates only that wave',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final benchRows = await (db.select(
        db.exerciseCatalog,
      )..where((t) => t.name.equals('Barbell Bench Press'))).get();
      final benchId = benchRows.first.id;
      final inclineRows = await (db.select(
        db.exerciseCatalog,
      )..where((t) => t.name.equals('Incline Barbell Bench Press'))).get();
      final inclineId = inclineRows.first.id;

      final programId = await db
          .into(db.programs)
          .insert(
            ProgramsCompanion.insert(
              name: '4-Week Rotation',
              weeks: const Value(4),
              startDateIso: const Value('2026-09-14'),
            ),
          );

      final dayIds = <int>[];
      for (var w = 0; w < 4; w++) {
        final weekId = await db
            .into(db.programWeeks)
            .insert(
              ProgramWeeksCompanion.insert(programId: programId, weekIndex: w),
            );
        final dayId = await db
            .into(db.programDays)
            .insert(
              ProgramDaysCompanion.insert(
                programWeekId: weekId,
                dayOfWeek: 1,
                cycleDayIndex: const Value(0),
                name: 'Upper',
                slotLabel: const Value('Upper'),
              ),
            );
        dayIds.add(dayId);
        await db
            .into(db.programDayExercises)
            .insert(
              ProgramDayExercisesCompanion.insert(
                programDayId: dayId,
                exerciseId: w < 2 ? benchId : inclineId,
                orderIndex: 0,
                targetSets: const Value(3),
                targetRepsMin: const Value(8),
                targetRepsMax: const Value(8),
              ),
            );
      }

      final slotId = await db
          .into(db.programExerciseSlots)
          .insert(
            ProgramExerciseSlotsCompanion.insert(
              programId: programId,
              slotKey: 'upper:0',
              daySlotLabel: 'Upper',
              orderIndex: 0,
              role: const Value('main'),
            ),
          );
      for (var w = 0; w < 4; w++) {
        await db
            .into(db.rotationAssignments)
            .insert(
              RotationAssignmentsCompanion.insert(
                slotId: slotId,
                exerciseId: w < 2 ? benchId : inclineId,
                weekIndex: w,
                reason: 'wave test',
              ),
            );
      }

      final programsRepo = ProgramsRepository(db);
      final start = DateTime(2026, 9, 14);
      await programsRepo.materializeProgram(programId, start, from: start);
      final week1ScheduleId = await programsRepo.findScheduledWorkoutId(
        programDayId: dayIds[0],
        dateIso: '2026-09-14',
      );
      expect(week1ScheduleId, isNotNull);

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        wrap(
          container,
          PlannedWorkoutPreviewView(scheduleId: week1ScheduleId!),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Substitute exercise'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Dumbbell Bench Press'));
      await tester.tap(find.text('Dumbbell Bench Press'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('This workout only'), findsOneWidget);
      expect(find.text('This wave (Weeks 1–2)'), findsOneWidget);
      expect(find.text('Every wave'), findsOneWidget);

      await tester.tap(find.text('This wave (Weeks 1–2)'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no longer exists'), findsNothing);
      expect(find.text('Dumbbell Bench Press'), findsOneWidget);

      final updatedDays = await (db.select(
        db.programDays,
      )..where((t) => t.id.isIn(dayIds))).get();
      final byId = {for (final d in updatedDays) d.id: d};
      // Wave 1 (Weeks 1–2) received the template; Wave 2 (Weeks 3–4) kept its rotation.
      expect(byId[dayIds[0]]!.templateId, isNotNull);
      expect(byId[dayIds[1]]!.templateId, equals(byId[dayIds[0]]!.templateId));
      expect(byId[dayIds[2]]!.templateId, isNull);
      expect(byId[dayIds[3]]!.templateId, isNull);
    },
  );
}
