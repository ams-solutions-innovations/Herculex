import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';
import 'package:herculex/features/hercul/application/hercul_providers.dart';
import 'package:herculex/features/hercul/domain/hercul_assessment.dart';
import 'package:herculex/features/hercul/presentation/views/hercul_insights_report_view.dart';

/// Non-scrollable glance widget for Hercul Insights on the Dashboard.
///
/// Displays a 4-tier glance status (`Great`, `Good`, `Not Good`, `Bad`),
/// physiological quick-metrics (Water Retention, Lifting Load, Regeneration),
/// and a concise summary. Tapping opens the dedicated [HerculInsightsReportView].
class HerculInsightsCard extends ConsumerWidget {
  const HerculInsightsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final reportAsync = ref.watch(herculInsightsReportProvider);

    final accentColor = reportAsync.maybeWhen(
      data: (r) => herculStatusColor(context, r.overallStatus),
      orElse: () => hx.primary,
    );

    return dashboardCard(
      accent: accentColor,
      onTap: () => context.push(AppRoutes.herculInsights),
      padding: const EdgeInsets.all(16),
      child: reportAsync.when(
        loading: () => _buildLoadingState(context),
        error: (_, _) => _buildErrorState(context),
        data: (report) => LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 230;
            if (isCompact) {
              return _CompactGlanceView(report: report);
            }
            return _FullGlanceView(report: report);
          },
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return Row(
      children: [
        Icon(Icons.psychology_outlined, size: 20, color: hx.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Hercul Insights',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return Row(
      children: [
        Icon(Icons.psychology_outlined, size: 20, color: hx.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Hercul Insights · Tap to view report',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 20, color: hx.onSurfaceVariant),
      ],
    );
  }
}

class _FullGlanceView extends StatelessWidget {
  final HerculInsightsReport report;

  const _FullGlanceView({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final statusColor = herculStatusColor(context, report.overallStatus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header row: Title + Status Badge + Report chevron
        Row(
          children: [
            Icon(Icons.psychology_rounded, size: 20, color: statusColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hercul Insights',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: statusColor.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    herculStatusIcon(report.overallStatus),
                    size: 13,
                    color: statusColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    report.overallStatus.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: hx.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 4-tier glance bar: the active tier is lit, the badge above names it.
        Row(
          children: [
            for (final tier in HerculGlanceStatus.values) ...[
              if (tier != HerculGlanceStatus.values.first)
                const SizedBox(width: 4),
              Expanded(
                child: _GlanceTierSegment(
                  tier: tier,
                  active: tier == report.overallStatus,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          report.glanceHeadline,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        // One row, never wraps: the card has a fixed height.
        Row(
          children: [
            Flexible(
              child: _MiniMetricChip(
                icon: Icons.water_drop_outlined,
                label: report.waterRetentionAssessment.metricBadge,
                status: report.waterRetentionAssessment.status,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: _MiniMetricChip(
                icon: Icons.battery_charging_full_rounded,
                label: report.regenerationAssessment.metricBadge,
                status: report.regenerationAssessment.status,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CompactGlanceView extends StatelessWidget {
  final HerculInsightsReport report;

  const _CompactGlanceView({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final statusColor = herculStatusColor(context, report.overallStatus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.psychology_rounded, size: 17, color: statusColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Insights',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: hx.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: statusColor.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                herculStatusIcon(report.overallStatus),
                size: 14,
                color: statusColor,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  report.overallStatus.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${report.regenerationAssessment.metricBadge} · ${report.waterRetentionAssessment.metricBadge}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: hx.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _GlanceTierSegment extends StatelessWidget {
  final HerculGlanceStatus tier;
  final bool active;

  const _GlanceTierSegment({required this.tier, required this.active});

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final color = herculStatusColor(context, tier);
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: active ? color : hx.surfaceVariant.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _MiniMetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final HerculGlanceStatus status;

  const _MiniMetricChip({
    required this.icon,
    required this.label,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final color = herculStatusColor(context, status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: hx.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
