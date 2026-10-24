import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/programs/data/weekly_adaptation_repository.dart';
import 'package:herculex/features/programs/domain/weekly_adaptation_engine.dart';

/// Small confirmation surface for a deterministic schedule proposal.  It
/// deliberately offers one recommendation, not an AI conversation or a menu
/// of opaque alternatives.
Future<bool> showWeeklyAdaptationSheet(
  BuildContext context, {
  required WeeklyAdaptationRepository repository,
  required StoredAdaptationProposal proposal,
  bool skipOnDecline = true,
}) async {
  // After a finished session there is nothing left to skip, so the user may
  // simply swipe the suggestion away.
  final afterSession =
      proposal.proposal.trigger == AdaptationTrigger.incompleteWorkout;
  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        isDismissible: afterSession,
        enableDrag: afterSession,
        showDragHandle: true,
        builder: (sheetContext) => _WeeklyAdaptationSheet(
          proposal: proposal,
          accept: () async {
            await repository.accept(proposal.id);
            if (sheetContext.mounted) {
              Navigator.pop(sheetContext, true);
            }
          },
          decline: () async {
            await repository.decline(proposal.id, skipSource: skipOnDecline);
            if (sheetContext.mounted) {
              Navigator.pop(sheetContext, false);
            }
          },
        ),
      ) ??
      false;
}

class _WeeklyAdaptationSheet extends StatefulWidget {
  const _WeeklyAdaptationSheet({
    required this.proposal,
    required this.accept,
    required this.decline,
  });

  final StoredAdaptationProposal proposal;
  final Future<void> Function() accept;
  final Future<void> Function() decline;

  @override
  State<_WeeklyAdaptationSheet> createState() => _WeeklyAdaptationSheetState();
}

class _WeeklyAdaptationSheetState extends State<_WeeklyAdaptationSheet> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AdaptationStaleException
              ? error.toString()
              : 'Could not save this change. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final proposal = widget.proposal;
    final plan = proposal.proposal;
    final hasChanges = plan.hasChanges;
    final afterSession = plan.trigger == AdaptationTrigger.incompleteWorkout;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(switch (plan.trigger) {
              AdaptationTrigger.lowRecovery => 'Adjust today\'s workout?',
              AdaptationTrigger.incompleteWorkout =>
                hasChanges
                    ? 'Make up the missed sets?'
                    : 'Some sets were left out',
              AdaptationTrigger.skippedWorkout =>
                hasChanges ? 'Adjust this week?' : 'Skip this workout?',
            }, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(plan.reason, style: TextStyle(color: AppColors.secondary)),
            if (hasChanges) ...[
              const SizedBox(height: 18),
              Text(
                plan.trigger == AdaptationTrigger.lowRecovery
                    ? 'Keep the main work and reduce the work that costs more recovery.'
                    : 'Prioritise your goal while keeping the extra work within your recovery and weekly plan.',
                style: TextStyle(color: AppColors.secondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              for (final change in plan.changes.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.add_task_rounded, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          change.addedExercise == null
                              ? '${change.plan.name}: ${change.plan.workingSetCount} working sets after adjustment.'
                              : '${proposal.scheduleDates[change.scheduleId] ?? change.plan.name}: '
                                    '${proposal.exerciseNames[change.addedExercise!.exerciseId] ?? 'Exercise'} '
                                    '+${change.addedExercise!.workingSetCount} working sets.',
                        ),
                      ),
                    ],
                  ),
                ),
              if (plan.uncoveredVolume.isNotEmpty)
                Text(
                  'Some volume is intentionally left out to protect recovery.',
                  style: TextStyle(color: AppColors.secondary, fontSize: 12),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!),
              ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(hasChanges ? widget.accept : widget.decline),
                child: Text(switch ((afterSession, hasChanges)) {
                  (true, true) => 'Add to remaining workouts',
                  (true, false) => 'OK',
                  (false, true) =>
                    plan.trigger == AdaptationTrigger.skippedWorkout
                        ? 'Skip and adjust this week'
                        : 'Start adapted workout',
                  (false, false) => 'Skip workout',
                }),
              ),
            ),
            if (hasChanges)
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => _run(widget.decline),
                  child: Text(switch (plan.trigger) {
                    AdaptationTrigger.lowRecovery => 'Start original workout',
                    AdaptationTrigger.incompleteWorkout =>
                      'Keep the plan as is',
                    AdaptationTrigger.skippedWorkout =>
                      'Skip without changing the plan',
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
