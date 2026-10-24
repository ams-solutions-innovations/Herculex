import 'package:flutter/material.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/steps/domain/step_score_engine.dart';
import 'package:herculex/features/steps/domain/step_weightlifting_impact.dart';

/// Card explaining the precise physiological and programming impact of daily steps on weightlifting.
class StepWeightliftingImpactCard extends StatelessWidget {
  final StepWeightliftingImpact impact;

  const StepWeightliftingImpactCard({super.key, required this.impact});

  Color _accentColor(StepActivityZone zone) {
    switch (zone) {
      case StepActivityZone.sedentary:
        return const Color(0xFF64748B); // Slate
      case StepActivityZone.lightlyActive:
        return const Color(0xFF38BDF8); // Sky blue
      case StepActivityZone.optimal:
        return const Color(0xFF10B981); // Emerald
      case StepActivityZone.highNeat:
        return const Color(0xFFF59E0B); // Amber
      case StepActivityZone.exhaustive:
        return const Color(0xFFF97316); // Orange
      case StepActivityZone.extreme:
        return const Color(0xFFEF4444); // Red
    }
  }

  IconData _zoneIcon(StepActivityZone zone) {
    switch (zone) {
      case StepActivityZone.sedentary:
        return Icons.weekend_rounded;
      case StepActivityZone.lightlyActive:
        return Icons.directions_walk_rounded;
      case StepActivityZone.optimal:
        return Icons.verified_rounded;
      case StepActivityZone.highNeat:
        return Icons.local_fire_department_rounded;
      case StepActivityZone.exhaustive:
        return Icons.warning_amber_rounded;
      case StepActivityZone.extreme:
        return Icons.dangerous_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(impact.zone);

    final lowerDelta = ((impact.lowerBodyVolumeFactor - 1.0) * 100).round();
    final lowerLabel = lowerDelta == 0 ? '100% (Full)' : '$lowerDelta% Sets';

    final upperDelta = ((impact.upperBodyVolumeFactor - 1.0) * 100).round();
    final upperLabel = upperDelta == 0 ? '100% (Full)' : '$upperDelta% Sets';

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      color: accent.withValues(alpha: 0.05),
      border: Border.all(color: accent.withValues(alpha: 0.3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(_zoneIcon(impact.zone), color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      impact.systemicFatigueStatus.toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: accent,
                        letterSpacing: 1.0,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Weightlifting Impact Analysis',
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

          // 4-Quadrant Metric Modifiers Grid
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildMetricTile(
                      theme: theme,
                      label: 'LEG VOLUME (SQUAT/DL)',
                      value: lowerLabel,
                      color: lowerDelta < 0
                          ? Colors.orange
                          : const Color(0xFF10B981),
                      icon: Icons.fitness_center_rounded,
                    ),
                    _buildMetricTile(
                      theme: theme,
                      label: 'UPPER BODY VOLUME',
                      value: upperLabel,
                      color: upperDelta < 0
                          ? Colors.orange
                          : const Color(0xFF10B981),
                      icon: Icons.sports_gymnastics_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildMetricTile(
                      theme: theme,
                      label: 'INTRA-WORKOUT CARBS',
                      value: impact.recommendedIntraWorkoutCarbsGrams > 0
                          ? '+${impact.recommendedIntraWorkoutCarbsGrams}g Carbs'
                          : 'None needed',
                      color: impact.recommendedIntraWorkoutCarbsGrams > 0
                          ? Colors.amberAccent
                          : AppColors.secondary,
                      icon: Icons.local_dining_rounded,
                    ),
                    _buildMetricTile(
                      theme: theme,
                      label: 'INTER-SET CLEARANCE',
                      value: '${impact.workCapacityScore}%',
                      color: const Color(0xFF38BDF8),
                      icon: Icons.speed_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Tactical Coaching Cues
          _buildTacticalTip(
            theme: theme,
            title: 'LOWER BODY SESSION (LEGS / SQUATS)',
            tip: impact.legDayTacticalTip,
            icon: Icons.arrow_downward_rounded,
            iconColor: Colors.deepOrangeAccent,
          ),
          const SizedBox(height: 10),
          _buildTacticalTip(
            theme: theme,
            title: 'UPPER BODY SESSION (BENCH / PRESS)',
            tip: impact.upperDayTacticalTip,
            icon: Icons.arrow_upward_rounded,
            iconColor: Colors.cyanAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required ThemeData theme,
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AppColors.secondary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                    fontSize: 9,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTacticalTip({
    required ThemeData theme,
    required String title,
    required String tip,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  fontSize: 10,
                  color: iconColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tip,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
