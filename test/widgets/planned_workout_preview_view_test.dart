import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/shell/main_scaffold.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/scheduled_workout_service.dart';
import 'package:herculex/features/workouts/presentation/views/planned_workout_preview_view.dart';

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
}
