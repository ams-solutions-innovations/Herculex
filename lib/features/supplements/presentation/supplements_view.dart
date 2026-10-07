import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/supplements/application/supplement_providers.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/presentation/supplement_ai_scan_dialog.dart';
import 'package:herculex/features/supplements/presentation/supplement_edit_sheet.dart';

const _accent = Color(0xFF9B59B6);

/// Full supplements page: today's progress, every supplement with its dose
/// and schedule, and the add / AI-scan actions. Opened from the dashboard card.
class SupplementsView extends ConsumerWidget {
  const SupplementsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(supplementDayStateProvider);

    return HxScreenShell(
      title: 'Supplements',
      titleIcon: Icons.medication_outlined,
      children: [
        stateAsync.when(
          data: (state) => _Body(state: state),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: HxSpace.x8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(HxSpace.x6),
            child: Text(
              'Failed to load supplements: $e',
              style: TextStyle(color: context.hx.danger),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _scan(BuildContext context) async {
  final result = await SupplementAiScanDialog.show(context);
  if (result != null && context.mounted) {
    await SupplementEditSheet.show(context, existing: result.toSupplement());
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final SupplementDayState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final done = state.totalCount > 0 && state.progress >= 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HxCard(
          accent: _accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TODAY',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _accent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: HxSpace.x1),
              Text(
                state.totalCount == 0
                    ? 'Nothing to track yet'
                    : done
                    ? 'All taken ✓'
                    : '${state.takenCount} of ${state.totalCount} taken',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (state.totalCount > 0) ...[
                const SizedBox(height: HxSpace.x3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: state.progress),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    builder: (_, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        done ? Colors.green : _accent,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: HxSpace.x4),
        Wrap(
          spacing: HxSpace.x2,
          runSpacing: HxSpace.x2,
          children: [
            FilledButton.icon(
              onPressed: () => SupplementEditSheet.show(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add supplement'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _scan(context),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('AI photo scan'),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
            ),
          ],
        ),
        const SizedBox(height: HxSpace.x4),
        if (state.supplements.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: HxSpace.x6),
            child: Center(
              child: Text(
                'Scan a tub or add one by hand to start tracking doses.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          )
        else ...[
          for (final s in state.supplements) ...[
            _Row(supplement: s, isTaken: state.isTaken(s.id)),
            const SizedBox(height: HxSpace.x2),
          ],
          Padding(
            padding: const EdgeInsets.only(top: HxSpace.x2),
            child: Text(
              'Tap to mark as taken · long-press or use the pencil to edit.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        ],
      ],
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.supplement, required this.isTaken});

  final Supplement supplement;
  final bool isTaken;

  String? get _subtitle {
    final parts = <String?>[
      supplement.brand,
      supplement.doseLabel,
      switch (supplement.schedule) {
        SupplementSchedule.time => supplement.timeHHMM,
        SupplementSchedule.postWorkout => 'Post-workout',
        SupplementSchedule.none => null,
      },
    ].whereType<String>().where((p) => p.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final subtitle = _subtitle;

    return GestureDetector(
      onLongPress: () =>
          SupplementEditSheet.show(context, existing: supplement),
      child: HxCard(
        onTap: () {
          Haptics.selection();
          ref
              .read(supplementRepositoryProvider)
              .markTaken(supplement.id, !isTaken);
        },
        padding: const EdgeInsets.symmetric(
          horizontal: HxSpace.x4,
          vertical: HxSpace.x3,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isTaken ? _accent : Colors.transparent,
                border: Border.all(
                  color: isTaken ? _accent : theme.colorScheme.outlineVariant,
                  width: 1.8,
                ),
              ),
              child: isTaken
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: HxSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    supplement.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      decoration: isTaken ? TextDecoration.lineThrough : null,
                      color: isTaken ? muted : null,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: muted,
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  SupplementEditSheet.show(context, existing: supplement),
            ),
          ],
        ),
      ),
    );
  }
}
