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
                  width: 58 + 44 * (ripple.value - delay).clamp(0.0, 1.0),
                  height: 58 + 44 * (ripple.value - delay).clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
            Transform.scale(
              scale: pop.value.clamp(0.0, 1.4),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, const Color(0xFF30D158)],
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The exported card. Kept free of theme lookups so the chosen [background]
/// fully determines how it renders, whatever the app theme is.
class _ShareCard extends StatelessWidget {
  final SessionSummary summary;
  final ShareCardBackground background;
  final WeightFormat weightFormat;

  const _ShareCard({
    required this.summary,
    required this.background,
    required this.weightFormat,
  });

  bool get _onDark => background != ShareCardBackground.light;

  Color get _fg => _onDark ? Colors.white : const Color(0xFF0B1220);
  Color get _muted =>
      _onDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: switch (background) {
          ShareCardBackground.dark => const Color(0xFF0D1B2A),
          ShareCardBackground.light => Colors.white,
          ShareCardBackground.transparent => Colors.transparent,
        },
        border: background == ShareCardBackground.transparent
            ? Border.all(color: _fg.withValues(alpha: 0.25), width: 1.5)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'HERCULEX',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            summary.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _fg,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, d MMM').format(summary.startedAt),
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat(summary.durationLabel, 'TIME'),
              _divider(),
              _stat('${summary.caloriesBurned}', 'KCAL'),
              _divider(),
              _stat(weightFormat.formatTonnage(summary.tonnageKg), 'VOLUME'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('${summary.totalSets}', 'SETS'),
              _divider(),
              _stat('${summary.totalReps}', 'REPS'),
              _divider(),
              _stat('${summary.exerciseCount}', 'EXERCISES'),
            ],
          ),
          if (summary.photoPath != null &&
              File(summary.photoPath!).existsSync()) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(summary.photoPath!),
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (summary.muscleGroups.isNotEmpty) ...[
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in summary.muscleGroups)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      m,
                      style: TextStyle(
                        color: _onDark ? Colors.white : AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (summary.achievements.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: _onDark
                    ? const Color(0xFF132238).withValues(alpha: 0.85)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(
                    0xFFFFD700,
                  ).withValues(alpha: _onDark ? 0.35 : 0.45),
                  width: 1.0,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFFFFD700),
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'NEW RECORDS & ACHIEVEMENTS',
                        style: TextStyle(
                          color: _onDark
                              ? const Color(0xFFFFD700)
                              : const Color(0xFFB45309),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final ach in summary.achievements.take(3)) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: Row(
                        children: [
                          Icon(ach.icon, size: 14, color: ach.primaryColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              ach.title,
                              style: TextStyle(
                                color: _fg,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Values can be long ("Permanently replaced with
                          // …"); capped at half the row so the title keeps
                          // its share instead of collapsing.
                          Flexible(
                            child: Text(
                              ach.valueText,
                              style: TextStyle(
                                color: _onDark
                                    ? ach.primaryColor
                                    : const Color(0xFF0F172A),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: TextStyle(color: _fg, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: TextStyle(
          color: _muted,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      ),
    ],
  );

  Widget _divider() =>
      Container(width: 1, height: 30, color: _fg.withValues(alpha: 0.12));
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
