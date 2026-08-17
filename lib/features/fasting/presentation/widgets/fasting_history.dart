import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../data/local/database.dart';
import '../../../../theme/colors.dart';
import '../../../../theme/tokens/tokens.dart';
import '../../../../ui/ui.dart';
import '../fasting_providers.dart';

/// Recent sessions, deletable three ways: swipe, the detail sheet's delete
/// button, and — new in the UI rework — long-press any row to arm it (its
/// status icon flips to an X), then tap to delete. All three funnel through
/// the same confirm dialog and repository call.
class FastingHistory extends ConsumerStatefulWidget {
  const FastingHistory({super.key});

  @override
  ConsumerState<FastingHistory> createState() => _FastingHistoryState();
}

class _FastingHistoryState extends ConsumerState<FastingHistory> {
  bool _showAllHistory = false;
  bool _deleteMode = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final historyAsync = ref.watch(fastingHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text(
            "RECENT SESSIONS",
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: hx.secondary, letterSpacing: 1.0),
          ),
        ),
        const SizedBox(height: 12),
        historyAsync.when(
          data: (history) {
            if (history.isEmpty) {
              return HxGlass(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off_rounded, size: 36, color: hx.outline),
                    const SizedBox(height: 12),
                    Text("No Fasting History",
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      "Your completed fasting sessions will appear here.",
                      style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            final visibleCount =
                _showAllHistory || history.length <= 10 ? history.length : 10;
            final hasMore = history.length > visibleCount;

            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _deleteMode ? () => setState(() => _deleteMode = false) : null,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: visibleCount + (hasMore ? 1 : 0),
                separatorBuilder: (context, index) => const Divider(height: 24),
                itemBuilder: (context, index) {
                  if (index == visibleCount) {
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(() => _showAllHistory = true),
                        child: Text('View all (${history.length})'),
                      ),
                    );
                  }
                  final session = history[index];
                  return _HistoryTile(
                    session: session,
                    deleteMode: _deleteMode,
                    onLongPress: () => setState(() => _deleteMode = true),
                    onArmedDelete: () => _confirmAndDelete(session),
                    onSwipeConfirm: () => _confirmDeleteDialog(context),
                    onSwipeDismissed: () =>
                        ref.read(fastingRepositoryProvider).deleteSession(session.id),
                    onTap: () => _showHistoryDetails(context, session),
                  );
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Center(child: Text('Error: $e')),
        ),
      ],
    );
  }

  /// Confirm dialog shared by all three delete paths (swipe, long-press-arm,
  /// detail sheet) so they read identically.
  Future<bool> _confirmDeleteDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text("Delete Session"),
        content: const Text("Are you sure you want to delete this fasting session?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("DELETE",
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Long-press-armed and detail-sheet delete: dialog then delete, both in
  /// one step (unlike swipe, there's no dismiss animation to sequence with).
  Future<void> _confirmAndDelete(FastingSessionData session) async {
    if (!await _confirmDeleteDialog(context)) return;
    await ref.read(fastingRepositoryProvider).deleteSession(session.id);
    if (mounted) setState(() => _deleteMode = false);
  }

  Future<void> _showHistoryDetails(
      BuildContext context, FastingSessionData session) async {
    final format = DateFormat('yyyy-MM-dd HH:mm');
    final startedStr = format.format(session.startedAt);
    final endedStr = session.endedAt != null ? format.format(session.endedAt!) : 'Ongoing';
    final duration = session.endedAt != null
        ? session.endedAt!.difference(session.startedAt)
        : Duration.zero;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: 20),
            Text('Fasting Session Details',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_arrow_outlined),
              title: const Text('Started'),
              subtitle: Text(startedStr),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.stop_outlined),
              title: const Text('Ended'),
              subtitle: Text(endedStr),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Total Duration'),
              subtitle: Text('${duration.inHours}h ${duration.inMinutes % 60}m'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ref
                          .read(fastingRepositoryProvider)
                          .updateSessionCompletion(session.id, !session.completed);
                    },
                    icon: Icon(session.completed ? Icons.close : Icons.check),
                    label: Text(session.completed ? 'Mark Incomplete' : 'Mark Completed'),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmAndDelete(session);
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.session,
    required this.deleteMode,
    required this.onLongPress,
    required this.onArmedDelete,
    required this.onSwipeConfirm,
    required this.onSwipeDismissed,
    required this.onTap,
  });

  final FastingSessionData session;
  final bool deleteMode;
  final VoidCallback onLongPress;

  /// Tapping the row while armed by long-press.
  final VoidCallback onArmedDelete;

  /// Swipe confirm dialog; returning true lets Dismissible animate away.
  final Future<bool> Function() onSwipeConfirm;
  final VoidCallback onSwipeDismissed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final duration = session.endedAt!.difference(session.startedAt);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final dateStr = DateFormat('E, MMM d').format(session.startedAt);
    final targetHours = session.targetSeconds ~/ 3600;

    return Dismissible(
      key: ValueKey('session_${session.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.redAccent.withValues(alpha: 0.85),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => onSwipeConfirm(),
      onDismissed: (_) => onSwipeDismissed(),
      child: InkWell(
        onTap: deleteMode ? onArmedDelete : onTap,
        onLongPress: deleteMode ? null : onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: deleteMode
                      ? Colors.redAccent.withValues(alpha: 0.15)
                      : session.completed
                          ? hx.domainFasting.withValues(alpha: 0.1)
                          : hx.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  deleteMode
                      ? Icons.close
                      : session.completed
                          ? Icons.check_circle_outline
                          : Icons.close,
                  color: deleteMode
                      ? Colors.redAccent
                      : session.completed
                          ? hx.domainFasting
                          : hx.secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("$hours hrs $minutes min fast",
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                    Text("Target: ${targetHours}h • $dateStr",
                        style: theme.textTheme.bodySmall?.copyWith(color: hx.secondary)),
                  ],
                ),
              ),
              if (!deleteMode)
                Text(
                  session.completed ? "SUCCESS" : "INCOMPLETE",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: session.completed ? hx.domainFasting : hx.secondary,
                    fontWeight: session.completed ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
