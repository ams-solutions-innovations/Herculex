import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/hx_card.dart';
import 'package:herculex/design_system/components/hx_pill.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/goal_display_copy.dart';
import 'package:herculex/features/physique/presentation/physique_text.dart';
import 'package:herculex/features/physique/presentation/widgets/load_state_views.dart';
import 'package:intl/intl.dart';

/// Goal style, target and start date; an "Archived" pill for past goals.
class GoalHeaderCard extends ConsumerWidget {
  const GoalHeaderCard({super.key, required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(physiqueGoalProvider(goalId));
    final goal = async.asData?.value;
    final hx = context.hx;

    Widget body;
    if (goal == null) {
      body = async.hasError
          ? PhysiqueLoadError(
              onRetry: () => ref.invalidate(physiqueGoalProvider(goalId)),
            )
          : const PhysiqueLoading();
    } else {
      final started = DateFormat('MMM d, y').format(goal.startedAt);
      final target = GoalDisplayCopy.targetLine(goal.targetBfPercent);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  GoalDisplayCopy.title(goal.targetAestheticStyle),
                  style: PhysiqueText.heading(context, color: hx.onSurface),
                ),
              ),
              if (goal.status == 'archived') ...[
                const SizedBox(width: HxSpace.x2),
                const HxTextPill(label: 'Archived'),
              ],
            ],
          ),
          const SizedBox(height: HxSpace.x1),
          Text(
            target == null ? 'Started $started' : '$target · started $started',
            style: PhysiqueText.body(context, color: hx.onSurfaceVariant),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: HxCard(child: body),
    );
  }
}
