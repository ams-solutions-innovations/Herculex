import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/scheduled_workout_row.dart';
import 'package:herculex/features/programs/presentation/sheets/day_detail_sheet.dart';
import 'package:herculex/features/shell/main_scaffold.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/scheduled_workout_service.dart';

import '../support/go_router_test_harness.dart';
import '../support/test_database.dart';

class _FakeScheduledWorkoutService extends Fake implements ScheduledWorkoutService {
  int? lastStartedScheduleId;
  int startCalls = 0;
  PlannedSessionSnapshot? previewResult;

  @override
  Future<int> startScheduledWorkoutById(int scheduleId, {int? gymId}) async {
    lastStartedScheduleId = scheduleId;
    startCalls++;
    return 999;
  }

  @override
  Future<PlannedSessionSnapshot?> previewScheduledWorkout(int scheduleId) async {
    return previewResult ??
        const PlannedSessionSnapshot(
          name: 'Preview Upper Body',
          exercises: [],
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeScheduledWorkoutService fakeService;

  final date = DateTime(2026, 9, 14);
  final iso = '2026-09-14';

  setUp(() async {
    db = await openTestDatabase();
    fakeService = _FakeScheduledWorkoutService();
  });

  tearDown(() => db.close());

  Future<ScheduledWorkoutRow> createTestRow({
    required int scheduleId,
    required String status,
  }) async {
    final programId = await db.into(db.programs).insert(
      ProgramsCompanion.insert(name: '4-Week Hypertrophy'),
    );
    final weekId = await db.into(db.programWeeks).insert(
      ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
    );
    final dayId = await db.into(db.programDays).insert(
      ProgramDaysCompanion.insert(
        programWeekId: weekId,
        dayOfWeek: 1,
        name: 'Upper Body A',
      ),
    );

    final program = await (db.select(db.programs)..where((t) => t.id.equals(programId))).getSingle();
    final week = await (db.select(db.programWeeks)..where((t) => t.id.equals(weekId))).getSingle();
    final day = await (db.select(db.programDays)..where((t) => t.id.equals(dayId))).getSingle();

    return ScheduledWorkoutRow(
      schedule: ScheduledWorkoutData(
        id: scheduleId,
        programDayId: dayId,
        dateIso: iso,
        orderIndex: 0,
        occurrenceIndex: 0,
        status: status,
      ),
      day: day,
      week: week,
      program: program,
      exerciseCount: 4,
    );
  }

  testWidgets(
    'Tapping Start workout calls startScheduledWorkoutById and switches to Workouts tab (tab 2)',
    (tester) async {
      final row = await createTestRow(scheduleId: 101, status: ScheduleStatus.planned);
      final range = ScheduleRange.week(date, programId: row.program.id);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          scheduledWorkoutServiceProvider.overrideWithValue(fakeService),
          scheduleByDateProvider(range).overrideWith(
            (ref) => Stream.value({iso: [row]}),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DayDetailSheet(date: date, programId: row.program.id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start workout'), findsOneWidget);
      expect(find.byType(PremiumButton), findsOneWidget);

      await tester.tap(find.text('Start workout'));
      await tester.pumpAndSettle();

      expect(fakeService.lastStartedScheduleId, 101);
      expect(fakeService.startCalls, 1);
      expect(container.read(mainTabIndexProvider), 2);
    },
  );

  testWidgets(
    'Tapping Resume workout calls startScheduledWorkoutById and switches to Workouts tab (tab 2)',
    (tester) async {
      final row = await createTestRow(scheduleId: 202, status: ScheduleStatus.inProgress);
      final range = ScheduleRange.week(date, programId: row.program.id);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          scheduledWorkoutServiceProvider.overrideWithValue(fakeService),
          scheduleByDateProvider(range).overrideWith(
            (ref) => Stream.value({iso: [row]}),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DayDetailSheet(date: date, programId: row.program.id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Resume workout'), findsOneWidget);

      await tester.tap(find.text('Resume workout'));
      await tester.pumpAndSettle();

      expect(fakeService.lastStartedScheduleId, 202);
      expect(fakeService.startCalls, 1);
      expect(container.read(mainTabIndexProvider), 2);
    },
  );

  testWidgets(
    'Tapping View workout pushes the planned workout preview route and creates no sessions',
    (tester) async {
      final row = await createTestRow(scheduleId: 303, status: ScheduleStatus.planned);
      final range = ScheduleRange.week(date, programId: row.program.id);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          scheduledWorkoutServiceProvider.overrideWithValue(fakeService),
          scheduleByDateProvider(range).overrideWith(
            (ref) => Stream.value({iso: [row]}),
          ),
        ],
      );
      addTearDown(container.dispose);

      // DayDetailSheet is only ever shown as a modal (`HxSheet.show`, which
      // pushes an imperative `ModalBottomSheetRoute` on the Navigator,
      // separate from GoRouter's declarative route stack) — mirror that here
      // rather than pumping it as the harness's page-level `home`, so
      // `_viewWorkout`'s `Navigator.of(context).pop()` pops the modal, not
      // GoRouter's only remaining route.
      final harness = GoRouterTestHarness(
        home: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => DayDetailSheet.show(
                context,
                date: date,
                programId: row.program.id,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
        stubRoutes: {
          AppRoutes.plannedWorkoutPreview: (context, state) => StubRouteScreen(
            label: 'PlannedWorkoutPreview',
            value: state.pathParameters['id'],
          ),
        },
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: harness.app),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('View workout'), findsOneWidget);

      await tester.tap(find.text('View workout'));
      await tester.pumpAndSettle();

      expect(find.text('PlannedWorkoutPreview:303'), findsOneWidget);
      expect(fakeService.startCalls, 0);
    },
  );
}
