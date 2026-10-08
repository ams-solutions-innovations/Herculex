part of '../check_in_sheet.dart';

/// Why "Update roadmap" cannot start, said before a photo is taken. A missing
/// dream photo can be fixed right here.
class _BlockedView extends ConsumerWidget {
  const _BlockedView({
    required this.block,
    required this.goal,
    required this.onRecheck,
    required this.onClose,
  });

  final ReplanBlockedException block;
  final PhysiqueGoalData goal;

  /// Runs the readiness check again, e.g. after the dream photo was added.
  final VoidCallback onRecheck;
  final VoidCallback onClose;

  /// Stores a dream photo picked from the library, then checks again.
  Future<void> _pickDreamPhoto(BuildContext context, WidgetRef ref) async {
    final uuid = goal.syncUuid;
    if (uuid == null) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (picked == null) return;
    final ok = await ref
        .read(physiqueDreamPhotoRepositoryProvider)
        .save(File(picked.path), goalUuid: uuid);
    ref.invalidate(physiqueDreamPhotoProvider(uuid));
    if (!context.mounted) return;
    if (ok) {
      onRecheck();
    } else {
      AppNotice.show(
        context,
        'Could not save the photo',
        kind: AppNoticeKind.error,
      );
    }
  }

  String get _text => switch (block.block) {
    ReplanBlock.notStarted =>
      'Accept your roadmap first. Once it is running you can update it '
          'with new photos.',
    ReplanBlock.noDreamPhoto =>
      'Add your dream physique photo first. Herculex AI compares your new '
          'photo with it.',
    ReplanBlock.noWeight =>
      'Log your current weight first, so the new roadmap starts from where '
          'you are today.',
    ReplanBlock.tooSoon =>
      'You updated your roadmap recently. The next update is available '
          '${block.nextEligibleDate == null ? 'soon' : DateFormat('EEE, MMM d').format(block.nextEligibleDate!)}.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Notice(text: _text),
        const SizedBox(height: HxSpace.x6),
        if (block.block == ReplanBlock.noDreamPhoto) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _pickDreamPhoto(context, ref),
              child: const Text('Choose dream photo'),
            ),
          ),
          const SizedBox(height: HxSpace.x2),
        ],
        SizedBox(
          width: double.infinity,
          child: block.block == ReplanBlock.noDreamPhoto
              ? TextButton(onPressed: onClose, child: const Text('Close'))
              : FilledButton(onPressed: onClose, child: const Text('Close')),
        ),
      ],
    );
  }
}

String _percent(double v) =>
    '${v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}%';

/// The proposed roadmap next to what the analysis found. Nothing is stored
/// until the member taps "Use this roadmap".
class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({
    required this.proposal,
    required this.goalId,
    required this.busy,
    required this.onUse,
    required this.onKeep,
  });

  final ReplanProposal proposal;
  final int goalId;
  final bool busy;
  final VoidCallback onUse;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final wf = ref.watch(weightFormatProvider);
    final previousDream = ref.watch(goalTargetProvider).dreamKg;
    final analysis = proposal.analysis;
    final plan = proposal.proposal;
    // Dates from today: the carried-over weeks of a continued phase only
    // matter to the stored length, not to what lies ahead.
    final schedule = RoadmapScheduleCalculator.build(
      phases: [
        for (final d in plan.phases)
          SchedulePhaseInput(
            phase: d.phase,
            plannedWeeks: d.plannedWeeks,
            targetWeightKg: d.targetWeightKg,
            targetBfPercent: d.targetBfPercent,
          ),
      ],
      anchor: proposal.analyzedAt,
      now: proposal.analyzedAt,
      startWeightKg: proposal.weightKg,
    );
    final dream = schedule.dreamWeightKg;
    final months = analysis.estimatedMonths;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your new roadmap',
          style: PhysiqueText.heading(context, color: hx.onSurface),
        ),
        const SizedBox(height: HxSpace.x1),
        Text(
          'Nothing changes until you use it.',
          style: PhysiqueText.label(context, color: hx.onSurfaceVariant),
        ),
        const SizedBox(height: HxSpace.x4),
        Text(
          'Body fat now about ${_percent(analysis.currentEstimatedBf)}, '
          'target ${_percent(analysis.targetBfPercent)}.',
          style: PhysiqueText.body(context, color: hx.onSurface),
        ),
        Text(
          'About $months ${months == 1 ? 'month' : 'months'} to your dream '
          'physique.',
          style: PhysiqueText.body(context, color: hx.onSurface),
        ),
        if (plan.extendedBeyondEstimate)
          Text(
            'At a safe pace this plan takes about ${schedule.totalMonths} '
            'months.',
            style: PhysiqueText.body(context, color: hx.onSurfaceVariant),
          ),
        if (dream != null) ...[
          const SizedBox(height: HxSpace.x2),
          Text(
            'Dream weight ${wf.format(dream)}'
            '${previousDream == null || previousDream == dream ? '' : ' (was ${wf.format(previousDream)})'}',
            key: const Key('replan-dream-weight'),
            style: PhysiqueText.bodyStrong(context, color: hx.onSurface),
          ),
        ],
        const SizedBox(height: HxSpace.x4),
        for (final p in schedule.phases) ...[
          Text(
            p.phase.label,
            style: PhysiqueText.bodyStrong(context, color: hx.onSurface),
          ),
          Wrap(
            spacing: HxSpace.x3,
            children: [
              if (roadmapWeightRange(p, wf).isNotEmpty)
                Text(
                  roadmapWeightRange(p, wf),
                  style: PhysiqueText.bodyTabular(context, color: hx.onSurface),
                ),
              if (roadmapPace(p, wf).isNotEmpty)
                Text(
                  roadmapPace(p, wf),
                  style: PhysiqueText.labelTabular(
                    context,
                    color: hx.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          Text(
            '${p.plannedWeeks} weeks · ${roadmapDateRange(p)}',
            style: PhysiqueText.label(context, color: hx.onSurfaceVariant),
          ),
          const SizedBox(height: HxSpace.x3),
        ],
        const SizedBox(height: HxSpace.x3),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('replan-use'),
            onPressed: busy ? null : onUse,
            child: const Text('Use this roadmap'),
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            key: const Key('replan-keep'),
            onPressed: busy ? null : onKeep,
            child: const Text('Keep my current roadmap'),
          ),
        ),
      ],
    );
  }
}
