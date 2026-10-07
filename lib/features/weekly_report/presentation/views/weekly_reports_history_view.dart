import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_payload.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/section_card_scaffold.dart';
import 'package:intl/intl.dart';

/// Past weekly reports, newest first (D-09, RPT-04).
///
/// Stays visible when the opt-in is off (D-07): a banner then offers to turn it
/// on, but only by opening notification settings, where the processing
/// disclosure lives. Reads providers only, never the database.
class WeeklyReportsHistoryView extends ConsumerWidget {
  const WeeklyReportsHistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(weeklyReportHistoryProvider);
    final enabled = ref.watch(weeklyReportEnabledProvider);

    return HxScreenShell(
      title: 'Weekly reports',
      children: [
        if (!enabled) ...[
          const _TurnOnBanner(),
          const SizedBox(height: HxSpace.x4),
        ],
        history.when(
          loading: () => const _Message('Loading weekly reports'),
          error: (_, _) => const _Message("Couldn't load your weekly reports."),
          data: (records) {
            if (records.isEmpty) return _EmptyState(enabled: enabled);
            final sorted = [...records]
              ..sort((a, b) => b.week.compareTo(a.week));
            return Column(
              children: [
                for (final record in sorted) ...[
                  _ReportRow(record: record),
                  const SizedBox(height: HxSpace.x2),
                ],
              ],
            );
          },
        ),
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

class _TurnOnBanner extends StatelessWidget {
  const _TurnOnBanner();

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

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HxSpace.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No weekly reports yet', style: ReportText.heading(context)),
          const SizedBox(height: HxSpace.x2),
          Text(
            "Turn on Weekly report in notification settings. Your first report appears on Sunday, or open this week's now.",
            style: ReportText.body(context),
          ),
          if (enabled) ...[
            const SizedBox(height: HxSpace.x4),
            SizedBox(
              height: 48,
              child: PremiumButton(
                text: "Open this week's report",
                onTap: () {
                  final week = IsoWeek.fromDate(ref.read(clockProvider).now());
                  context.push(
                    AppPaths.weeklyReport(week.isoYear, week.isoWeek),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.record});

  final WeeklyReportRecord record;

  /// Whether the narrative is still owed: none stored, and the payload has
  /// something for the AI to interpret. An undecodable payload shows no pill.
  bool get _narrativePending {
    if (record.narrativeJson != null) return false;
    final payload = WeeklyReportPayload.tryDecode(record.payloadJson);
    return payload != null && payload.hasNarrativeSignal;
  }

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final week = record.week;
    final unread = record.viewedAt == null;
    return HxCard(
      onTap: () =>
          context.push(AppPaths.weeklyReport(week.isoYear, week.isoWeek)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Week ${week.isoWeek}',
                    style: ReportText.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(_rangeLabel(week), style: ReportText.label(context)),
                ],
              ),
            ),
            if (_narrativePending) ...[
              const HxTextPill(label: 'Narrative pending'),
              const SizedBox(width: HxSpace.x2),
            ],
            if (unread) ...[
              Semantics(
                label: 'Unread',
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: hx.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: HxSpace.x2),
            ],
            Icon(Icons.chevron_right, color: hx.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

final DateFormat _dayFormat = DateFormat('EEE d MMM');

/// "Mon 28 Sep – Sun 4 Oct" (Monday to Sunday of [week]).
String _rangeLabel(IsoWeek week) {
  final start = week.start;
  final sunday = DateTime(start.year, start.month, start.day + 6);
  return '${_dayFormat.format(start)} – ${_dayFormat.format(sunday)}';
}
