import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_controller.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_payload.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/ai_narrative_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/nutrition_section_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/physique_section_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/recovery_section_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/section_card_scaffold.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/tdee_shift_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/training_section_card.dart';
import 'package:intl/intl.dart';

/// One week's report (RPT-01 to RPT-05).
///
/// Everything measured is rendered from the stored `payload_json` (frozen,
/// never recomputed). Entering the screen asks the controller to open the week
/// exactly once: that persists the snapshot if needed and starts the Herculex
/// AI narrative in the background, so the screen never blocks on the AI call
/// (D-02, D-03). The live row arrives through [weeklyReportProvider], so the
/// narrative card updates by itself when the call finishes.
class WeeklyReportView extends ConsumerStatefulWidget {
  const WeeklyReportView({super.key, required this.week});

  final IsoWeek week;

  @override
  ConsumerState<WeeklyReportView> createState() => _WeeklyReportViewState();
}

class _WeeklyReportViewState extends ConsumerState<WeeklyReportView> {
  /// How [WeeklyReportController.open] ended, once it has. Only consulted when
  /// there is no stored row.
  WeeklyReportOpenResult? _result;

  @override
  void initState() {
    super.initState();
    // After the first frame, once and only here: a rebuild must never start
    // another generation (T-29-76).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_open());
    });
  }

  Future<void> _open() async {
    final result = await ref
        .read(weeklyReportControllerProvider)
        .open(widget.week);
    if (!mounted) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final week = widget.week;
    final row = ref.watch(weeklyReportProvider(week));
    final enabled = ref.watch(weeklyReportEnabledProvider);

    return HxScreenShell(
      title: 'Week ${week.isoWeek}',
      children: [
        Text(_rangeLabel(week), style: ReportText.label(context)),
        const SizedBox(height: HxSpace.x6),
        row.when(
          loading: () => const _Message('Loading report'),
          error: (_, _) => const _LoadError(),
          data: (record) {
            if (record != null) return _ReportBody(record: record, week: week);
            if (!enabled || _result is WeeklyReportDisabled) {
              return const _TurnOnState();
            }
            return switch (_result) {
              WeeklyReportNoData() => const _NoDataState(),
              WeeklyReportFailed() => const _LoadError(),
              _ => const _Message('Loading report'),
            };
          },
        ),
        const SizedBox(height: HxSpace.x6),
      ],
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.record, required this.week});

  final WeeklyReportRecord record;
  final IsoWeek week;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WeeklyReportPayload payload;
    try {
      payload = WeeklyReportPayload.fromJsonString(record.payloadJson);
    } catch (_) {
      return const _LoadError();
    }

    final clock = ref.watch(clockProvider);
    final now = clock.now();
    final isCurrentWeek = week == IsoWeek.fromDate(now);
    final tdee = payload.tdee;
    final narrative = narrativeStatusFor(
      record: record,
      payload: payload,
      ui: ref.watch(narrativeUiStateProvider(week)),
      now: now,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isCurrentWeek) ...[
          Text(
            'Snapshot from ${_snapshotFormat.format(record.generatedAt)}',
            style: ReportText.label(context),
          ),
          const SizedBox(height: HxSpace.x4),
        ],
        NutritionSectionCard(section: payload.nutrition),
        const SizedBox(height: HxSpace.x6),
        TrainingSectionCard(section: payload.training),
        const SizedBox(height: HxSpace.x6),
        RecoverySectionCard(section: payload.recovery),
        const SizedBox(height: HxSpace.x6),
        PhysiqueSectionCard(section: payload.physique),
        if (tdee != null && tdee.material) ...[
          const SizedBox(height: HxSpace.x6),
          TdeeShiftCard(record: record, section: tdee),
        ],
        // Measured part ends here; the interpreted part is visibly separate.
        if (narrative != null) ...[
          const SizedBox(height: HxSpace.x8),
          AiNarrativeCard(
            status: narrative.status,
            narrative: narrative.narrative,
            retryEnabled: narrative.retryEnabled,
            onRetry: () => unawaited(
              ref.read(weeklyReportControllerProvider).retryNarrative(week),
            ),
          ),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HxSpace.x4),
      child: Text(text, style: ReportText.label(context)),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError();

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HxSpace.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: hx.danger),
          const SizedBox(width: HxSpace.x3),
          Expanded(
            child: Text(
              "Couldn't load this report. Go back and open it again.",
              style: ReportText.body(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoDataState extends StatelessWidget {
  const _NoDataState();

  @override
  Widget build(BuildContext context) {
    return HxCard(
      child: Text('No data this week', style: ReportText.label(context)),
    );
  }
}

class _TurnOnState extends StatelessWidget {
  const _TurnOnState();

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return HxCard(
      onTap: () => context.push(AppRoutes.notifications),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(
              Icons.notifications_none,
              size: 20,
              color: hx.onSurfaceVariant,
            ),
            const SizedBox(width: HxSpace.x3),
            Expanded(
              child: Text(
                'Turn on weekly report',
                style: ReportText.body(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right, color: hx.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

final DateFormat _dayFormat = DateFormat('EEE d MMM');
final DateFormat _snapshotFormat = DateFormat('d MMM yyyy');

/// "Mon 28 Sep – Sun 4 Oct" (Monday to Sunday of [week]).
String _rangeLabel(IsoWeek week) {
  final start = week.start;
  final sunday = DateTime(start.year, start.month, start.day + 6);
  return '${_dayFormat.format(start)} – ${_dayFormat.format(sunday)}';
}
