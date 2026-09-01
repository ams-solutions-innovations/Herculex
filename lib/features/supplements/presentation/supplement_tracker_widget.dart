import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';
import 'package:herculex/features/supplements/domain/supplement.dart';
import 'package:herculex/features/supplements/presentation/supplement_ai_scan_dialog.dart';
import 'package:herculex/features/supplements/presentation/supplement_edit_sheet.dart';
import 'package:herculex/features/supplements/presentation/supplement_providers.dart';
import 'package:herculex/theme/colors.dart';
import 'package:herculex/theme/haptics.dart';

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
      loading: () => _buildCard(
        context,
        theme,
        ref,
        const SupplementDayState(supplements: [], takenIds: {}),
      ),
      error: (_, e) => const SizedBox.shrink(),
    );
  }

  Widget _buildCard(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
    SupplementDayState state,
  ) {
    const accent = Color(0xFF9B59B6);

    return dashboardCard(
      accent: accent,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9B59B6).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.medication_outlined,
                    size: 18,
                    color: Color(0xFF9B59B6),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SUPPLEMENTS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF9B59B6),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        state.totalCount == 0
                            ? 'Track daily doses'
                            : '${state.takenCount} of ${state.totalCount} taken today',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Progress chip
                if (state.totalCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: state.progress >= 1.0
                          ? Colors.green.withValues(alpha: 0.15)
                          : const Color(0xFF9B59B6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      state.progress >= 1.0
                          ? '✓ Done'
                          : '${(state.progress * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: state.progress >= 1.0
                            ? Colors.green
                            : const Color(0xFF9B59B6),
                        fontWeight: FontWeight.bold,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                // Add button
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  color: AppColors.secondary,
                  tooltip: 'Add supplement',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: () => SupplementEditSheet.show(context),
                ),
              ],
            ),
          ),

          // ── Progress bar ────────────────────────────────────────────────
          if (state.totalCount > 0) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: state.progress),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  builder: (_, value, child) => LinearProgressIndicator(
                    value: value,
                    minHeight: 5,
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
            Flexible(
              child: _EmptyState(
                onAdd: () => SupplementEditSheet.show(context),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                color: isTaken ? const Color(0xFF9B59B6) : Colors.transparent,
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
                      decoration: isTaken ? TextDecoration.lineThrough : null,
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
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.medication_outlined,
              size: 28,
              color: AppColors.secondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 6),
            Text(
              'No supplements yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Scan a tub or add one by hand to start tracking doses.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final result = await SupplementAiScanDialog.show(context);
                    if (result != null && context.mounted) {
                      await SupplementEditSheet.show(
                        context,
                        existing: result.toSupplement(),
                      );
                    }
                  },
                  icon: const Icon(Icons.auto_awesome, size: 15),
                  label: const Text('AI Foto sken'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF9B59B6),
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('Ročni vnos'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF9B59B6),
                    side: BorderSide(
                      color: const Color(0xFF9B59B6).withValues(alpha: 0.4),
                    ),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
