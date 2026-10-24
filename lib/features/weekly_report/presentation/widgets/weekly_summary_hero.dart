import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_payload.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_summary.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/section_card_scaffold.dart';

/// The week in one glance, above the measured sections: a verdict, one line
/// of why, and four numbers. Purely deterministic.
class WeeklySummaryHero extends ConsumerWidget {
  const WeeklySummaryHero({
    super.key,
    required this.payload,
    required this.week,
  });

  final WeeklyReportPayload payload;
  final IsoWeek week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final planned = ref.watch(weeklyPlannedSessionsProvider(week)).valueOrNull;
    final summary = WeeklyReportSummary.from(payload, plannedSessions: planned);
    final accent = switch (summary.verdict) {
      WeekVerdict.great => hx.success,
      WeekVerdict.good => hx.primary,
      WeekVerdict.mixed => hx.warning,
      WeekVerdict.quiet => hx.onSurfaceVariant,
    };

    return HxCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.verdict.label,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: HxSpace.x1),
          Text(summary.detail, style: ReportText.label(context)),
          const SizedBox(height: HxSpace.x4),
          Row(
            children: [
              _Figure(
                icon: Icons.fitness_center_rounded,
                value: planned != null && planned > 0
                    ? '${summary.sessions}/$planned'
                    : '${summary.sessions}',
                label: 'Workouts',
              ),
              _Figure(
                icon: Icons.restaurant_rounded,
                value: summary.avgKcal == null
                    ? '—'
                    : '${summary.avgKcal} kcal',
                label: summary.targetKcal == null
                    ? 'Avg / day'
                    : 'Goal ${summary.targetKcal}',
              ),
              _Figure(
                icon: Icons.bedtime_outlined,
                value: summary.avgSleepHours == null
                    ? '—'
                    : '${summary.avgSleepHours!.toStringAsFixed(1)} h',
                label: 'Sleep',
              ),
              _Figure(
                icon: Icons.monitor_weight_outlined,
                value: _weightDelta(summary.bodyweightDeltaKg),
                label: 'Weight',
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _weightDelta(double? delta) {
    if (delta == null) return '—';
    final sign = delta > 0
        ? '+'
        : delta < 0
        ? '−'
        : '±';
    return '$sign${delta.abs().toStringAsFixed(1)} kg';
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: hx.onSurfaceVariant),
          const SizedBox(height: HxSpace.x1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: ReportText.body(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ReportText.label(context),
          ),
        ],
      ),
    );
  }
}
