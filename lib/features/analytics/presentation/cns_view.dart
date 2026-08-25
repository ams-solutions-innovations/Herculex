import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../theme/tokens/tokens.dart';
import '../../../ui/ui.dart';
import '../domain/cns_breakdown.dart';
import 'cns_providers.dart';

/// Dedicated CNS (Central Nervous System) analytics view.
/// Shows current neurological readiness, ACWR metrics, 28-day historical load,
/// session-by-session fatigue breakdown with residual decay, top taxing exercises,
/// and full transparency on the calculation engine.
class CnsView extends ConsumerWidget {
  const CnsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cnsAsync = ref.watch(cnsDetailedBreakdownProvider);

    return HxScreenShell(
      title: 'CNS Analytics',
      children: [
        cnsAsync.when(
          data: (result) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CnsReadinessHeaderCard(result: result),
              const SizedBox(height: HxSpace.x4),
              _AcwrMetricCard(result: result),
              const SizedBox(height: HxSpace.x4),
              _CnsLoadChartCard(result: result),
              const SizedBox(height: HxSpace.x4),
              _RecentWorkoutsImpactCard(result: result),
              const SizedBox(height: HxSpace.x4),
              _TopCnsExercisesCard(result: result),
              const SizedBox(height: HxSpace.x4),
              const _CnsEngineExplainerCard(),
              const SizedBox(height: HxSpace.x6),
            ],
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: HxSpace.x8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(HxSpace.x6),
              child: Text(
                'Failed to load CNS analytics: $e',
                style: TextStyle(color: context.hx.danger),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 1. Readiness & Recovery Header ──────────────────────────────────────────

class _CnsReadinessHeaderCard extends StatelessWidget {
  const _CnsReadinessHeaderCard({required this.result});

  final CnsDetailedResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    final readinessPct = (result.readiness * 100).round();
    final fatiguePct = (result.currentLoad * 100).round();

    final statusColor = switch (result.status) {
      'FRESH' => hx.success,
      'MODERATE' => hx.warning,
      _ => hx.danger,
    };

    final etaText = result.hoursToFullRecovery == null || result.hoursToFullRecovery! <= 0.5
        ? 'Fully Primed & Recovered'
        : 'Full recovery in ~${result.hoursToFullRecovery!.round()}h';

    return HxCard(
      accent: hx.domainRecovery,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NEUROLOGICAL READINESS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hx.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: hx.isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(HxRadius.pill),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      result.status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$readinessPct%',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: HxSpace.x3),
              Text(
                'readiness ($fatiguePct% fatigue)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: hx.secondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x3),
          // Visual Readiness Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: result.readiness,
              minHeight: 8,
              backgroundColor: hx.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: HxSpace.x3),
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: hx.secondary),
              const SizedBox(width: 6),
              Text(
                etaText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hx.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x4),
          // Actionable Recommendation Box
          Container(
            padding: const EdgeInsets.all(HxSpace.x3 + 2),
            decoration: BoxDecoration(
              color: (result.deloadSuggested ? hx.danger : hx.primary).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(HxRadius.md),
              border: Border.all(
                color: (result.deloadSuggested ? hx.danger : hx.primary).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  result.deloadSuggested
                      ? Icons.battery_alert
                      : Icons.bolt_outlined,
                  size: 20,
                  color: result.deloadSuggested ? hx.danger : hx.primary,
                ),
                const SizedBox(width: HxSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.deloadSuggested ? 'Deload Suggested' : 'Training Guidance',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: result.deloadSuggested ? hx.danger : hx.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.trainingGuidance,
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                      ),
                    ],
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

// ── 2. ACWR Metric Card ─────────────────────────────────────────────────────

class _AcwrMetricCard extends StatelessWidget {
  const _AcwrMetricCard({required this.result});

  final CnsDetailedResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    final acwr = result.acwr;
    final acwrStatus = acwr > 1.4
        ? 'High Spike'
        : (acwr >= 0.8 && acwr <= 1.3 ? 'Sweet Spot' : (acwr < 0.8 ? 'Underload' : 'Moderate'));
    final acwrColor = acwr > 1.4
        ? hx.danger
        : (acwr >= 0.8 && acwr <= 1.3 ? hx.success : hx.warning);

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WORKLOAD RATIO (ACWR)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hx.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: acwrColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  acwrStatus,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: acwrColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            'Acute 7-day neurological strain compared to your 4-week chronic baseline.',
            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
          ),
          const SizedBox(height: HxSpace.x4),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Acute 7-Day',
                  value: result.acuteWeeklyLoad.toStringAsFixed(1),
                  unit: 'pts',
                  accent: hx.primary,
                ),
              ),
              const SizedBox(width: HxSpace.x2),
              Expanded(
                child: _MetricTile(
                  label: 'Chronic 4-Wk Avg',
                  value: result.chronicWeeklyLoad.toStringAsFixed(1),
                  unit: 'pts/wk',
                  accent: hx.secondary,
                ),
              ),
              const SizedBox(width: HxSpace.x2),
              Expanded(
                child: _MetricTile(
                  label: 'ACWR Ratio',
                  value: '${acwr.toStringAsFixed(2)}×',
                  unit: acwrStatus,
                  accent: acwrColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x3),
          // ACWR Safe Zone Visual
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(
                  height: 6,
                  color: hx.surfaceVariant,
                ),
                FractionallySizedBox(
                  widthFactor: (acwr / 2.0).clamp(0.0, 1.0),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: acwrColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0.0 (Deload)', style: TextStyle(fontSize: 9, color: hx.secondary)),
              Text('0.8–1.3 (Optimal)', style: TextStyle(fontSize: 9, color: hx.success, fontWeight: FontWeight.w600)),
              Text('> 1.4 (Fatigue Spike)', style: TextStyle(fontSize: 9, color: hx.danger)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.accent,
  });

  final String label;
  final String value;
  final String unit;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(HxRadius.md),
        border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: hx.secondary, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          Text(
            unit,
            style: TextStyle(fontSize: 9, color: hx.secondary),
          ),
        ],
      ),
    );
  }
}

