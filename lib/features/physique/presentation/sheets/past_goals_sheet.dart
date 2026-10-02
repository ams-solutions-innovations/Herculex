import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_sheet.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/goal_display_copy.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:intl/intl.dart';

/// Archived goals, newest-archived first. Read-only history (D-03): tapping
/// one opens the archived progress screen, which hides every action.
class PastGoalsSheet extends ConsumerWidget {
  const PastGoalsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return HxSheet.show<void>(context, builder: (_) => const PastGoalsSheet());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals =
        ref.watch(archivedPhysiqueGoalsProvider).asData?.value ??
        const <PhysiqueGoalData>[];
    return HxSheet(
      title: 'Past goals',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in goals)
            _PastGoalRow(
              goal: g,
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
  const _PastGoalRow({required this.goal, required this.onTap});

  final PhysiqueGoalData goal;
  final VoidCallback onTap;

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
              Icon(Icons.chevron_right_rounded, color: hx.secondary),
            ],
          ),
        ),
      ),
    );
  }
}
