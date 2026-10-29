import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/application/physique_schedule_provider.dart';
import 'package:herculex/features/physique/data/physique_date_keys.dart';
import 'package:herculex/features/physique/domain/goal_progress.dart';
import 'package:herculex/features/physique/presentation/widgets/physique_design_kit.dart';

/// Weight, body fat, waist and lean mass in a 2 × 2 grid: where each stands,
/// how far it moved since the goal began, and how much of the way it is.
class ProgressMetricsGrid extends ConsumerWidget {
  const ProgressMetricsGrid({super.key, required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
    if (goal == null) return const SizedBox.shrink();
    final wf = ref.watch(weightFormatProvider);
    final logs =
        ref.watch(physiqueWeightLogsProvider).asData?.value ?? const [];
    final bf = ref.watch(physiqueBodyFatReadingProvider(goalId));
    final waists =
        ref.watch(physiqueMeasuredWaistProvider).asData?.value ?? const [];
    final dreamKg = ref
        .watch(physiqueRoadmapScheduleProvider(goalId))
        ?.dreamWeightKg;

    // A 7-day average around the newest weigh-in steadies day-to-day noise.
    double? weight;
    if (logs.isNotEmpty) {
      final newest = logs.last.date;
      final week = [
        for (final l in logs)
          if (newest.difference(l.date).inDays < 7) l.kg,
      ];
      weight = week.reduce((a, b) => a + b) / week.length;
    }
    final startKg = goal.startWeightKg;
    final startBf = goal.startBfPercent;
    final bfNow = bf.percent;

    final since = physiqueDayKey(goal.startedAt);
    final goalWaists = [
      for (final m in waists)
        if (m.dateIso.compareTo(since) >= 0) m,
    ];
    BodyMeasurementData? firstWaist = goalWaists.firstOrNull;
    final lastWaist = goalWaists.lastOrNull;
    if (firstWaist == lastWaist) firstWaist = null;

    double? lean(double? kg, double? pct) =>
        kg == null || pct == null ? null : kg * (1 - pct / 100);
    final leanNow = lean(weight, bfNow);
    final leanStart = lean(startKg, startBf);

    String signed(double v, String unit, {int digits = 1}) {
      final text = v.abs().toStringAsFixed(digits);
      if (double.parse(text) == 0) return '±0 $unit';
      return '${v < 0 ? '−' : '+'}$text $unit';
    }

    // Moving toward the goal is green; the wrong way is amber.
    Color toward(double delta, {required bool lower}) => delta.abs() < 0.05
        ? hx.secondary
        : (delta < 0) == lower
        ? hx.success
        : hx.warning;

    final losing = dreamKg != null && startKg != null && dreamKg < startKg;
    final weightTile = _Metric(
      icon: Icons.monitor_weight_outlined,
      label: 'WEIGHT',
      value: weight == null ? '—' : wf.formatValue(weight),
      unit: wf.suffix,
      delta: weight == null || startKg == null
          ? null
          : signed(wf.toDisplay(weight) - wf.toDisplay(startKg), wf.suffix),
      deltaColor: weight == null || startKg == null
          ? hx.secondary
          : toward(weight - startKg, lower: losing),
      goal: dreamKg == null ? null : 'goal ${wf.formatValue(dreamKg)}',
      progress: weight == null || startKg == null || dreamKg == null
          ? null
          : startKg == dreamKg
          ? 1
          : ((startKg - weight) / (startKg - dreamKg)).clamp(0.0, 1.0),
      bar: hx.primary,
    );
    final bfTile = _Metric(
      icon: Icons.water_drop_outlined,
      label: 'BODY FAT',
      value: bfNow == null
          ? '—'
          : '${bf.source == PhysiqueBfSource.estimate ? '~' : ''}${bfNow.round()}',
      unit: '%',
      delta: bfNow == null || startBf == null
          ? null
          : signed(bfNow - startBf, 'pts', digits: 0),
      deltaColor: bfNow == null || startBf == null
          ? hx.secondary
          : toward(bfNow - startBf, lower: true),
      goal: goal.targetBfPercent == null
          ? null
          : 'goal ${goal.targetBfPercent!.round()}%',
      progress: GoalProgress.fraction(
        startBfPercent: startBf,
        currentBfPercent: bfNow,
        targetBfPercent: goal.targetBfPercent,
      ),
      bar: hx.primary,
    );
    final waistTile = _Metric(
      icon: Icons.straighten_rounded,
      label: 'WAIST',
      value: lastWaist == null ? '—' : lastWaist.value.round().toString(),
      unit: 'cm',
      delta: lastWaist == null || firstWaist == null
          ? null
          : signed(lastWaist.value - firstWaist.value, 'cm', digits: 0),
      deltaColor: lastWaist == null || firstWaist == null
          ? hx.secondary
          : toward(lastWaist.value - firstWaist.value, lower: true),
      goal: lastWaist == null ? 'not logged' : 'since start',
      progress: null,
      bar: hx.primary,
    );
    final leanTile = _Metric(
      icon: Icons.fitness_center_rounded,
      label: 'LEAN MASS',
      value: leanNow == null ? '—' : wf.formatValue(leanNow),
      unit: wf.suffix,
      delta: leanNow == null || leanStart == null
          ? null
          : signed(wf.toDisplay(leanNow) - wf.toDisplay(leanStart), wf.suffix),
      deltaColor: leanNow == null || leanStart == null
          ? hx.secondary
          : (leanNow - leanStart) < -0.5
          ? hx.warning
          : (leanNow - leanStart) > 0.5
          ? hx.success
          : hx.secondary,
      goal: leanNow == null || leanStart == null
          ? null
          : (leanNow - leanStart).abs() <= 0.5
          ? 'kept'
          : 'since start',
      progress: leanNow == null ? null : 1,
      bar: hx.success,
    );

    Widget row(Widget a, Widget b) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          const SizedBox(width: 8),
          Expanded(child: b),
        ],
      ),
    );
    return Column(
      children: [
        row(weightTile, bfTile),
        const SizedBox(height: 8),
        row(waistTile, leanTile),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.delta,
    required this.deltaColor,
    required this.goal,
    required this.progress,
    required this.bar,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String? delta;
  final Color deltaColor;
  final String? goal;
  final double? progress;
  final Color bar;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: physiqueCard(context, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: hx.secondary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: hx.secondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                text: value,
                style: physiqueDisplay(
                  26,
                  weight: FontWeight.w600,
                  letterSpacing: -0.6,
                ),
                children: [
                  if (value != '—')
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                        color: hx.secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  delta ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: deltaColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (goal != null)
                Flexible(
                  child: Text(
                    goal!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hx.tertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (progress != null) ...[
            const SizedBox(height: 6),
            PhysiqueBar(value: progress!, color: bar),
          ],
        ],
      ),
    );
  }
}
