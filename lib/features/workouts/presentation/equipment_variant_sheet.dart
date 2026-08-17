import 'package:flutter/material.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../domain/equipment_variants.dart';
import 'equipment_icon.dart';

/// Hevy-style equipment prompt (§26): immediately after picking an exercise,
/// large tappable buttons ask which equipment it will be performed with. The
/// choice is stored per log entry as `workout_exercises.equipment_variant`.
class EquipmentVariantSheet extends StatelessWidget {
  final ExerciseCatalogData exercise;
  const EquipmentVariantSheet({super.key, required this.exercise});

  /// Returns the chosen variant id, or null if dismissed. Skips the prompt
  /// (returning the catalog modality) when only one option makes sense.
  static Future<String?> show(
    BuildContext context,
    ExerciseCatalogData exercise,
  ) {
    final options = optionsFor(exercise);
    if (options.length <= 1) {
      return Future.value(exercise.modality);
    }
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => EquipmentVariantSheet(exercise: exercise),
    );
  }

  // Keep equipment icons in one place so the post-pick prompt and the
  // family-style chooser use the same visual language.
  static const _icons = <String, IconData>{
    'barbell': Icons.horizontal_rule,
    'dumbbell': Icons.fitness_center,
    'smith': Icons.view_column,
    'cable': Icons.cable,
    'machine_plate': Icons.settings_outlined,
    'machine_selectorized': Icons.tune,
    'kettlebell': Icons.sports_handball,
    'band': Icons.gesture,
    'bodyweight': Icons.accessibility_new,
    'other': Icons.more_horiz,
  };

  static IconData iconFor(String variant) =>
      _icons[variant] ?? Icons.fitness_center_outlined;

  static Widget iconWidget(String variant, {double size = 20, Color? color}) =>
      EquipmentGlyph(
        variant: variant,
        size: size,
        color: color ?? AppColors.secondary,
      );

  static String labelFor(String variant) => equipmentVariantLabel(variant);

  /// Plausible equipment options per exercise, catalog default first.
  ///
  /// Only swaps the exercise can physically be performed with are offered. A
  /// Seated Leg Curl exists on exactly one machine, so it gets no prompt at
  /// all — [show] skips the sheet when there is a single option. The rule
  /// itself lives in `domain/equipment_variants.dart`; the Wear OS catalog
  /// push needs the same answer.
  static List<String> optionsFor(ExerciseCatalogData exercise) =>
      equipmentVariantsFor(exercise);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = optionsFor(exercise);

    return Container(
      decoration: BoxDecoration(
        color:
            theme.bottomSheetTheme.backgroundColor ??
            AppColors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                exercise.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text('Which equipment?', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final (i, option) in options.indexed)
                        _VariantButton(
                          label: labelFor(option),
                          variant: option,
                          isDefault: i == 0,
                          onTap: () => Navigator.of(context).pop(option),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariantButton extends StatelessWidget {
  final String label;
  final String variant;
  final bool isDefault;
  final VoidCallback onTap;

  const _VariantButton({
    required this.label,
    required this.variant,
    required this.isDefault,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        // Large touch targets per §26.
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: isDefault
              ? AppColors.primaryContainer.withValues(alpha: 0.4)
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDefault
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.4),
            width: isDefault ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EquipmentGlyph(
              variant: variant,
              size: 22,
              color: isDefault ? AppColors.primary : AppColors.secondary,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: isDefault ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
