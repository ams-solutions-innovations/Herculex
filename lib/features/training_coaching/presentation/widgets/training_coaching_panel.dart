import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:herculex/features/workouts/domain/workout_action_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/training_coaching/application/training_coaching_providers.dart';
import 'package:herculex/features/training_coaching/domain/training_coaching.dart';
import 'package:herculex/features/training_coaching/presentation/sheets/coaching_preview_sheet.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';

class TrainingCoachingPanel extends ConsumerWidget {
  const TrainingCoachingPanel({super.key, this.sessionId});
  final int? sessionId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposals = ref.watch(trainingCoachingProvider(sessionId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sessionId != null) _ReasonCheckIn(sessionId: sessionId!),
        ...proposals.valueOrNull
                ?.take(3)
                .map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CoachingCard(key: ValueKey(row.syncUuid), row: row),
                  ),
                ) ??
            [],
        if (proposals.hasError)
          TextButton.icon(
            onPressed: () =>
                ref.invalidate(trainingCoachingProvider(sessionId)),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry training suggestions'),
          ),
      ],
    );
  }
}

class _CoachingCard extends ConsumerStatefulWidget {
  const _CoachingCard({super.key, required this.row});
  final TrainingCoachingProposalData row;
  @override
  ConsumerState<_CoachingCard> createState() => _CoachingCardState();
}

