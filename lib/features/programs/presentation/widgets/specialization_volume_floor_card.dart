import 'package:flutter/material.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/design_system/tokens/hx_geometry.dart';
import 'package:herculex/features/programs/domain/program_muscle_volume.dart';
import 'package:herculex/features/programs/domain/volume_bands.dart';

/// Live-preview half of D-04–D-07's maintenance-volume-floor check: renders
/// the Schedule step's estimated weekly volume per muscle group, tinting any
/// group whose weekly sets fall below [VolumeBands]'s minimum ("Light").
///
/// Rendered instead of `ProgramMuscleVolumeCard` whenever primary-lift
/// specialization is active, so a below-floor muscle group is visible the
/// moment a template is linked — not just after Create-time confirmation.
class SpecializationVolumeFloorCard extends StatelessWidget {
  const SpecializationVolumeFloorCard({super.key, required this.breakdown});

  final ProgramVolumeBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    if (breakdown.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final hx = context.hx;
    final items = breakdown.averageWeeklyVolumes;
    final maxSets = items.isEmpty
        ? 1.0
        : items.map((e) => e.sets).reduce((a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(HxSpace.x4),
      decoration: BoxDecoration(
        color: hx.surfaceContainer,
        borderRadius: HxRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly Volume per Muscle Group',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in items) _buildMuscleRow(theme, hx, item, maxSets),
        ],
      ),
    );
  }

  Widget _buildMuscleRow(
    ThemeData theme,
    HxColors hx,
    MuscleVolumeEntry item,
    double maxSets,
  ) {
    final verdict = VolumeBands.forGroup(item.muscle).verdict(item.sets);
    final isLow = verdict == VolumeVerdict.low;
    final ratio = maxSets > 0 ? (item.sets / maxSets).clamp(0.05, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.muscle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isLow ? hx.warning : null,
                ),
              ),
              Text('${item.formattedSets} sets'),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: hx.surfaceVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: ratio,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: isLow ? hx.warning : hx.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
          if (isLow) ...[
            const SizedBox(height: 2),
            Text(
              '${verdict.label} — ${verdict.blurb}',
              style: theme.textTheme.bodySmall?.copyWith(color: hx.warning),
            ),
          ],
        ],
      ),
    );
  }
}
