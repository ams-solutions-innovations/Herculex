import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/tokens/tokens.dart';
import '../../../../ui/ui.dart';
import '../../domain/training_suggestion.dart';
import '../recovery_providers.dart';

/// "What's best to train next" — the readiest push/pull/legs/core split,
/// which of its muscles have actually cleared the trainable bar, and why
/// anything else in that split got skipped.
class NextWorkoutSuggestionCard extends ConsumerWidget {
  const NextWorkoutSuggestionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final suggestion = ref.watch(nextWorkoutTrainingSuggestionProvider);

    return HxCard(
      accent: hx.domainRecovery,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "NEXT WORKOUT FOCUS",
            style: theme.textTheme.labelSmall?.copyWith(
              color: hx.secondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: HxSpace.x1),
          suggestion.when(
            data: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _categoryLabel(s.bestCategory),
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: hx.domainRecovery, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: HxSpace.x2),
                Text(_summary(s), style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary)),
                if (s.readyMuscles.isNotEmpty) ...[
                  const SizedBox(height: HxSpace.x3),
                  Wrap(
                    spacing: HxSpace.x2,
                    runSpacing: HxSpace.x2,
                    children: [
                      for (final m in s.readyMuscles)
                        HxTextPill(label: m, selected: true, accent: hx.domainRecovery),
                    ],
                  ),
                ],
                if (s.excludedDeload.isNotEmpty || s.excludedJointPain.isNotEmpty) ...[
                  const SizedBox(height: HxSpace.x3),
                  _ExclusionsNote(deload: s.excludedDeload, jointPain: s.excludedJointPain),
                ],
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: HxSpace.x4),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Text('Error: $e', style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(MuscleCategory c) => switch (c) {
        MuscleCategory.push => 'Push',
        MuscleCategory.pull => 'Pull',
        MuscleCategory.legs => 'Legs',
        MuscleCategory.core => 'Core',
      };

  String _summary(TrainingSuggestion s) {
    final category = _categoryLabel(s.bestCategory).toLowerCase();
    if (s.readyMuscles.isEmpty) {
      return 'Your most-recovered split is $category, but all muscle groups are still recovering — consider taking an extra rest day or doing light active recovery before your next session.';
    }
    final muscles = s.readyMuscles.length <= 3
        ? s.readyMuscles.join(', ')
        : '${s.readyMuscles.take(3).join(', ')} and more';
    final verb = s.readyMuscles.length == 1 ? 'is' : 'are';
    return '$category has the highest readiness ($muscles $verb fresh). If you had another split scheduled (e.g. Legs), consider swapping or shifting it by 1–2 days.';
  }
}

class _ExclusionsNote extends StatelessWidget {
  const _ExclusionsNote({required this.deload, required this.jointPain});

  final List<String> deload;
  final List<String> jointPain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final lines = [
      if (deload.isNotEmpty) 'Skipping ${deload.join(', ')} — flagged for a deload.',
      if (jointPain.isNotEmpty)
        "Skipping ${jointPain.join(', ')} — loads a joint you've flagged.",
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(line, style: theme.textTheme.labelSmall?.copyWith(color: hx.secondary)),
          ),
      ],
    );
  }
}
