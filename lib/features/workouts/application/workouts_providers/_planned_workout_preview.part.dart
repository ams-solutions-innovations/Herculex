part of '../workouts_providers.dart';

/// Data for [PlannedWorkoutPreviewView] (FLOW-02): a scheduled workout's
/// resolved plan, the exercise catalog needed to render it, and the
/// schedule's current status (used only to gate the Start CTA).
class PlannedWorkoutPreviewData {
  final PlannedSessionSnapshot plan;
  final Map<int, ExerciseCatalogData> exercises;
  final String status;

  const PlannedWorkoutPreviewData({
    required this.plan,
    required this.exercises,
    required this.status,
  });
}

/// Resolves a pushed [PlannedWorkoutPreviewView]'s data from a `scheduleId`
/// alone — matching [sessionSummaryProvider]'s pattern for a route-pushed
/// detail view. Reuses [ScheduledWorkoutService] end-to-end rather than
/// re-deriving plan resolution or the "started" check.
final plannedWorkoutPreviewProvider = FutureProvider.autoDispose
    .family<PlannedWorkoutPreviewData?, int>((ref, scheduleId) async {
      final service = ref.watch(scheduledWorkoutServiceProvider);
      final today = await service.workoutForSchedule(scheduleId);
      if (today == null) return null;
      final plan = await service.previewScheduledWorkout(scheduleId);
      if (plan == null) return null;
      final db = ref.watch(appDatabaseProvider);
      final catalog = await db.select(db.exerciseCatalog).get();
      final exercises = {for (final e in catalog) e.id: e};
      return PlannedWorkoutPreviewData(
        plan: plan,
        exercises: exercises,
        status: today.schedule.status,
      );
    });
