import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/workout_report/data/workout_report_plan_actions.dart';
import 'package:herculex/features/workout_report/data/workout_report_repository.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';

final workoutReportRepositoryProvider = Provider<WorkoutReportRepository>(
  (ref) => WorkoutReportRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
  ),
);

final workoutReportPlanActionsProvider = Provider<WorkoutReportPlanActions>(
  (ref) => WorkoutReportPlanActions(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
    ref.watch(weeklyAdaptationRepositoryProvider),
  ),
);

/// Scheduled workout id → share of planned sets that were logged.
final scheduleCompletionProvider = StreamProvider<Map<int, double>>(
  (ref) => ref.watch(workoutReportRepositoryProvider).watchScheduleCompletion(),
);

final workoutReportProvider = StreamProvider.autoDispose
    .family<WorkoutReport?, int>((ref, id) async* {
      final repo = ref.watch(workoutReportRepositoryProvider);
      await repo.generate(id);
      yield* repo
          .watch(id)
          .map(
            (row) => row == null ? null : WorkoutReport.decode(row.reportJson),
          );
    });
