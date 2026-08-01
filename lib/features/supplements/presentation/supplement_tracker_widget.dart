import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import '../../../theme/haptics.dart';
import '../domain/supplement.dart';
import 'supplement_edit_sheet.dart';
import 'supplement_providers.dart';

/// Dashboard widget — a checkbox-based daily supplement tracker.
///
/// Shows all configured supplements as animated checkbox rows with an optional
/// time or "post-workout" badge. Tapping a row toggles it; long-pressing (or
/// tapping the name) opens the edit sheet. A "+" button adds new supplements.
class SupplementTrackerWidget extends ConsumerWidget {
  const SupplementTrackerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stateAsync = ref.watch(supplementDayStateProvider);

    return stateAsync.when(
      data: (state) => _buildCard(context, theme, ref, state),
      loading: () => _buildCard(context, theme, ref,
          const SupplementDayState(supplements: [], takenIds: {})),
      error: (_, e) => const SizedBox.shrink(),
    );
  }

  Widget _buildCard(BuildContext context, ThemeData theme, WidgetRef ref,
      SupplementDayState state) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9B59B6).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.medication_outlined,
                    size: 20,
                    color: Color(0xFF9B59B6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SUPPLEMENTS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF9B59B6),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        state.totalCount == 0
                            ? 'Track what you take each day'
                            : '${state.takenCount} of ${state.totalCount} taken today',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.secondary),
                      ),
                    ],
                  ),
                ),
                // Progress chip
                if (state.totalCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: state.progress >= 1.0
                          ? Colors.green.withValues(alpha: 0.15)
                          : const Color(0xFF9B59B6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      state.progress >= 1.0
                          ? '✓ All done'
                          : '${(state.progress * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: state.progress >= 1.0
                            ? Colors.green
                            : const Color(0xFF9B59B6),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                // Add button
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  color: AppColors.secondary,
                  tooltip: 'Add supplement',
                  onPressed: () =>
                      SupplementEditSheet.show(context),
                ),
              ],
            ),
          ),

          // ── Progress bar ────────────────────────────────────────────────
          if (state.totalCount > 0) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: state.progress),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  builder: (_, value, child) => LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      value >= 1.0 ? Colors.green : const Color(0xFF9B59B6),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // ── Supplement rows ─────────────────────────────────────────────
          if (state.supplements.isEmpty)
            _EmptyState(onAdd: () => SupplementEditSheet.show(context))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Column(
                children: [
                  for (final s in state.supplements)
                    _SupplementRow(
                      supplement: s,
                      isTaken: state.isTaken(s.id),
                      onToggle: (taken) {
                        Haptics.selection();
                        ref
                            .read(supplementRepositoryProvider)
                            .markTaken(s.id, taken);
                      },
                      onEdit: () =>
                          SupplementEditSheet.show(context, existing: s),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Supplement row ─────────────────────────────────────────────────────────────

class _SupplementRow extends StatelessWidget {
  final Supplement supplement;
  final bool isTaken;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  const _SupplementRow({
    required this.supplement,
    required this.isTaken,
    required this.onToggle,
    required this.onEdit,
  });

  /// `Optimum Nutrition · 5 g` — omitted entirely when neither is set.
  String? get _subtitle {
    final parts = [
      if (supplement.brand != null && supplement.brand!.isNotEmpty)
        supplement.brand!,
      if (supplement.doseLabel != null) supplement.doseLabel!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => onToggle(!isTaken),
      onLongPress: onEdit,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            // Animated checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isTaken
                    ? const Color(0xFF9B59B6)
                    : Colors.transparent,
                border: Border.all(
                  color: isTaken
                      ? const Color(0xFF9B59B6)
                      : AppColors.outlineVariant,
                  width: 1.8,
                ),
              ),
              child: isTaken
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),

            // Name, with brand and dose beneath when they're known
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    supplement.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      decoration:
                          isTaken ? TextDecoration.lineThrough : null,
                      color: isTaken ? AppColors.secondary : null,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_subtitle != null)
                    Text(
                      _subtitle!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        fontSize: 10.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Schedule badge
            _ScheduleBadge(supplement: supplement),

            // Edit button (subtle)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              color: AppColors.secondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Edit',
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleBadge extends StatelessWidget {
  final Supplement supplement;
  const _ScheduleBadge({required this.supplement});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String? label;
    IconData? icon;

    switch (supplement.schedule) {
      case SupplementSchedule.time:
        label = supplement.timeHHMM ?? '';
        icon = Icons.access_time;
        break;
      case SupplementSchedule.postWorkout:
        label = 'Post-workout';
        icon = Icons.fitness_center;
        break;
      case SupplementSchedule.none:
        return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.secondary),
          const SizedBox(width: 3),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The parent Column uses crossAxisAlignment.start, so the empty state has
    // to claim the full width itself or it hugs the left edge.
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.medication_outlined,
              size: 40,
              color: AppColors.secondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No supplements yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Scan a tub or add one by hand to start tracking doses.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF9B59B6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 16, color: Color(0xFF9B59B6)),
                    const SizedBox(width: 6),
                    Text(
                      'Add your first supplement',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF9B59B6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
