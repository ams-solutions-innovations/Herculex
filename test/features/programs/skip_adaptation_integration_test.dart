import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/programs/data/weekly_adaptation_repository.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late FakeClock clock;
  late List<int> schedules;
  late WeeklyAdaptationRepository adaptations;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
    clock = FakeClock(DateTime(2026, 10, 12, 8));
    adaptations = WeeklyAdaptationRepository(db, clock);
    final program = await db
        .into(db.programs)
        .insert(ProgramsCompanion.insert(name: 'Skip regression'));
    final week = await db
        .into(db.programWeeks)
        .insert(ProgramWeeksCompanion.insert(programId: program, weekIndex: 0));
    schedules = [];
    final muscles = ['Chest', 'Back', 'Biceps', 'Triceps', 'Quads'];
    final exercises = <int>[];
    for (final muscle in muscles) {
      exercises.add(
        await db
            .into(db.exerciseCatalog)
            .insert(
              ExerciseCatalogCompanion.insert(
                name: 'Skip $muscle',
                primaryMuscle: muscle,
                equipment: 'machine',
                mechanics: 'isolation',
                force: 'push',
                plane: 'sagittal',
              ),
            ),
      );
    }
    for (var i = 0; i < 3; i++) {
      final day = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: week,
              dayOfWeek: 1 + i * 2,
              name: 'Day $i',
            ),
          );
      final chosen = i == 0 ? [exercises.first] : exercises.skip(1).toList();
      for (var j = 0; j < chosen.length; j++) {
        await db
            .into(db.programDayExercises)
            .insert(
              ProgramDayExercisesCompanion.insert(
                programDayId: day,
                exerciseId: chosen[j],
                orderIndex: j,
                slotRole: const Value('isolation'),
                targetSets: const Value(3),
              ),
            );
      }
      schedules.add(
        await db
            .into(db.scheduledWorkouts)
            .insert(
              ScheduledWorkoutsCompanion.insert(
                programId: Value(program),
                programDayId: day,
                dateIso: '2026-10-${12 + i * 2}',
              ),
            ),
      );
    }
  });
  tearDown(() => db.close());

  test(
    'accepted skip updates today immediately and catch-up work stays within weekly caps',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(clock),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        todaysScheduledWorkoutProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(
        (await container.read(
          todaysScheduledWorkoutProvider.future,
        ))?.schedule.id,
        schedules.first,
      );
      final proposal = (await adaptations.proposeForSkippedWorkout(
        schedules.first,
      ))!;
      expect(proposal.proposal.hasChanges, isTrue);
      await adaptations.accept(proposal.id);
      // The shared stream drives dashboard, widget and watch; no manual invalidation.
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (container.read(todaysScheduledWorkoutProvider).asData?.value ==
                null &&
            container.read(todaysScheduledWorkoutProvider).hasValue) {
          break;
        }
      }
      expect(
        await container.read(todaysScheduledWorkoutProvider.future),
        isNull,
      );
      expect(
        await adaptations.proposeForSkippedWorkout(schedules.first),
        isNull,
      );
      final overridesBefore =
          (await db.select(db.adaptationOverrides).get()).length;
      await adaptations.accept(
        proposal.id,
      ); // duplicate confirmation is harmless
      expect(
        (await db.select(db.adaptationOverrides).get()).length,
        overridesBefore,
      );

      final second = await adaptations.proposeForSkippedWorkout(schedules[1]);
      if (second != null) {
        await adaptations.accept(second.id);
      }
      final remaining = await (db.select(
        db.scheduledWorkouts,
      )..where((s) => s.id.equals(schedules.last))).getSingle();
      final resolver = PlannedSessionResolver(db);
      final original = await resolver.resolveProgramDay(remaining.programDayId);
      final current = await resolver.resolveScheduledWorkout(remaining);
      int count(PlannedSessionSnapshot p) => p.exercises.fold(
        0,
        (n, e) => n + e.sets.where((s) => !s.isWarmup).length,
      );
      expect(
        count(current),
        lessThanOrEqualTo((count(original) * 1.2).floor()),
      );
      expect(
        current.exercises.map((e) => e.orderIndex).toSet().length,
        current.exercises.length,
      );
      expect(count(current) - count(original), lessThanOrEqualTo(4));
    },
  );

  test(
    'moving a target after preview expires the proposal without skipping source',
    () async {
      final proposal = (await adaptations.proposeForSkippedWorkout(
        schedules.first,
      ))!;
      expect(proposal.proposal.hasChanges, isTrue);
      final target = proposal.proposal.changes.first.scheduleId;
      await (db.update(
        db.scheduledWorkouts,
      )..where((s) => s.id.equals(target))).write(
        const ScheduledWorkoutsCompanion(dateIso: Value('2026-10-20')),
      );
      await expectLater(
        adaptations.accept(proposal.id),
        throwsA(isA<AdaptationStaleException>()),
      );
      final source = await (db.select(
        db.scheduledWorkouts,
      )..where((s) => s.id.equals(schedules.first))).getSingle();
      expect(source.status, ScheduleStatus.planned);
      expect(await db.select(db.adaptationOverrides).get(), isEmpty);
    },
  );
}
