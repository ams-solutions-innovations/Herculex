import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/units.dart';
import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../analytics/domain/variant_performance.dart';
import '../../analytics/presentation/analytics_providers.dart';
import 'equipment_variant_sheet.dart';

/// Per-exercise performance breakdown (§1, §5, §26): PR and estimated 1RM for
/// each equipment variant and each accessory combination, e.g.
/// "Squat 1RM: 100 kg (Raw), 120 kg (Belt), 125 kg (Belt + Sleeves)".
class ExercisePerformanceSheet extends ConsumerWidget {
  final ExerciseCatalogData exercise;
  const ExercisePerformanceSheet({super.key, required this.exercise});

  static Future<void> show(
      BuildContext context, ExerciseCatalogData exercise) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExercisePerformanceSheet(exercise: exercise),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final byEquipment = ref.watch(equipmentPerformanceProvider(exercise.id));
    final byAccessory = ref.watch(accessoryPerformanceProvider(exercise.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor ??
              AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(exercise.name,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text('Effective load includes bodyweight, bands, and chains.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.secondary)),
            const SizedBox(height: 20),
            _Section(
              title: 'By equipment',
              async: byEquipment,
              labelOf: (r) => EquipmentVariantSheet.labelFor(r.label),
            ),
            const SizedBox(height: 20),
            _Section(
              title: 'By accessories',
              async: byAccessory,
              labelOf: (r) => r.label,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends ConsumerWidget {
  final String title;
  final AsyncValue<List<PerformanceRecord>> async;
  final String Function(PerformanceRecord) labelOf;

  const _Section(
      {required this.title, required this.async, required this.labelOf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        async.when(
          data: (records) => records.isEmpty
              ? Text('No completed sets yet',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.secondary))
              : Column(
                  children: [
                    for (final r in records)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(labelOf(r),
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600)),
                                  Text(
                                    _subtitle(r, ref.watch(weightFormatProvider)),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: AppColors.secondary),
                                  ),
                                ],
                              ),
                            ),
                            if (r.bestE1RmKg != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(ref.watch(weightFormatProvider).format(r.bestE1RmKg!),
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary)),
                                  Text('e1RM',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: AppColors.secondary)),
                                ],
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text('Error: $e'),
        ),
      ],
    );
  }

  String _subtitle(PerformanceRecord r, WeightFormat fmt) {
    var text = 'Best: ${fmt.format(r.bestWeightKg)}';
    if (r.rawWeightKg != null &&
        (r.rawWeightKg! - r.bestWeightKg).abs() > 0.1 &&
        r.rawWeightKg! > 0) {
      text += ' (${fmt.format(r.rawWeightKg!)} bar)';
    }
    text += ' × ${r.bestWeightReps} • ${r.setCount} set${r.setCount == 1 ? '' : 's'}';
    return text;
  }
}
