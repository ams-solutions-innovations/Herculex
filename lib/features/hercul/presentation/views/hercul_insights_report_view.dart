import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/features/hercul/application/hercul_providers.dart';
import 'package:herculex/features/hercul/domain/hercul_assessment.dart';
import 'package:herculex/features/hercul/domain/hercul_rule.dart';
import 'package:herculex/features/labs/application/labs_providers.dart';

/// Dedicated full-screen Hercul Insights Report page.
///
/// Kept visual and short: overall status, four dimension tiles (details one
/// tap away), a compact list of lifestyle drivers, a Labs shortcut and the
/// few insights that are firing right now.
class HerculInsightsReportView extends ConsumerStatefulWidget {
  const HerculInsightsReportView({super.key});

  @override
  ConsumerState<HerculInsightsReportView> createState() =>
      _HerculInsightsReportViewState();
}

class _HerculInsightsReportViewState
    extends ConsumerState<HerculInsightsReportView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final reportAsync = ref.watch(herculInsightsReportProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_rounded, color: hx.primary, size: 22),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Hercul Insights',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not generate Hercul Insights.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ),
        data: (report) {
          final messages = report.messages.take(2).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            children: [
              _OverallStatusHeroCard(report: report),
              const SizedBox(height: 16),
              for (final msg in messages) ...[
                _ReportMessageCard(message: msg),
                const SizedBox(height: 8),
              ],
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const Key('hercul-insights-details'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Details'),
                  subtitle: const Text(
                    'Weight, lifting, water, recovery and drivers',
                  ),
                  children: [
                    _TileGrid(
                      tiles: [
                        _DimensionTile(
                          label: 'Weight',
                          assessment: report.bodyweightAssessment,
                          icon: Icons.monitor_weight_outlined,
                        ),
                        _DimensionTile(
                          label: 'Lifting',
                          assessment: report.liftingAssessment,
                          icon: Icons.fitness_center_rounded,
                        ),
                        _DimensionTile(
                          label: 'Water',
                          assessment: report.waterRetentionAssessment,
                          icon: Icons.water_drop_outlined,
                        ),
                        _DimensionTile(
                          label: 'Recovery',
                          assessment: report.regenerationAssessment,
                          icon: Icons.battery_charging_full_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _SectionTitle('Drivers'),
                    const SizedBox(height: 8),
                    _DriversCard(factors: report.factors),
                    if (labsEnabled) ...[
                      const SizedBox(height: 12),
                      const _LabsTile(),
                    ],
                    for (final msg in report.messages.skip(2)) ...[
                      _ReportMessageCard(message: msg),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Color herculStatusColor(BuildContext context, HerculGlanceStatus status) {
  final hx = context.hx;
  return switch (status) {
    HerculGlanceStatus.great => hx.success,
    HerculGlanceStatus.good => hx.primary,
    HerculGlanceStatus.notGood => hx.warning,
    HerculGlanceStatus.bad => hx.danger,
  };
}

IconData herculStatusIcon(HerculGlanceStatus status) {
  return switch (status) {
    HerculGlanceStatus.great => Icons.verified_rounded,
    HerculGlanceStatus.good => Icons.thumb_up_alt_rounded,
    HerculGlanceStatus.notGood => Icons.warning_amber_rounded,
    HerculGlanceStatus.bad => Icons.error_outline_rounded,
  };
}

String _domainLabel(HerculDomain domain) => switch (domain) {
  HerculDomain.recovery => 'Recovery & CNS',
  HerculDomain.volume => 'Lifting & Volume',
  HerculDomain.nutrition => 'Nutrition & Fuel',
  HerculDomain.bodyweight => 'Bodyweight & Water',
  HerculDomain.consistency => 'Consistency',
  HerculDomain.ergonomics => 'Biomechanics',
};

IconData _domainIcon(HerculDomain domain) => switch (domain) {
  HerculDomain.recovery => Icons.battery_charging_full_rounded,
  HerculDomain.volume => Icons.fitness_center_rounded,
  HerculDomain.nutrition => Icons.restaurant_rounded,
  HerculDomain.bodyweight => Icons.monitor_weight_outlined,
  HerculDomain.consistency => Icons.calendar_month_rounded,
  HerculDomain.ergonomics => Icons.accessibility_new_rounded,
};

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _OverallStatusHeroCard extends StatelessWidget {
  final HerculInsightsReport report;

  const _OverallStatusHeroCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final statusColor = herculStatusColor(context, report.overallStatus);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withValues(alpha: hx.isDark ? 0.22 : 0.14),
            hx.surfaceContainerLowest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                herculStatusIcon(report.overallStatus),
                size: 22,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  report.overallStatus.label,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${report.overallScore}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                  height: 1,
                ),
              ),
              Text(
                '/100',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: hx.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final tier in HerculGlanceStatus.values) ...[
                if (tier != HerculGlanceStatus.values.first)
                  const SizedBox(width: 6),
                Expanded(
                  child: _TierBar(
                    tier: tier,
                    selected: tier == report.overallStatus,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            report.glanceHeadline,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _TierBar extends StatelessWidget {
  final HerculGlanceStatus tier;
  final bool selected;

  const _TierBar({required this.tier, required this.selected});

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final color = herculStatusColor(context, tier);
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 8,
          decoration: BoxDecoration(
            color: selected ? color : hx.surfaceVariant.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tier.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? color : hx.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Lays [tiles] out two per row with equal heights per row.
class _TileGrid extends StatelessWidget {
  final List<Widget> tiles;

  const _TileGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (i > 0) {
        rows.add(const SizedBox(height: 10));
      }
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

/// One dimension at a glance: icon, name, the key number. Tap for the why.
class _DimensionTile extends StatelessWidget {
  final String label;
  final HerculDimensionAssessment assessment;
  final IconData icon;

  const _DimensionTile({
    required this.label,
    required this.assessment,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final color = herculStatusColor(context, assessment.status);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _showDetails(context, color),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: hx.isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  herculStatusIcon(assessment.status),
                  size: 14,
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              assessment.metricBadge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, Color color) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final hx = ctx.hx;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        assessment.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _StatusBadge(status: assessment.status),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  assessment.headline,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  assessment.explanation,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hx.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                if (assessment.keyDrivers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final driver in assessment.keyDrivers)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            driver,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lifestyle factors as one compact list: icon, name, value, status dot.
class _DriversCard extends StatelessWidget {
  final List<HerculFactorImpact> factors;

  const _DriversCard({required this.factors});

  static IconData _icon(String id) => switch (id) {
    'fasting' => Icons.timer_outlined,
    'alcohol' => Icons.local_bar_outlined,
    'creatine' => Icons.bolt_rounded,
    'carbs_before_bed' => Icons.nights_stay_outlined,
    'hydration_sodium' => Icons.water_drop_outlined,
    _ => Icons.bedtime_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Container(
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < factors.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: hx.outlineVariant.withValues(alpha: 0.25),
              ),
            InkWell(
              onTap: factors[i].route == null
                  ? null
                  : () => context.push(factors[i].route!),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      _icon(factors[i].id),
                      size: 18,
                      color: herculStatusColor(context, factors[i].status),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            factors[i].title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            factors[i].valueLabel,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: hx.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: herculStatusColor(context, factors[i].status),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shortcut into the Labs feature, with this week's finding count when Labs
/// is switched on.
class _LabsTile extends ConsumerWidget {
  const _LabsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final enabled = ref.watch(labsConsentProvider).enabled;
    final count = enabled
        ? ref.watch(labsSnapshotProvider(7)).valueOrNull?.findings.length
        : null;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push(AppRoutes.labs),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.science_outlined, size: 20, color: hx.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Labs',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              !enabled
                  ? 'Turn on'
                  : count == null
                  ? ''
                  : count == 0
                  ? 'Nothing flagged'
                  : '$count this week',
              style: theme.textTheme.labelMedium?.copyWith(
                color: hx.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: hx.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final HerculGlanceStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = herculStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _ReportMessageCard extends ConsumerWidget {
  final HerculMessage message;

  const _ReportMessageCard({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final status = HerculInsightsReport.classifyMessage(message);
    final statusColor = herculStatusColor(context, status);
    final cta = message.cta;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: cta == null
          ? null
          : () {
              if (cta.type == 'route') {
                context.push(cta.value);
              }
              ref.read(herculLogFiredProvider)(message.ruleId);
            },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: statusColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_domainIcon(message.domain), size: 18, color: statusColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _domainLabel(message.domain),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hx.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message.text,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
            if (cta != null && cta.type == 'route')
              Icon(Icons.chevron_right_rounded, color: hx.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
