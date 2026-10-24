// lib/features/sleep/presentation/widgets/sleep_weightlifting_impact_card.dart
import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/sleep/domain/sleep_weightlifting_impact.dart';

/// Comprehensive card explaining exact athletic impact on weightlifting and training.
class SleepWeightliftingImpactCard extends StatelessWidget {
  final SleepWeightliftingImpact impact;

  const SleepWeightliftingImpactCard({super.key, required this.impact});

  Color _badgeColor(LiftingReadinessLevel level) {
    switch (level) {
      case LiftingReadinessLevel.peak:
        return const Color(0xFF10B981); // Emerald
      case LiftingReadinessLevel.normal:
        return const Color(0xFF6366F1); // Indigo
      case LiftingReadinessLevel.cautious:
        return const Color(0xFFF59E0B); // Amber
      case LiftingReadinessLevel.compromised:
        return const Color(0xFFEF4444); // Red
    }
  }

  IconData _badgeIcon(LiftingReadinessLevel level) {
    switch (level) {
      case LiftingReadinessLevel.peak:
        return Icons.offline_bolt_rounded;
      case LiftingReadinessLevel.normal:
        return Icons.fitness_center_rounded;
      case LiftingReadinessLevel.cautious:
        return Icons.warning_amber_rounded;
      case LiftingReadinessLevel.compromised:
        return Icons.dangerous_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = _badgeColor(impact.readinessLevel);

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      color: accentColor.withValues(alpha: 0.05),
      border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _badgeIcon(impact.readinessLevel),
                  color: accentColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      impact.statusBadge,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                        letterSpacing: 1.0,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      impact.headline,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 4-Key Lifting Modifiers Grid
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricCol(
                  label: 'VOLUME MOD',
                  value: '${(impact.volumeFactor * 100).round()}%',
                  subtitle: impact.volumeFactor < 1.0
                      ? '-${((1.0 - impact.volumeFactor) * 100).round()}% sets'
                      : 'Full capacity',
                  color: accentColor,
                  theme: theme,
                ),
                Container(width: 1, height: 36, color: Colors.white10),
                _buildMetricCol(
                  label: 'CNS DRIVE',
                  value: '${impact.cnsReadinessPercent}%',
                  subtitle: 'Rate coding',
                  color: const Color(0xFF8B5CF6),
                  theme: theme,
                ),
                Container(width: 1, height: 36, color: Colors.white10),
                _buildMetricCol(
                  label: '1RM CAPACITY',
                  value: '${impact.strengthCapacityPercent}%',
                  subtitle: 'Neural output',
                  color: const Color(0xFF06B6D4),
                  theme: theme,
                ),
                Container(width: 1, height: 36, color: Colors.white10),
                _buildMetricCol(
                  label: 'TARGET RPE',
                  value: '≤ ${impact.maxRecommendedRpe.toStringAsFixed(1)}',
                  subtitle: 'Exertion cap',
                  color: const Color(0xFFF59E0B),
                  theme: theme,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Physiology section: CNS & Tissue Breakdown
          Text(
            'PHYSIOLOGICAL IMPACT',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              letterSpacing: 1.0,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          _buildPhysioCard(
            title: 'Neural Motor Unit Recruitment',
            description: impact.cnsExplanation,
            icon: Icons.psychology_rounded,
            color: const Color(0xFF8B5CF6),
            theme: theme,
          ),
          const SizedBox(height: 10),
          _buildPhysioCard(
            title: 'Growth Hormone & Tissue Synthesis',
            description: impact.muscleRepairExplanation,
            icon: Icons.healing_rounded,
            color: const Color(0xFF10B981),
            theme: theme,
          ),
          const SizedBox(height: 20),

          // Actionable Pre-Workout Recommendations
          Text(
            'TACTICAL PRE-WORKOUT PROTOCOL',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              letterSpacing: 1.0,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ...impact.tacticalTips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 10,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tip,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCol({
    required String label,
    required String value,
    required String subtitle,
    required Color color,
    required ThemeData theme,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.secondary,
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 15,
          ),
        ),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.tertiary,
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  Widget _buildPhysioCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                    fontSize: 11,
                    height: 1.35,
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
