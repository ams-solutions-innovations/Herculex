import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/analytics/data/analytics_repository.dart';
import 'package:herculex/features/analytics/domain/insights_week_summary.dart';
import 'package:herculex/features/analytics/presentation/widgets/cns_recovery_cards.dart';
import 'package:herculex/features/labs/presentation/labs_view.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/weekly_reports_entry_card.dart';
import 'package:intl/intl.dart';

part 'insights_view/_training_cards.part.dart';
part 'insights_view/_correlation_cards.part.dart';

/// Insights leads with what matters this week — three numbers and one piece
/// of advice — then the weekly reports, Labs and top lifts. The detailed
/// analytics (recovery map, CNS chart, balance, correlations) sit under
/// "More analytics" for the users who want them.
class InsightsView extends ConsumerWidget {
  const InsightsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HxScreenShell(
      title: 'Insights',
      children: [
        const _ThisWeekHero(),
        const SizedBox(height: 16),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            childrenPadding: EdgeInsets.zero,
            title: Text(
              'More analytics',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Muscle recovery, CNS load, balance, volume and correlations',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.hx.secondary),
            ),
            children: const [
              SizedBox(height: 8),
              WeeklyReportsEntryCard(),
              SizedBox(height: 12),
              LabsEntryCard(),
              SizedBox(height: 16),
              _OneRmCard(),
              SizedBox(height: 16),
              RecoveryDetailCard(),
              SizedBox(height: 16),
              CnsTrendCard(),
              SizedBox(height: 16),
              _BalanceCard(),
              SizedBox(height: 16),
              _TonnageCard(),
              SizedBox(height: 16),
              _SleepVsRpeCard(),
              SizedBox(height: 16),
              _HrVsTonnageCard(),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThisWeekHero extends ConsumerWidget {
  const _ThisWeekHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final summary = ref.watch(insightsWeekSummaryProvider);
    final weight = ref.watch(weightFormatProvider);

    return HxCard(
      accent: hx.domainTraining,
      child: summary.when(
        loading: () => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const Text('Could not load this week.'),
        data: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'THIS WEEK',
              style: theme.textTheme.labelSmall?.copyWith(
                color: hx.secondary,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _HeroNumber(
                    value: '${s.sessions}',
                    label: s.sessions == 1 ? 'workout' : 'workouts',
                  ),
                ),
                Expanded(
                  child: _HeroNumber(
                    value: weight.format(s.tonnageKg),
                    label: _changeLabel(s),
                  ),
                ),
                Expanded(
                  child: _HeroNumber(
                    value: '${(s.readiness * 100).round()}%',
                    label: 'ready',
                    color: _readinessColor(hx, s.readiness),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 18,
                  color: hx.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(s.advice, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _changeLabel(InsightsWeekSummary s) {
    final change = s.tonnageChange;
    if (change == null) {
      return 'volume';
    }
    final pct = (change * 100).round();
    return pct >= 0 ? '+$pct% vs last wk' : '$pct% vs last wk';
  }

  static Color _readinessColor(HxColors hx, double readiness) {
    if (readiness >= 0.6) {
      return hx.success;
    }
    if (readiness >= 0.3) {
      return hx.warning;
    }
    return hx.danger;
  }
}

class _HeroNumber extends StatelessWidget {
  const _HeroNumber({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: context.hx.secondary,
          ),
        ),
      ],
    );
  }
}
