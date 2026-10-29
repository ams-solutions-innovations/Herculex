part of '../workout_finish_view.dart';

/// Expanding ring + check mark that plays once when the screen opens.
class _Burst extends StatelessWidget {
  final AnimationController controller;
  const _Burst({required this.controller});

  @override
  Widget build(BuildContext context) {
    final pop = CurvedAnimation(
      parent: controller,
      curve: const Interval(0, 0.45, curve: Curves.elasticOut),
    );
    final ripple = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.05, 0.65, curve: Curves.easeOutCubic),
    );

    return SizedBox(
      width: 104,
      height: 104,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            for (final delay in const [0.0, 0.15])
              Opacity(
                opacity:
                    (1 - ((ripple.value - delay).clamp(0.0, 1.0))).clamp(
                      0.0,
                      1.0,
                    ) *
                    0.35,
                child: Container(
                  width: 72 + 32 * (ripple.value - delay).clamp(0.0, 1.0),
                  height: 72 + 32 * (ripple.value - delay).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: context.hx.primary, width: 2),
                  ),
                ),
              ),
            Transform.scale(
              scale: pop.value.clamp(0.0, 1.4),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [context.hx.primary, context.hx.success],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: context.hx.primary.withValues(alpha: 0.45),
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Circuit Summary Section ────────────────────────────────────────────────

class _CircuitsSummaryCard extends StatelessWidget {
  final int sessionId;
  final List<List<WorkoutExerciseData>> circuitGroups;

  const _CircuitsSummaryCard({
    required this.sessionId,
    required this.circuitGroups,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.repeat_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'CIRCUITS PERFORMANCE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < circuitGroups.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _CircuitSummaryTile(index: i + 1, exercises: circuitGroups[i]),
          ],
        ],
      ),
    );
  }
}

class _CircuitSummaryTile extends ConsumerWidget {
  final int index;
  final List<WorkoutExerciseData> exercises;

  const _CircuitSummaryTile({required this.index, required this.exercises});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sortedExercises = List<WorkoutExerciseData>.from(exercises)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    final setsByEx = <int, List<SetEntryData>>{};
    for (final ex in sortedExercises) {
      final setsAsync = ref.watch(workoutExerciseSetsProvider(ex.id));
      setsByEx[ex.id] = setsAsync.asData?.value ?? [];
    }

    final stats = calculateCircuitStats(
      exercises: sortedExercises,
      setsByExerciseId: setsByEx,
    );

    final isCircuit = sortedExercises.length >= 3;
    final label = isCircuit ? 'Circuit $index' : 'Superset $index';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${sortedExercises.length} exercises',
                style: TextStyle(color: AppColors.secondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COMPLETED ROUNDS',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${stats.completedRounds} / ${stats.totalPlannedRounds}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 24, color: AppColors.outlineVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AVG REST BETWEEN',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stats.formattedAvgRest,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
