import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/programs/application/block_update_controller.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/presentation/sheets/update_block_sheet.dart';

/// The active training block with a way to rebuild it, highlighted when the
/// app thinks the block no longer fits (missed sessions or poor recovery).
///
/// With [onlyWhenRecommended] it stays hidden unless there is a suggestion,
/// for screens where the block is not the subject.
class BlockAdjustmentCard extends ConsumerWidget {
  const BlockAdjustmentCard({super.key, this.onlyWhenRecommended = false});

  final bool onlyWhenRecommended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final program = ref.watch(activeProgramProvider).valueOrNull;
    if (program == null) return const SizedBox.shrink();
    final adjustment = ref.watch(visibleBlockAdjustmentProvider);
    final recommendation = adjustment?.program.id == program.id
        ? adjustment!.recommendation
        : null;
    if (onlyWhenRecommended && recommendation == null) {
      return const SizedBox.shrink();
    }
    final hx = context.hx;
    final theme = Theme.of(context);
    final days = program.daysPerWeek;

    return HxCard(
      accent: recommendation == null ? null : hx.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fitness_center_rounded, color: hx.domainTraining),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your training block',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: hx.secondary,
                      ),
                    ),
                    Text(
                      program.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (days != null) HxTextPill(label: '$days× / week'),
            ],
          ),
          if (recommendation != null) ...[
            const SizedBox(height: HxSpace.x3),
            Text(recommendation.message, style: theme.textTheme.bodyMedium),
          ] else ...[
            const SizedBox(height: HxSpace.x2),
            Text(
              'Less time than planned, or training fewer days? Rebuild the rest of the block around it.',
              style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
            ),
          ],
          const SizedBox(height: HxSpace.x3),
          Row(
            children: [
              if (recommendation != null)
                TextButton(
                  onPressed: () async {
                    final key = blockAdjustmentKey(adjustment!);
                    await ref
                        .read(sharedPreferencesProvider)
                        .setString(blockAdjustmentDismissedKey, key);
                    ref.read(blockAdjustmentDismissedProvider.notifier).state =
                        key;
                  },
                  child: const Text('Not now'),
                ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () => showUpdateBlockSheet(
                  context,
                  program: program,
                  recommendation: recommendation,
                ),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Update block'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