// ── 3. 28-Day Load Chart Card ───────────────────────────────────────────────

class _CnsLoadChartCard extends StatelessWidget {
  const _CnsLoadChartCard({required this.result});

  final CnsDetailedResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final daily = result.trends.daily;

    final maxLoad = daily.fold<double>(1.0, (m, d) => max(m, d.load));

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DAILY CNS STRAIN (28 DAYS)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hx.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                'Max: ${maxLoad.toStringAsFixed(1)} pts',
                style: TextStyle(fontSize: 11, color: hx.secondary),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            'Daily neurological load points accumulated from completed workouts.',
            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
          ),
          const SizedBox(height: HxSpace.x4),
          SizedBox(
            height: 140,
            child: BarChart(
              BarChartData(
                maxY: max(maxLoad * 1.15, 2.0),
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxLoad > 4 ? 2 : 1,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: hx.outlineVariant.withValues(alpha: 0.15),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 7,
                      getTitlesWidget: (val, meta) {
                        final idx = val.toInt();
                        if (idx < 0 || idx >= daily.length) return const SizedBox.shrink();
                        final d = daily[idx].day;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('d. MMM').format(d),
                            style: TextStyle(fontSize: 9, color: hx.secondary),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => hx.surfaceContainer,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final day = daily[group.x.toInt()];
                      return BarTooltipItem(
                        '${DateFormat('E, d. MMM').format(day.day)}\n',
                        TextStyle(fontSize: 11, color: hx.secondary),
                        children: [
                          TextSpan(
                            text: '${day.load.toStringAsFixed(2)} pts',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: hx.primary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                barGroups: [
                  for (final (i, d) in daily.indexed)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: d.load > 0 ? d.load : 0.03,
                          width: 6,
                          color: d.load == 0
                              ? hx.outlineVariant.withValues(alpha: 0.25)
                              : (d.load > 3.0
                                  ? hx.danger
                                  : (d.load > 1.5 ? hx.warning : hx.primary)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: HxSpace.x2),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _LegendDot(color: hx.primary, label: 'Light/Mod'),
              const SizedBox(width: 12),
              _LegendDot(color: hx.warning, label: 'Heavy'),
              const SizedBox(width: 12),
              _LegendDot(color: hx.danger, label: 'High Strain'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: hx.secondary)),
      ],
    );
  }
}

// ── 4. Recent Workouts Impact Card ──────────────────────────────────────────

class _RecentWorkoutsImpactCard extends StatelessWidget {
  const _RecentWorkoutsImpactCard({required this.result});

  final CnsDetailedResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final sessions = result.recentSessions;

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WORKOUT CNS IMPACT & RESIDUAL FATIGUE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: hx.secondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            'Individual training sessions contributing to neurological strain, with 36h exponential recovery decay.',
            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
          ),
          const SizedBox(height: HxSpace.x4),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HxSpace.x4),
              child: Center(
                child: Text(
                  'No completed workouts in history.',
                  style: TextStyle(color: hx.secondary),
                ),
              ),
            )
          else
            Column(
              children: [
                for (final session in sessions.take(8))
                  _SessionImpactTile(session: session),
              ],
            ),
        ],
      ),
    );
  }
}

