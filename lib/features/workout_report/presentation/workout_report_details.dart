import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/features/workout_report/application/workout_report_providers.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workout_report/presentation/workout_report_card.dart';

class WorkoutReportDetails extends ConsumerStatefulWidget {
  const WorkoutReportDetails({super.key, required this.sessionId});
  final int sessionId;

  @override
  ConsumerState<WorkoutReportDetails> createState() =>
      _WorkoutReportDetailsState();
}

class _WorkoutReportDetailsState extends ConsumerState<WorkoutReportDetails> {
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workoutReportProvider(widget.sessionId));
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: colors.error,
                ),
                const SizedBox(height: 12),
                const Text('Report could not be loaded.'),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(workoutReportProvider(widget.sessionId)),
                  child: const Text('Retry report'),
                ),
              ],
            ),
          ),
          data: (report) => report == null
              ? const Center(child: Text('No report yet.'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    // Header Bar
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your training report',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 13,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Your completed workout',
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Top Overview Hero Card
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _heroStat(
                              context,
                              value:
                                  '${report.completedSets}/${report.plannedSets}',
                              label: 'Sets',
                              icon: Icons.fitness_center_rounded,
                              iconColor: colors.primary,
                            ),
                          ),
                          _verticalDivider(colors),
                          Expanded(
                            child: _heroStat(
                              context,
                              value: '${report.minutes}m',
                              label: 'Duration',
                              icon: Icons.timer_outlined,
                              iconColor: colors.secondary,
                            ),
                          ),
                          _verticalDivider(colors),
                          Expanded(
                            child: _heroStat(
                              context,
                              value: report.changes.isEmpty
                                  ? 'On plan'
                                  : 'Adapted',
                              label: 'Status',
                              icon: report.changes.isEmpty
                                  ? Icons.verified_outlined
                                  : Icons.tune_rounded,
                              iconColor: report.changes.isEmpty
                                  ? const Color(0xFF30D158)
                                  : const Color(0xFFFF9F0A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Insights and next steps
                    _sectionTitle(
                      context,
                      icon: Icons.tips_and_updates_outlined,
                      title: 'Next time',
                    ),
                    const SizedBox(height: 8),
                    if (report.findings.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'No special findings for this workout.',
                        ),
                      )
                    else
                      for (final finding in report.highlights.take(2))
                        _compactFindingCard(context, finding),
                    if (report.findings.isNotEmpty)
                      ExpansionTile(
                        key: const Key('workout-review-details'),
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Details and all findings'),
                        children: [
                          for (final finding in report.findings)
                            _modernFindingCard(context, finding),
                        ],
                      ),

                    const SizedBox(height: 16),

                    if (report.changes.isNotEmpty ||
                        report.muscleChanges.isNotEmpty)
                      Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          title: const Text(
                            'Plan vs. what you did',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${report.changes.length} '
                            '${report.changes.length == 1 ? 'change' : 'changes'}',
                          ),
                          children: [
                            // What changed section (if changes exist)
                            if (report.changes.isNotEmpty) ...[
                              _sectionTitle(
                                context,
                                icon: Icons.edit_note_rounded,
                                title: 'What changed',
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerLowest,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: colors.outlineVariant.withValues(
                                      alpha: 0.25,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    for (final change in report.changes)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.arrow_right_rounded,
                                              size: 18,
                                              color: colors.primary,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                change,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Direct / primary muscle work
                            if (report.muscleChanges.isNotEmpty) ...[
                              _sectionTitle(
                                context,
                                icon: Icons.accessibility_new_rounded,
                                title: 'Direct / primary muscle work',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Volume differences compared to your starting plan:',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final e in report.muscleChanges.entries)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            (e.value >= 0
                                                    ? const Color(0xFF30D158)
                                                    : const Color(0xFFFF9F0A))
                                                .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color:
                                              (e.value >= 0
                                                      ? const Color(0xFF30D158)
                                                      : const Color(0xFFFF9F0A))
                                                  .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            e.key,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: e.value >= 0
                                                  ? const Color(0xFF30D158)
                                                  : const Color(0xFFFF9F0A),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '${e.value > 0 ? '+' : ''}${e.value} sets',
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ),
                      ),

                    // Actions Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: busy ? null : _preview,
                            icon: busy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.auto_fix_high_rounded),
                            label: const Text('Preview a program adjustment'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => editReportContext(
                              context,
                              ref,
                              widget.sessionId,
                            ),
                            icon: const Icon(Icons.tune_rounded, size: 18),
                            label: const Text('Update optional context'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 13,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Your program changes only after you confirm a preview.',
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _sectionTitle(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 4),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );

  Widget _heroStat(
    BuildContext context, {
    required String value,
    required String label,
    required IconData icon,
    required Color iconColor,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 17, color: iconColor),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );

  Widget _verticalDivider(ColorScheme colors) => Container(
    width: 1,
    height: 30,
    color: colors.outlineVariant.withValues(alpha: 0.25),
  );

  Widget _compactFindingCard(BuildContext context, ReportFinding finding) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              finding.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              finding.nextStep,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modernFindingCard(BuildContext context, ReportFinding finding) {
    final colors = Theme.of(context).colorScheme;
    final toneColor = switch (finding.tone) {
      ReportTone.positive => const Color(0xFF30D158),
      ReportTone.caution => const Color(0xFFFF9F0A),
      ReportTone.neutral => colors.primary,
    };
    final toneIcon = switch (finding.tone) {
      ReportTone.positive => Icons.check_circle_rounded,
      ReportTone.caution => Icons.warning_amber_rounded,
      ReportTone.neutral => Icons.lightbulb_outline_rounded,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: toneColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(toneIcon, size: 15, color: toneColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (finding.exerciseName != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          finding.exerciseName!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    Text(
                      finding.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _supportLabel(finding.support),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Detail Text
          Text(
            finding.detail,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: colors.onSurface.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 8),

          // Recommendation Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    finding.nextStep,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _supportLabel(ReportSupport value) => switch (value) {
    ReportSupport.recorded => 'Verified',
    ReportSupport.pattern => 'Pattern',
    ReportSupport.possible => 'Factor',
    ReportSupport.unknown => 'Observed',
  };

  Future<void> _preview() async {
    setState(() => busy = true);
    final actions = ref.read(workoutReportPlanActionsProvider);
    final notices = AppNotice.of(context);
    try {
      final preview = await actions.preview(widget.sessionId);
      if (!mounted) {
        return;
      }
      if (preview == null) {
        notices.show(
          'No supported change fits the upcoming schedule. Keep the plan and review the next comparable session.',
          kind: AppNoticeKind.info,
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.tune_rounded, size: 20),
              SizedBox(width: 8),
              Text('Program adjustment'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    preview.proposal.proposal.reason,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                for (final change in preview.proposal.proposal.changes) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${preview.dates[change.scheduleId]} · ${change.plan.name}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${preview.beforeSets[change.scheduleId]} sets',
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: Colors.grey,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_rounded, size: 13),
                            const SizedBox(width: 6),
                            Text(
                              '${change.plan.workingSetCount} working sets',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        for (final exercise in change.plan.exercises)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '• ${exercise.workingSetCount} sets · ${preview.exerciseNames[exercise.exerciseId] ?? exercise.slotRole}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                Text(
                  'This adjusts only the upcoming scheduled sessions. Your base program is preserved.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep current plan'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm adjustment'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await actions.accept(preview);
        if (mounted) {
          notices.show('Confirmed adjustment saved.');
        }
      } else {
        await actions.adaptations.decline(preview.proposal.id);
      }
    } catch (_) {
      if (mounted) {
        notices.show(
          'The schedule changed or this preview is unavailable. Reopen the preview.',
          kind: AppNoticeKind.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }
}
