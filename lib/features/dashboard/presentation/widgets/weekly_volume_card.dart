import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/units.dart';
import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../../../../theme/tokens/tokens.dart';
import '../../../analytics/presentation/analytics_providers.dart';
import 'dashboard_shared.dart';

/// This week's total volume mini-card (§18). Tapping navigates to the dedicated
/// Muscle Volume Overview page.
class WeeklyVolumeMiniCard extends ConsumerStatefulWidget {
  const WeeklyVolumeMiniCard({super.key});

  @override
  ConsumerState<WeeklyVolumeMiniCard> createState() =>
      _WeeklyVolumeMiniCardState();
}

class _WeeklyVolumeMiniCardState extends ConsumerState<WeeklyVolumeMiniCard> {
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
    final showSets = _showSets;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 220;

        return DashboardPill(
          color: context.hx.domainTraining,
          radius: isCompact ? 20 : 999,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 24,
            vertical: isCompact ? 12 : 16,
          ),
          onTap: () => context.push('/muscle-volume'),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL VOLUME',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.secondary,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Haptics.selection();
                            _toggleShowSets();
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              showSets ? 'Sets' : 'Tonnage',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    volume.when(
                      data: (v) => Text(
                        showSets
                            ? '${v.totalSets} sets'
                            : _formatTonnage(v.totalTonnageKg),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      loading: () => const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (e, _) =>
                          const Icon(Icons.error_outline, size: 18),
                    ),
                  ],
                )
              : Row(
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
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
                                  Icon(Icons.swap_horiz,
                                      size: 14, color: AppColors.primary),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: volume.when(
                          data: (v) => Text(
                              showSets
                                  ? '${v.totalSets} sets'
                                  : _formatTonnage(v.totalTonnageKg),
                              style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary)),
                          loading: () => const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          error: (e, _) =>
                              const Icon(Icons.error_outline, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 22,
                      color: AppColors.secondary,
                    ),
                  ],
                ),
        );
      },
    );
  }

  /// Delegates to the active measurement system, so imperial users read
  /// pounds rather than tonnes.
  String _formatTonnage(double kg) =>
      ref.read(weightFormatProvider).formatTonnage(kg);
}