class _CoachingCardState extends ConsumerState<_CoachingCard> {
  bool busy = false;
  String? error;
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = workoutActionMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(trainingCoachingRepositoryProvider);
    final row = widget.row, signal = repo.signal(widget.row);
    final payload = jsonDecode(row.payloadJson) as Map;
    final result = payload['result'] as Map?;
    final feedback = row.status == 'review'
        ? ref.watch(coachingFeedbackProvider(row.id)).valueOrNull
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.status == 'review'
                  ? 'Review your training trial'
                  : signal.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              row.status == 'trial'
                  ? 'Trying this change for two comparable workouts, for up to 28 days. Your original program is available if you cancel.'
                  : signal.detail,
            ),
            if (result != null) ...[
              Text(
                '${result['targetMet']} of ${result['completed']} trial workouts met the planned set count.',
              ),
              Text(
                (result['minutes'] as List).isEmpty
                    ? 'No completed trial duration yet.'
                    : 'Trial durations: ${(result['minutes'] as List).join(', ')} minutes.',
              ),
              Text(switch (result['conclusion']) {
                'manageable' =>
                  'The shorter prescription was manageable and comparable benchmarks showed no recorded decline.',
                'review' => 'Review the results before keeping the change.',
                _ =>
                  'There is not enough comparable data to judge whether the change helped.',
              }),
            ],
            if (feedback != null && row.status == 'review') ...[
              Text(
                feedback.pain
                    ? 'You reported pain during this trial.'
                    : feedback.fatigueAfter == null
                    ? 'How did the trial feel? (Optional)'
                    : feedback.fatigueAfter!
                    ? 'You reported that the trial was still tiring.'
                    : 'You reported that the trial felt manageable.',
              ),
              if (feedback.fatigueBefore != null)
                Text(
                  feedback.fatigueBefore!
                      ? 'Before the trial: unusual fatigue was reported.'
                      : 'Before the trial: no unusual fatigue was reported.',
                ),
              if (feedback.fatigueAfter == null && !feedback.pain)
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Manageable'),
                      onPressed: busy
                          ? null
                          : () => _run(
                              () => repo.saveFeedback(row.id, tiring: false),
                            ),
                    ),
                    ActionChip(
                      label: const Text('Still tiring'),
                      onPressed: busy
                          ? null
                          : () => _run(
                              () => repo.saveFeedback(row.id, tiring: true),
                            ),
                    ),
                    ActionChip(
                      label: const Text('Pain'),
                      onPressed: busy
                          ? null
                          : () => _run(
                              () => repo.saveFeedback(
                                row.id,
                                tiring: true,
                                pain: true,
                              ),
                            ),
                    ),
                  ],
                ),
            ],
            if (row.programId == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Link your workouts to a program to apply changes.',
                ),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (row.status == 'proposed') ...[
                  FilledButton.tonal(
                    onPressed: busy || row.programId == null
                        ? null
                        : () => CoachingPreviewSheet.show(context, row.id),
                    child: const Text('Review suggestion'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _run(() => repo.decline(row.id)),
                    child: const Text('Dismiss'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _run(() => repo.snooze(row.id)),
                    child: const Text('Later'),
                  ),
                ],
                if (row.status == 'review')
                  FilledButton.tonal(
                    onPressed: busy
                        ? null
                        : () => CoachingPreviewSheet.show(
                            context,
                            row.id,
                            permanent: true,
                          ),
                    child: const Text('Review permanent change'),
                  ),
                if (row.status == 'review')
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            int? sets;
                            if (signal.kind == CoachingKind.reduceSets) {
                              sets = await showModalBottomSheet<int>(
                                context: context,
                                builder: (context) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (
                                        var n = 1;
                                        n <
                                            (signal.exercise!['planned']
                                                as int);
                                        n++
                                      )
                                        ListTile(
                                          title: Text(
                                            'Try $n working ${n == 1 ? 'set' : 'sets'}',
                                          ),
                                          onTap: () =>
                                              Navigator.pop(context, n),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                              if (sets == null || !mounted) return;
                            }
                            await _run(() async {
                              final draft = await repo.adjustTrial(
                                row.id,
                                targetSets: sets,
                              );
                              if (context.mounted)
                                await CoachingPreviewSheet.show(context, draft);
                            });
                          },
                    child: const Text('Adjust the trial'),
                  ),
                if (['trial', 'review'].contains(row.status))
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _run(() => repo.cancelTrial(row.id)),
                    child: const Text('Return to original program'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonCheckIn extends ConsumerStatefulWidget {
  const _ReasonCheckIn({required this.sessionId});
  final int sessionId;
  @override
  ConsumerState<_ReasonCheckIn> createState() => _ReasonState();
}

class _ReasonState extends ConsumerState<_ReasonCheckIn> {
  bool skipped = false, busy = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    final snapshot = ref
        .watch(workoutBehaviorProvider(widget.sessionId))
        .valueOrNull;
    if (snapshot == null || skipped) return const SizedBox.shrink();
    final observation = CoachingObservation.decode(snapshot.snapshotJson);
    if (!observation.reliable ||
        observation.policy != 'unknown' ||
        observation.data['reasonDismissed'] == true)
      return const SizedBox.shrink();
    final changed =
        observation.original.any(
          (p) =>
              (observation.actualFor(p)?['completed'] as int? ?? 0) !=
              p['planned'],
        ) ||
        observation.actual.any(
          (a) => !observation.original.any(
            (p) => p['row'] == a['row'] && p['exercise'] == a['exercise'],
          ),
        );
    if (!changed) return const SizedBox.shrink();
    final behavior = ref.read(trainingCoachingRepositoryProvider).behavior;
    Future<void> answer(ReportReason? reason) async {
      setState(() {
        busy = true;
        error = null;
      });
      try {
        if (reason == null) {
          await behavior.dismissReason(widget.sessionId);
        } else {
          await behavior.saveReason(widget.sessionId, reason);
        }
        if (mounted) setState(() => skipped = true);
      } catch (e) {
        if (mounted) setState(() => error = workoutActionMessage(e));
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What changed your workout?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Optional — this helps distinguish limited time from intentionally doing less.',
            ),
            if (error != null) Text(error!),
            Wrap(
              spacing: 8,
              children: [
                for (final reason in ReportReason.values)
                  ActionChip(
                    label: Text(switch (reason) {
                      ReportReason.time => 'Time',
                      ReportReason.fatigue => 'Fatigue',
                      ReportReason.pain => 'Pain',
                      ReportReason.equipment => 'Equipment',
                      ReportReason.preference => 'Preference',
                    }),
                    onPressed: busy ? null : () => answer(reason),
                  ),
                ActionChip(
                  label: const Text('Other / skip'),
                  onPressed: busy ? null : () => answer(null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
