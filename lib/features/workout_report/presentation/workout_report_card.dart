import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/features/workout_report/application/workout_report_providers.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workout_report/presentation/report_context_sheet.dart';
import 'package:herculex/features/workout_report/presentation/workout_report_details.dart';

class WorkoutReportCard extends ConsumerWidget {
  const WorkoutReportCard({super.key, required this.sessionId});
  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(workoutReportProvider(sessionId));
    final colors = Theme.of(context).colorScheme;

    return Container(
      key: const ValueKey('workout-report-card'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: report.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Preparing your training report…',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        error: (_, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Workout saved. Report unavailable for now.'),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () =>
                    ref.invalidate(workoutReportProvider(sessionId)),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry report'),
              ),
            ],
          ),
        ),
        data: (value) => value == null
            ? const SizedBox.shrink()
            : InkWell(
                onTap: () => _openDetails(context),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Training report',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            value.changes.isEmpty &&
                                    value.completedSets >= value.plannedSets
                                ? Icons.check_circle_rounded
                                : Icons.tune_rounded,
                            size: 16,
                            color:
                                value.changes.isEmpty &&
                                    value.completedSets >= value.plannedSets
                                ? const Color(0xFF30D158)
                                : const Color(0xFFFF9F0A),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _statusLine(value),
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // The single most useful takeaway; the rest lives in
                      // the full report.
                      if (value.highlights.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _toneIcon(value.highlights.first.tone),
                              size: 18,
                              color: _toneColor(
                                value.highlights.first.tone,
                                colors,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _takeaway(value.highlights.first),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 8),

                      // Action buttons
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => _openDetails(context),
                            icon: const Icon(
                              Icons.analytics_outlined,
                              size: 17,
                            ),
                            label: const Text('View report'),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Add context',
                            onPressed: () =>
                                editReportContext(context, ref, sessionId),
                            icon: const Icon(Icons.tune_rounded, size: 18),
                            style: IconButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  void _openDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => WorkoutReportDetails(sessionId: sessionId),
    );
  }

  static String _statusLine(WorkoutReport report) {
    final sets = report.plannedSets > 0
        ? '${report.completedSets}/${report.plannedSets} sets'
        : '${report.completedSets} sets';
    final changes = report.changes.length;
    if (changes == 0) {
      return report.completedSets >= report.plannedSets
          ? 'On plan · $sets'
          : sets;
    }
    return '$sets · $changes ${changes == 1 ? 'change' : 'changes'}';
  }

  static String _takeaway(ReportFinding finding) => finding.exerciseName == null
      ? finding.title
      : '${finding.exerciseName}: ${finding.title}';

  Color _toneColor(ReportTone tone, ColorScheme colors) => switch (tone) {
    ReportTone.positive => const Color(0xFF30D158),
    ReportTone.caution => const Color(0xFFFF9F0A),
    ReportTone.neutral => colors.primary,
  };

  IconData _toneIcon(ReportTone tone) => switch (tone) {
    ReportTone.positive => Icons.check_rounded,
    ReportTone.caution => Icons.warning_amber_rounded,
    ReportTone.neutral => Icons.lightbulb_outline_rounded,
  };
}

Future<void> editReportContext(
  BuildContext context,
  WidgetRef ref,
  int sessionId,
) async {
  final repository = ref.read(workoutReportRepositoryProvider);
  final notices = AppNotice.of(context);
  try {
    final initial = await repository.contextFor(sessionId);
    if (!context.mounted) return;
    final result = await showReportContextSheet(context, initial);
    if (result != null) await repository.saveContext(sessionId, result);
  } catch (_) {
    if (context.mounted) {
      notices.show(
        'Context could not be saved. Please try again.',
        kind: AppNoticeKind.error,
      );
    }
  }
}
