import 'package:flutter/material.dart';
import 'package:herculex/features/programs/domain/program_muscle_volume.dart';
import 'package:herculex/theme/colors.dart';

/// Renders a structured breakdown of prescribed weekly sets per muscle group
/// for a training program.
class ProgramMuscleVolumeCard extends StatefulWidget {
  final ProgramVolumeBreakdown breakdown;
  final String title;
  final bool initialExpanded;

  const ProgramMuscleVolumeCard({
    super.key,
    required this.breakdown,
    this.title = 'Weekly Volume per Muscle Group',
    this.initialExpanded = true,
  });

  @override
  State<ProgramMuscleVolumeCard> createState() =>
      _ProgramMuscleVolumeCardState();
}

class _ProgramMuscleVolumeCardState extends State<ProgramMuscleVolumeCard> {
  int _selectedWeek = -1; // -1 = Average, 0..N = Week index
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breakdown = widget.breakdown;

    if (breakdown.isEmpty) return const SizedBox.shrink();

    final hasMultipleWeeks = breakdown.weeks.length > 1;

    // Get current items to show
    final List<MuscleVolumeEntry> items;
    final String currentTotalLabel;
    final String currentPeriodLabel;

    if (_selectedWeek == -1 || _selectedWeek >= breakdown.weeks.length) {
      items = breakdown.averageWeeklyVolumes;
      currentTotalLabel = '${breakdown.formattedAverageTotalSets} sets / wk';
      currentPeriodLabel = 'Average per week';
    } else {
      final week = breakdown.weeks[_selectedWeek];
      items = week.volumes;
      currentTotalLabel = '${week.formattedTotalSets} sets';
      currentPeriodLabel = week.weekLabel;
    }

    final maxSets = items.isEmpty ? 1.0 : items.first.sets;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.bar_chart_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          currentPeriodLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      currentTotalLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.secondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            Divider(height: 1, color: AppColors.outlineVariant),
            const SizedBox(height: 10),

            // Week selector chips (if more than 1 week)
            if (hasMultipleWeeks)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildChip(
                      label: 'Avg / Wk',
                      isSelected: _selectedWeek == -1,
                      onTap: () => setState(() => _selectedWeek = -1),
                    ),
                    for (var i = 0; i < breakdown.weeks.length; i++) ...[
                      const SizedBox(width: 6),
                      _buildChip(
                        label: breakdown.weeks[i].weekLabel,
                        isSelected: _selectedWeek == i,
                        onTap: () => setState(() => _selectedWeek = i),
                      ),
                    ],
                  ],
                ),
              ),

            if (hasMultipleWeeks) const SizedBox(height: 12),

            // Muscle volume bars list
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  for (final item in items)
                    _buildMuscleRow(theme, item, maxSets),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.surfaceContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppColors.primary : AppColors.secondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMuscleRow(
    ThemeData theme,
    MuscleVolumeEntry item,
    double maxSets,
  ) {
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
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  Text(
                    '${item.formattedSets} sets',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${item.percentage.toStringAsFixed(0)}%)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: ratio,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
