import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/features/physique/application/goal_target_provider.dart';

/// Stores a target weight the member typed, through the one place that knows
/// about the roadmap. Returns true when it was stored.
///
/// When the roadmap has to change instead (the running phase cannot end at
/// that weight), nothing is written and a notice says why, with a shortcut to
/// the roadmap editor.
Future<bool> saveGoalTarget(
  BuildContext context,
  WidgetRef ref,
  double kg,
) async {
  // Grabbed before the await: the sheet that called this usually pops.
  final notices = AppNotice.of(context);
  final router = GoRouter.maybeOf(context);
  final result = await ref.read(goalTargetControllerProvider).setTarget(kg);
  switch (result) {
    case GoalTargetApplied():
      return true;
    case GoalTargetNeedsRoadmapChange(:final goalId, :final message):
      notices.show(
        message,
        kind: AppNoticeKind.info,
        actionLabel: 'Edit roadmap',
        onAction: () =>
            router?.push(AppPaths.dreamPhysiqueProgress(goalId: goalId)),
      );
      return false;
  }
}
