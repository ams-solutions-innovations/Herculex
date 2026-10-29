import 'package:flutter/material.dart';
import 'package:herculex/features/workouts/domain/workout_action_message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/training_coaching/application/training_coaching_providers.dart';
import 'package:herculex/features/training_coaching/data/training_coaching_repository.dart';
import 'package:herculex/features/training_coaching/domain/training_coaching.dart';
import 'package:intl/intl.dart';

class CoachingPreviewSheet extends ConsumerStatefulWidget {
  const CoachingPreviewSheet({
    super.key,
    required this.proposalId,
    this.permanent = false,
  });
  final int proposalId;
  final bool permanent;
  static Future<void> show(
    BuildContext context,
    int id, {
    bool permanent = false,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CoachingPreviewSheet(proposalId: id, permanent: permanent),
  );
  @override
  ConsumerState<CoachingPreviewSheet> createState() => _PreviewState();
}

class _PreviewState extends ConsumerState<CoachingPreviewSheet> {
  CoachingPreview? preview;
  bool busy = true, confirmed = false;
  String? error;
  int minutes = 30;
  DateTime? extraAt;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
      preview = null;
    });
    try {
      final repo = ref.read(trainingCoachingRepositoryProvider);
      final value = widget.permanent
          ? await repo.permanentPreview(widget.proposalId)
          : await repo.preview(
              widget.proposalId,
              availableMinutes: minutes,
              extraAt: extraAt,
            );
      if (mounted) setState(() => preview = value);
    } catch (e) {
      if (mounted) setState(() => error = workoutActionMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _extra() async {
    final now = ref.read(clockProvider).now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 7)),
      initialDate: now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
    );
    if (time == null || !mounted) return;
    extraAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final proposal = ref
        .watch(trainingCoachingProvider(null))
        .valueOrNull
        ?.where((p) => p.id == widget.proposalId)
        .firstOrNull;
    final canAddDay =
        preview?.signal.kind == CoachingKind.catchUp ||
        proposal?.kind == CoachingKind.catchUp.name;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.permanent
                        ? 'Keep this program change'
                        : 'Review training change',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (confirmed) ...[
              const Text('Your confirmed training plan has been saved.'),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ] else ...[
              if (!widget.permanent)
                DropdownButtonFormField<int>(
                  initialValue: minutes,
                  decoration: const InputDecoration(
                    labelText: 'Available minutes',
                  ),
                  items: [
                    for (final m in [15, 20, 30, 45, 60])
                      DropdownMenuItem(value: m, child: Text('$m minutes')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) {
                          minutes = v!;
                          _load();
                        },
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (error != null) ...[
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: busy ? null : _load,
                  child: const Text('Refresh preview'),
                ),
              ],
              if (preview != null) ...[
                Text(preview!.signal.detail),
                Text(
                  widget.permanent
                      ? 'Changes apply to the future program occurrences listed below.'
                      : preview!.signal.oneOff
                      ? 'This only affects the listed one-time sessions. Skipping an optional session creates no catch-up reminder.'
                      : 'Try this for two comparable workouts, for up to 28 days. Then review whether to keep it.',
                ),
                if (preview!.signal.kind == CoachingKind.reduceSets)
                  const Text(
                    'Set count changes keep the prescribed effort. Weight and proximity to failure are not increased.',
                  ),
                for (final c in preview!.changes)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${DateFormat.yMMMd().format(c.date)} · ${c.after.name}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${_count(c.before)} → ${_count(c.after)} working sets',
                          ),
                          if (c.beforeMinutes != null && c.afterMinutes != null)
                            Text(
                              'Estimated time: ${c.beforeMinutes} → ${c.afterMinutes} minutes',
                            ),
                          for (final m in {
                            ...c.beforeVolume.keys,
                            ...c.afterVolume.keys,
                          })
                            if (((c.beforeVolume[m] ?? 0) -
                                        (c.afterVolume[m] ?? 0))
                                    .abs() >
                                .01)
                              Text(
                                '$m: ${(c.beforeVolume[m] ?? 0).toStringAsFixed(1)} → ${(c.afterVolume[m] ?? 0).toStringAsFixed(1)} estimated sets',
                              ),
                          const Text('Before'),
                          for (final e in c.before.exercises)
                            Text(
                              '${preview!.exerciseNames[e.exerciseId]} · ${e.sets.where((s) => !s.isWarmup).length} sets',
                            ),
                          const SizedBox(height: 6),
                          const Text('After'),
                          for (final e in c.after.exercises)
                            Text(
                              '${preview!.exerciseNames[e.exerciseId]} · ${e.sets.where((s) => !s.isWarmup).length} sets',
                            ),
                        ],
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await ref
                                .read(trainingCoachingRepositoryProvider)
                                .accept(preview!);
                            if (mounted) setState(() => confirmed = true);
                          } catch (e) {
                            if (mounted)
                              setState(() {
                                error = workoutActionMessage(e);
                                preview = null;
                              });
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: Text(
                    widget.permanent
                        ? 'Confirm permanent change'
                        : 'Confirm this plan',
                  ),
                ),
              ],
              if (!widget.permanent && canAddDay)
                TextButton.icon(
                  onPressed: busy ? null : _extra,
                  icon: const Icon(Icons.event_available),
                  label: const Text('Review an optional short workout'),
                ),
              if (extraAt != null)
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          extraAt = null;
                          _load();
                        },
                  child: const Text('Use existing workouts instead'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  int _count(dynamic plan) => (plan.exercises as List).fold<int>(
    0,
    (n, dynamic e) =>
        n + (e.sets as List).where((dynamic s) => !s.isWarmup).length,
  );
}
