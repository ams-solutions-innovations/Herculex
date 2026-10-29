import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/analytics/application/analytics_providers.dart';
import 'package:herculex/features/analytics/data/analytics_repository.dart';
import 'package:herculex/features/analytics/domain/insights_week_summary.dart';
import 'package:herculex/features/analytics/presentation/widgets/cns_recovery_cards.dart';
import 'package:herculex/features/labs/presentation/labs_view.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/weekly_reports_entry_card.dart';
import 'package:intl/intl.dart';

part 'insights_view/_training_cards.part.dart';
part 'insights_view/_correlation_cards.part.dart';

/// Insights provides a high-level view of training, recovery, and readiness.
///
/// On desktop screens (width >= 840px), it presents a full-fledged multi-column
/// analytics dashboard: a prominent weekly hero card alongside entry points
/// for weekly reports and labs, followed by a balanced two-column grid
/// featuring recovery details, CNS trends, muscle balance, 1RM estimates,
/// tonnage progression, and biometric correlations.
///
/// On mobile screens (< 840px), detailed analytics remain organized under a
/// collapsible "More analytics" section to keep the primary view compact.
class InsightsView extends ConsumerWidget {
  const InsightsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= HxBreakpoints.rail;

    return HxScreenShell(
      title: 'Insights',
      showBack: false,
      maxContentWidth: isDesktop
          ? HxBreakpoints.wideMax
          : HxBreakpoints.readingMax,
      children: [
        if (isDesktop) ...[
          // ── Top Section: Hero card alongside entry cards ───────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: _ThisWeekHero(isDesktop: true),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    WeeklyReportsEntryCard(),
                    SizedBox(height: 12),
                    LabsEntryCard(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Performance & Recovery',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          // ── Main Analytics Grid (2 balanced columns) ───────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    RecoveryDetailCard(),
                    SizedBox(height: 16),
                    CnsTrendCard(),
                    SizedBox(height: 16),
                    _BalanceCard(),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Right Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    _OneRmCard(),
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
          ),
          const SizedBox(height: 32),
        ] else ...[
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
      ],
    );
  }
}

class _ThisWeekHero extends ConsumerWidget {
  const _ThisWeekHero({this.isDesktop = false});

  final bool isDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final theme = Theme.of(context);
    final summary = ref.watch(insightsWeekSummaryProvider);
    final weight = ref.watch(weightFormatProvider);

    return HxCard(
      accent: hx.domainTraining,
      padding: EdgeInsets.all(isDesktop ? HxSpace.x6 : HxSpace.x5),
      child: summary.when(
        loading: () => SizedBox(
          height: isDesktop ? 160 : 120,
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const Text('Could not load this week.'),
        data: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDesktop)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: hx.domainTraining.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hx.domainTraining.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          size: 14,
                          color: hx.domainTraining,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'THIS WEEK',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: hx.domainTraining,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Live Pulse',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hx.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else
              Text(
                'THIS WEEK',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hx.secondary,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            SizedBox(height: isDesktop ? 16 : 12),
            Row(
              children: [
                Expanded(
                  child: _HeroNumber(
                    value: '${s.sessions}',
                    label: s.sessions == 1 ? 'workout' : 'workouts',
                    isDesktop: isDesktop,
                  ),
                ),
                Expanded(
                  child: _HeroNumber(
                    value: weight.format(s.tonnageKg),
                    label: _changeLabel(s),
                    isDesktop: isDesktop,
                  ),
                ),
                Expanded(
                  child: _HeroNumber(
                    value: '${(s.readiness * 100).round()}%',
                    label: 'ready',
                    color: _readinessColor(hx, s.readiness),
                    isDesktop: isDesktop,
                  ),
                ),
              ],
            ),
            SizedBox(height: isDesktop ? 18 : 14),
            if (isDesktop)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: hx.surfaceContainerLowest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hx.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 18,
                      color: hx.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.advice,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
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
  const _HeroNumber({
    required this.value,
    required this.label,
    this.color,
    this.isDesktop = false,
  });

  final String value;
  final String label;
  final Color? color;
  final bool isDesktop;

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
            style: (isDesktop
                    ? theme.textTheme.headlineMedium
                    : theme.textTheme.headlineSmall)
                ?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: context.hx.secondary,
            fontWeight: isDesktop ? FontWeight.w600 : null,
          ),
        ),
      ],
    );
  }
}
