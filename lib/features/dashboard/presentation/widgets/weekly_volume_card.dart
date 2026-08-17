import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/units.dart';
import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../../../analytics/domain/weekly_muscle_volume.dart';
import '../../../analytics/presentation/analytics_providers.dart';
import 'dashboard_shared.dart';
/// This week's total tonnage (§18), as a pill that opens into a per-muscle
/// breakdown of where the volume actually went.
class WeeklyVolumeMiniCard extends ConsumerStatefulWidget {
  const WeeklyVolumeMiniCard({super.key});

  @override
  ConsumerState<WeeklyVolumeMiniCard> createState() =>
      _WeeklyVolumeMiniCardState();
}

class _WeeklyVolumeMiniCardState extends ConsumerState<WeeklyVolumeMiniCard> {
  bool _expanded = false;
  late bool _showSets;

  @override
  void initState() {
    super.initState();
    _showSets =
        ref.read(sharedPreferencesProvider).getBool('show_volume_in_sets') ??
            false;
  }

  void _toggleShowSets() {
    final prefs = ref.read(sharedPreferencesProvider);
    setState(() => _showSets = !_showSets);
    prefs.setBool('show_volume_in_sets', _showSets);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final volume = ref.watch(weeklyMuscleVolumeProvider);
    final data = volume.asData?.value;
    final showSets = _showSets;

    return DashboardPill(
      radius: _expanded ? 24 : 999,
      padding: EdgeInsets.fromLTRB(24, 16, 16, _expanded ? 20 : 16),
      onTap: data == null ? null : () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    dashboardTitle(context, 'Total Volume'),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        Haptics.selection();
                        _toggleShowSets();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              showSets ? 'Sets' : 'Tonnage',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.swap_horiz, size: 14, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  Haptics.selection();
                  _toggleShowSets();
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: volume.when(
                    data: (v) => Text(
                        showSets ? '${v.totalSets} sets' : _formatTonnage(v.totalTonnageKg),
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                    loading: () => const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    error: (e, _) => const Icon(Icons.error_outline, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(Icons.expand_more,
                    size: 22, color: AppColors.secondary),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded || data == null
                ? const SizedBox(width: double.infinity)
                : _breakdown(theme, data, showSets),
          ),
        ],
      ),
    );
  }

  Widget _breakdown(ThemeData theme, WeeklyMuscleVolume v, bool showSets) {
    if (v.byMuscle.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('No sets logged yet this week.',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
      );
    }
    final sortedList = List<MuscleVolume>.from(v.byMuscle);
    if (showSets) {
      sortedList.sort((a, b) => b.sets.compareTo(a.sets));
    } else {
      sortedList.sort((a, b) => b.tonnageKg.compareTo(a.tonnageKg));
    }
    final max = sortedList.isNotEmpty
        ? (showSets ? sortedList.first.sets : sortedList.first.tonnageKg)
        : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text('${v.totalSets} working sets since Monday',
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
        const SizedBox(height: 12),
        for (final m in sortedList)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(m.muscle,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis)),
                    if (showSets) ...[
                      Text(_formatTonnage(m.tonnageKg),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.secondary)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 62,
                        child: Text('${m.sets.toStringAsFixed(m.sets < 10 ? 1 : 0)} sets',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                    ] else ...[
                      Text('${m.sets.toStringAsFixed(m.sets < 10 ? 1 : 0)} sets',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.secondary)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 62,
                        child: Text(_formatTonnage(m.tonnageKg),
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: max <= 0
                        ? 0
                        : ((showSets ? m.sets : m.tonnageKg) / max).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Delegates to the active measurement system, so imperial users read
  /// pounds rather than tonnes.
  String _formatTonnage(double kg) =>
      ref.read(weightFormatProvider).formatTonnage(kg);
}
