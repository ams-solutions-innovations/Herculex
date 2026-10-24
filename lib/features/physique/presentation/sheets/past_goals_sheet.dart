import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_sheet.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/goal_display_copy.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:intl/intl.dart';

/// Archived goals with explicit, cascading deletion.
class PastGoalsSheet extends ConsumerStatefulWidget {
  const PastGoalsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return HxSheet.show<void>(context, builder: (_) => const PastGoalsSheet());
  }

  @override
  ConsumerState<PastGoalsSheet> createState() => _PastGoalsSheetState();
}

class _PastGoalsSheetState extends ConsumerState<PastGoalsSheet> {
  final Set<int> _deleting = {};

  Future<void> _delete(PhysiqueGoalData goal) async {
    if (_deleting.contains(goal.id)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete this past goal?'),
        content: const Text(
          'This removes the goal, its check-ins, roadmap and saved photos. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep goal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: dialog.hx.danger),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete goal'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _deleting.add(goal.id));
    final notices = AppNotice.of(context);
    final store = ref.read(physiquePhotoStoreProvider);
    try {
      final uuid = await ref
          .read(physiqueGoalRepositoryProvider)
          .deleteArchivedGoal(goal.id);
      if (uuid != null) {
        await store.deleteGoalFolder(uuid);
      }
      notices.show('Past goal deleted.');
    } on Object {
      notices.show(
        'Could not delete this goal. Try again.',
        kind: AppNoticeKind.error,
      );
    } finally {
      if (mounted) {
        setState(() => _deleting.remove(goal.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(archivedPhysiqueGoalsProvider);
    final goals = history.asData?.value ?? const <PhysiqueGoalData>[];
    return HxSheet(
      title: 'Past goals',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (history.isLoading)
            const Center(child: CircularProgressIndicator()),
          if (history.hasError)
            TextButton(
              onPressed: () => ref.invalidate(archivedPhysiqueGoalsProvider),
              child: const Text('Could not load past goals. Tap to retry.'),
            ),
          if (history.hasValue && goals.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No past goals.'),
            ),
          for (final g in goals)
            _PastGoalRow(
              goal: g,
              deleting: _deleting.contains(g.id),
              onDelete: () => _delete(g),
              onTap: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push(AppPaths.dreamPhysiqueProgress(goalId: g.id));
              },
            ),
        ],
      ),
    );
  }
}

class _PastGoalRow extends StatelessWidget {
  const _PastGoalRow({
    required this.goal,
    required this.onTap,
    required this.onDelete,
    required this.deleting,
  });

  final PhysiqueGoalData goal;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final fmt = DateFormat('MMM d, y');
    final target = GoalDisplayCopy.targetLine(goal.targetBfPercent);
    final archived = goal.archivedAt;
    final dates = archived == null
        ? 'Started ${fmt.format(goal.startedAt)}'
        : 'Started ${fmt.format(goal.startedAt)} · '
              'Archived ${fmt.format(archived)}';
    return InkWell(
      onTap: onTap,
      borderRadius: HxRadius.mdAll,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: HxSpace.x3),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      GoalDisplayCopy.title(goal.targetAestheticStyle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PhysiqueText.heading(context, color: hx.onSurface),
                    ),
                    if (target != null)
                      Text(
                        target,
                        style: PhysiqueText.body(
                          context,
                          color: hx.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      dates,
                      style: PhysiqueText.label(context, color: hx.secondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete past goal',
                onPressed: deleting ? null : onDelete,
                icon: deleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.delete_outline_rounded, color: hx.secondary),
              ),
              Icon(Icons.chevron_right_rounded, color: hx.secondary),
            ],
          ),
        ),
      ),
    );
  }
}