class _SessionImpactTile extends StatefulWidget {
  const _SessionImpactTile({required this.session});

  final SessionCnsImpact session;

  @override
  State<_SessionImpactTile> createState() => _SessionImpactTileState();
}

class _SessionImpactTileState extends State<_SessionImpactTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final session = widget.session;

    final hasResidual = session.hasActiveResidualFatigue;
    final residualPct = (session.currentResidualFatigue * 100).round();

    final dateStr = DateFormat('E, d. MMM · HH:mm').format(session.sessionDate);
    final hoursAgo = DateTime.now().difference(session.sessionDate).inHours;
    final timeAgoStr = hoursAgo < 24
        ? '${hoursAgo}h ago'
        : '${(hoursAgo / 24).round()}d ago';

    return Container(
      margin: const EdgeInsets.only(bottom: HxSpace.x3),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(HxRadius.md),
        border: Border.all(
          color: hasResidual
              ? hx.domainRecovery.withValues(alpha: 0.35)
              : hx.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(HxRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(HxSpace.x3),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: (hasResidual ? hx.domainRecovery : hx.secondary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(HxRadius.sm),
                    ),
                    child: Icon(
                      Icons.fitness_center,
                      size: 18,
                      color: hasResidual ? hx.domainRecovery : hx.secondary,
                    ),
                  ),
                  const SizedBox(width: HxSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.workoutName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$dateStr ($timeAgoStr) • ${session.setCount} sets',
                          style: TextStyle(fontSize: 11, color: hx.secondary),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (hasResidual)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: hx.danger.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+$residualPct% active',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: hx.danger,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: hx.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Recovered',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: hx.success,
                            ),
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        '${session.totalLoad.toStringAsFixed(2)} load',
                        style: TextStyle(
                          fontSize: 11,
                          color: hx.secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: hx.secondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(HxSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SET-BY-SET CNS BREAKDOWN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: hx.secondary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        'Avg RPE ${session.avgRpe.toStringAsFixed(1)}',
                        style: TextStyle(fontSize: 10, color: hx.secondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: HxSpace.x2),
                  for (final s in session.sets)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      s.exerciseName,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (s.hasWeightedBonus) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: hx.primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '+2 weighted',
                                          style: TextStyle(fontSize: 8, color: hx.primary, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  'CNS ${s.effectiveCnsScore}/10 · RPE ${s.rpe.toStringAsFixed(1)} (${s.rpeFactor}×) · ${s.setType.label}',
                                  style: TextStyle(fontSize: 10, color: hx.secondary),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${s.setLoad.toStringAsFixed(2)} pts',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: hx.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 5. Top CNS-Taxing Exercises Card ────────────────────────────────────────

class _TopCnsExercisesCard extends StatelessWidget {
  const _TopCnsExercisesCard({required this.result});

  final CnsDetailedResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final exercises = result.topCnsExercises;

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MOST NEUROLOGICALLY DEMANDING EXERCISES',
            style: theme.textTheme.labelSmall?.copyWith(
              color: hx.secondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            'Exercises contributing the highest total CNS fatigue in your logged training.',
            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
          ),
          const SizedBox(height: HxSpace.x4),
          if (exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HxSpace.x4),
              child: Center(
                child: Text(
                  'No exercises logged yet.',
                  style: TextStyle(color: hx.secondary),
                ),
              ),
            )
          else
            Column(
              children: [
                for (final ex in exercises.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: HxSpace.x3),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _cnsScoreColor(hx, ex.cnsScore).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${ex.cnsScore}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _cnsScoreColor(hx, ex.cnsScore),
                            ),
                          ),
                        ),
                        const SizedBox(width: HxSpace.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      ex.exerciseName,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (ex.isWeightedBodyweight) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: hx.primary.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '+2 weighted',
                                        style: TextStyle(fontSize: 8, color: hx.primary, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                '${ex.targetMuscle} • ${ex.totalSets} sets • Avg RPE ${ex.avgRpe.toStringAsFixed(1)}',
                                style: TextStyle(fontSize: 11, color: hx.secondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: HxSpace.x2),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${ex.totalLoadContribution.toStringAsFixed(1)} pts',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: hx.primary,
                              ),
                            ),
                            Text('total CNS', style: TextStyle(fontSize: 9, color: hx.secondary)),
                          ],
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

  Color _cnsScoreColor(HxColors hx, int score) {
    if (score >= 8) return hx.danger;
    if (score >= 6) return hx.warning;
    return hx.primary;
  }
}

// ── 6. Calculation Engine Transparency Explainer ────────────────────────────

class _CnsEngineExplainerCard extends StatelessWidget {
  const _CnsEngineExplainerCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return HxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.functions, size: 18, color: hx.primary),
              const SizedBox(width: 8),
              Text(
                'HOW HERCULEX CALCULATES CNS STRAIN',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hx.secondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            'Central nervous system fatigue is computed for every completed set using 4 physiological variables:',
            style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
          ),
          const SizedBox(height: HxSpace.x4),
          _FormulaStepTile(
            number: '1',
            title: 'Exercise CNS Cost (1–10 scale)',
            description:
                'Axial heavy compound movements (Deadlifts, Squats, Weighted Pull-ups) require maximal motor-unit recruitment (8–10), while isolation work (Curls, Raises) creates minimal neurological fatigue (2–4). Weighted bodyweight lifts gain an automatic +2 intensity bump.',
            accent: hx.primary,
          ),
          const SizedBox(height: HxSpace.x3),
          _FormulaStepTile(
            number: '2',
            title: 'RPE Proximity to Failure Multiplier',
            description:
                'Sets at or near true failure impose exponentially higher central fatigue:\n• RPE ≥ 9.0 (0–1 RIR) → 1.5× strain multiplier\n• RPE ≥ 8.0 (2 RIR) → 1.3× strain multiplier\n• Submaximal (RPE < 8) → 1.0× multiplier',
            accent: hx.warning,
          ),
          const SizedBox(height: HxSpace.x3),
          _FormulaStepTile(
            number: '3',
            title: 'Advanced Set Technique Modifiers',
            description:
                'Techniques extending past concentric failure increase neurological stress:\n• Forced Reps & Negatives → 1.3×\n• Rest-Pause Sets → 1.2×\n• Pause Reps → 1.1×\n• Standard Sets → 1.0×',
            accent: hx.domainFasting,
          ),
          const SizedBox(height: HxSpace.x3),
          _FormulaStepTile(
            number: '4',
            title: 'Exponential Recovery Decay (36h Half-Life)',
            description:
                'Fatigue decays along an exponential half-life curve (t½ = 36 hours) across a 96-hour rolling window. Every set begins decaying the moment it is completed.',
            accent: hx.domainRecovery,
          ),
          const SizedBox(height: HxSpace.x4),
          // Formula Summary Container
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(HxSpace.x3),
            decoration: BoxDecoration(
              color: hx.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(HxRadius.md),
              border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MATHEMATICAL FORMULA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hx.primary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set Load = (CNS Score / 10) × RPE Multiplier × Set Type Multiplier',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: hx.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Active Fatigue = Σ 0.08 × Set Load × e^(-Δt · ln(2) / 36h)',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: hx.domainRecovery,
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

class _FormulaStepTile extends StatelessWidget {
  const _FormulaStepTile({
    required this.number,
    required this.title,
    required this.description,
    required this.accent,
  });

  final String number;
  final String title;
  final String description;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Text(
            number,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: HxSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hx.secondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
