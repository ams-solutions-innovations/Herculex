import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_sheet.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';

/// Modal bottom sheet for configuring an exercise's programming affinity.
///
/// Options:
/// - [ExerciseAffinity.core]: Core lift (star)
/// - [ExerciseAffinity.liked]: Like (heart)
/// - [ExerciseAffinity.okay]: Okay (check)
/// - [ExerciseAffinity.never]: Never (block)
class ExerciseAffinitySheet extends ConsumerWidget {
  const ExerciseAffinitySheet({
    super.key,
    required this.exercise,
    this.currentAffinity,
  });

  final ExerciseCatalogData exercise;
  final ExerciseAffinity? currentAffinity;

  /// Shows the affinity selection bottom sheet for [exercise].
  static Future<ExerciseAffinity?> show(
    BuildContext context, {
    required ExerciseCatalogData exercise,
    ExerciseAffinity? currentAffinity,
  }) {
    return HxSheet.show<ExerciseAffinity>(
      context,
      builder: (_) => ExerciseAffinitySheet(
        exercise: exercise,
        currentAffinity: currentAffinity,
      ),
    );
  }

  static (Color, IconData) visualFor(ExerciseAffinity affinity) =>
      switch (affinity) {
        ExerciseAffinity.never => (Colors.redAccent, Icons.block_rounded),
        ExerciseAffinity.okay => (AppColors.secondary, Icons.check_rounded),
        ExerciseAffinity.liked => (Colors.pinkAccent, Icons.favorite_rounded),
        ExerciseAffinity.core => (Colors.amber.shade800, Icons.star_rounded),
      };

  static String descriptionFor(ExerciseAffinity affinity) => switch (affinity) {
    ExerciseAffinity.core => 'Priority staple lift in your training program',
    ExerciseAffinity.liked =>
      'Preferred when smart suggestions select exercises',
    ExerciseAffinity.okay => 'Standard preference, suggested normally',
    ExerciseAffinity.never => 'Excluded from smart program suggestions',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final selected =
        ref.watch(exerciseAffinityProvider(exercise.id)).asData?.value ??
        currentAffinity ??
        ExerciseAffinity.okay;

    const options = [
      ExerciseAffinity.core,
      ExerciseAffinity.liked,
      ExerciseAffinity.okay,
      ExerciseAffinity.never,
    ];

    return HxSheet(
      title: 'Programming Preference',
      subtitle: exercise.name,
      scrollable: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: options.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final option = options[index];
              final isSelected = selected == option;
              final (color, icon) = visualFor(option);

              return Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.12)
                      : hx.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? color.withValues(alpha: 0.6)
                        : hx.outlineVariant.withValues(alpha: 0.35),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await ref
                          .read(exercisePreferencesRepositoryProvider)
                          .setAffinity(
                            exerciseId: exercise.id,
                            affinity: option,
                          );
                      if (context.mounted) {
                        Navigator.of(context).pop(option);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: color, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option.label,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? color : hx.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  descriptionFor(option),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: hx.secondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isSelected)
                            Icon(
                              Icons.check_circle_rounded,
                              color: color,
                              size: 22,
                            )
                          else
                            Icon(
                              Icons.radio_button_unchecked_rounded,
                              color: hx.outlineVariant.withValues(alpha: 0.6),
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Used by Smart exercise selection. “Never” is a hard filter.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: hx.secondary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
