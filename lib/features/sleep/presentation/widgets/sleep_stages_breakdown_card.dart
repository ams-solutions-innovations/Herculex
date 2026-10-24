// lib/features/sleep/presentation/widgets/sleep_stages_breakdown_card.dart
import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/sleep/domain/sleep_record.dart';

/// Card showing segmented sleep stages (Deep, REM, Light, Awake) with physical and CNS benefits.
class SleepStagesBreakdownCard extends StatelessWidget {
  final SleepRecord? record;

  const SleepStagesBreakdownCard({super.key, required this.record});

  String _formatMins(double mins) {
    final h = (mins / 60).floor();
    final m = (mins % 60).round();
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stages = record?.stages;
    final hasStages = stages != null && stages.totalSleepMinutes > 0;

    // Fallback estimates if wearable only reported total sleep hours
    final deepMins = hasStages
        ? stages.deepMinutes
        : (record != null ? record!.totalHours * 60 * 0.20 : 0.0);
    final remMins = hasStages
        ? stages.remMinutes
        : (record != null ? record!.totalHours * 60 * 0.22 : 0.0);
    final lightMins = hasStages
        ? stages.lightMinutes
        : (record != null ? record!.totalHours * 60 * 0.53 : 0.0);
    final awakeMins = hasStages
        ? stages.awakeMinutes
        : (record != null ? record!.totalHours * 60 * 0.05 : 0.0);

    final totalMins = deepMins + remMins + lightMins + awakeMins;
    final deepFlex = totalMins > 0
        ? (deepMins / totalMins * 1000).round()
        : 200;
    final remFlex = totalMins > 0 ? (remMins / totalMins * 1000).round() : 220;
    final lightFlex = totalMins > 0
        ? (lightMins / totalMins * 1000).round()
        : 530;
    final awakeFlex = totalMins > 0
        ? (awakeMins / totalMins * 1000).round()
        : 50;

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SLEEP STAGES & CYCLES',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              if (!hasStages && record != null)
                Text(
                  'ESTIMATED',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.tertiary,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Horizontal segmented gradient bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Row(
                children: [
                  Expanded(
                    flex: deepFlex > 0 ? deepFlex : 1,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: remFlex > 0 ? remFlex : 1,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF8B5CF6), Color(0xFFA855F7)],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: lightFlex > 0 ? lightFlex : 1,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF06B6D4), Color(0xFF22D3EE)],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: awakeFlex > 0 ? awakeFlex : 1,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2x2 Grid of stage insights
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              _buildStageTile(
                name: 'DEEP SLEEP',
                duration: _formatMins(deepMins),
                percent:
                    '${(deepMins / (totalMins > 0 ? totalMins : 1) * 100).round()}%',
                benefit: 'HGH & Tissue Repair',
                color: const Color(0xFF6366F1),
                theme: theme,
              ),
              _buildStageTile(
                name: 'REM SLEEP',
                duration: _formatMins(remMins),
                percent:
                    '${(remMins / (totalMins > 0 ? totalMins : 1) * 100).round()}%',
                benefit: 'CNS Motor Recruitment',
                color: const Color(0xFFA855F7),
                theme: theme,
              ),
              _buildStageTile(
                name: 'LIGHT SLEEP',
                duration: _formatMins(lightMins),
                percent:
                    '${(lightMins / (totalMins > 0 ? totalMins : 1) * 100).round()}%',
                benefit: 'Metabolic Clearance',
                color: const Color(0xFF06B6D4),
                theme: theme,
              ),
              _buildStageTile(
                name: 'AWAKE TIME',
                duration: _formatMins(awakeMins),
                percent:
                    '${(awakeMins / (totalMins > 0 ? totalMins : 1) * 100).round()}%',
                benefit: 'Sleep Continuity',
                color: const Color(0xFFF59E0B),
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStageTile({
    required String name,
    required String duration,
    required String percent,
    required String benefit,
    required Color color,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.secondary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  percent,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          Text(
            duration,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            benefit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.tertiary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
