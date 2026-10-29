part of '../workout_finish_view.dart';

/// Gold for records. The palette has no gold of its own; the fat macro token
/// is exactly it in dark mode and a readable amber in light mode.
Color _gold(HxColors hx) => hx.macroFatText;

/// Total volume, big, with how it compares to the last session of the same
/// workout — then time, sets and reps, and how much of the plan got done.
class _VolumeCard extends ConsumerWidget {
  const _VolumeCard({
    required this.summary,
    required this.sessionId,
    required this.weightFormat,
  });

  final SessionSummary summary;
  final int sessionId;
  final WeightFormat weightFormat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final report = ref.watch(workoutReportProvider(sessionId)).value;
    final completion = report == null
        ? null
        : SessionCompletion.ratio(
            completed: report.completedSets,
            planned: report.plannedSets,
          );
    final partial = SessionCompletion.isPartial(completion);
    final change = summary.tonnageChange;
    final volume = summary.tonnageKg.isFinite
        ? NumberFormat.decimalPattern().format(
            weightFormat.toDisplay(summary.tonnageKg).round(),
          )
        : '0';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        borderRadius: HxRadius.xlAll,
        border: Border.all(color: hx.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.6],
          colors: [
            Color.lerp(hx.surfaceContainerLowest, hx.primary, 0.12)!,
            hx.surfaceContainerLowest,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('TOTAL VOLUME', style: _kicker(context)),
              const Spacer(),
              if (change != null)
                Flexible(
                  child: _ChangeChip(change: change, name: summary.name),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    volume,
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontSize: 68,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -3,
                      height: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                weightFormat.suffix,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: hx.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: hx.outlineVariant)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _stat(
                    context,
                    WorkoutElapsedText.format(summary.duration),
                    'TIME',
                    first: true,
                  ),
                  _stat(context, '${summary.totalSets}', 'SETS'),
                  _stat(context, '${summary.totalReps}', 'REPS'),
                ],
              ),
            ),
          ),
          if (partial) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '${SessionCompletion.label(completion!)} of the plan done',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${report!.completedSets}/${report.plannedSets} sets',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: hx.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: HxRadius.pillAll,
              child: LinearProgressIndicator(
                value: completion,
                minHeight: 7,
                color: partialSessionColor,
                backgroundColor: hx.outlineVariant.withValues(alpha: .25),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    String value,
    String label, {
    bool first = false,
  }) {
    final hx = context.hx;
    return Expanded(
      child: Container(
        padding: EdgeInsets.only(left: first ? 0 : 14),
        decoration: first
            ? null
            : BoxDecoration(
                border: Border(left: BorderSide(color: hx.outlineVariant)),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: _kicker(context, size: 10.5, spacing: 1.2)),
          ],
        ),
      ),
    );
  }
}

class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.change, required this.name});

  final double change;
  final String name;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final pct = (change * 100).round();
    final color = pct >= 0 ? hx.success : hx.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: HxRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pct >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '${pct >= 0 ? '+' : ''}$pct% vs last $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "New records": an estimated-1RM record gets the big card, everything else
/// (rep records, volume records, milestones) a row in the list below it.
class _RecordsSection extends StatelessWidget {
  const _RecordsSection({required this.achievements});

  final List<InAppNotificationItem> achievements;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final gold = _gold(hx);
    final hero = achievements.firstWhereOrNull(
      (a) => a.type == AchievementType.weightPr,
    );
    final rest = [
      for (final a in achievements)
        if (!identical(a, hero)) a,
    ];
    final n = achievements.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'New records',
              style: theme.textTheme.displaySmall?.copyWith(fontSize: 20),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: gold.withValues(alpha: 0.14),
                borderRadius: HxRadius.pillAll,
              ),
              child: Text(
                '$n ${n == 1 ? 'PR' : 'PRs'}',
                style: TextStyle(
                  color: gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (hero != null)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: gold.withValues(alpha: 0.35)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  gold.withValues(alpha: 0.16),
                  hx.warning.withValues(alpha: 0.06),
                  hx.surfaceContainerLowest,
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.emoji_events_rounded, size: 20, color: gold),
                    const SizedBox(width: 8),
                    Text('ESTIMATED 1RM', style: _kicker(context, color: gold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  hero.title,
                  style: TextStyle(
                    color: hx.onSurfaceVariant,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        hero.value,
                        style: theme.textTheme.displayLarge?.copyWith(
                          fontSize: 44,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.5,
                          height: 1.05,
                        ),
                      ),
                    ),
                    if (hero.delta != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        hero.delta!,
                        style: TextStyle(
                          color: hx.success,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        if (rest.isNotEmpty) ...[
          if (hero != null) const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: hx.surfaceContainerLowest,
              borderRadius: HxRadius.lgAll,
              border: Border.all(color: hx.outlineVariant),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rest.length; i++)
                  _RecordRow(achievement: rest[i], divider: i > 0),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.achievement, required this.divider});

  final InAppNotificationItem achievement;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final a = achievement;
    final milestone =
        a.type == AchievementType.workoutMilestone ||
        a.type == AchievementType.streakMilestone;
    final color = milestone ? hx.primaryText : _gold(hx);
    final kind = switch (a.type) {
      AchievementType.weightPr => 'Estimated 1RM',
      AchievementType.repPr => 'Rep record',
      AchievementType.exerciseTonnagePr => 'Exercise volume',
      AchievementType.muscleGroupVolumePr => 'Muscle volume',
      AchievementType.accessoryPr => 'Setup record',
      AchievementType.workoutTonnagePr => 'Session record',
      AchievementType.longestWorkout => 'Longest workout',
      AchievementType.workoutMilestone ||
      AchievementType.streakMilestone => 'Milestone unlocked',
      _ => a.subtitle ?? '',
    };
    final delta = a.delta ?? (milestone ? 'New' : null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: divider
          ? BoxDecoration(
              border: Border(top: BorderSide(color: hx.outlineVariant)),
            )
          : null,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: HxRadius.smAll,
            ),
            child: Icon(a.icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (kind.isNotEmpty)
                  Text(
                    kind,
                    style: TextStyle(
                      color: hx.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  a.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (delta != null)
                  Text(
                    delta,
                    style: TextStyle(
                      color: hx.success,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _kicker(
  BuildContext context, {
  Color? color,
  double size = 11,
  double spacing = 1.6,
}) => TextStyle(
  color: color ?? context.hx.secondary,
  fontSize: size,
  fontWeight: FontWeight.w800,
  letterSpacing: spacing,
);
