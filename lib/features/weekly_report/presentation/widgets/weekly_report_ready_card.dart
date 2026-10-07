import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_providers.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/section_card_scaffold.dart';

/// Dashboard banner shown only while a weekly report is ready and unread
/// (D-09). It is deliberately not a configurable dashboard widget, so saved dashboard
/// layouts are untouched. It shows no health values, only the week number.
///
/// The bottom gap is part of the card, so nothing is left behind when it is
/// hidden.
class WeeklyReportReadyCard extends ConsumerWidget {
  const WeeklyReportReadyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(weeklyReportReadyProvider);
    if (week == null) return const SizedBox.shrink();
    final hx = context.hx;
    return Padding(
      padding: const EdgeInsets.only(bottom: HxSpace.x6),
      child: HxCard(
        accent: hx.primary,
        onTap: () =>
            context.push(AppPaths.weeklyReport(week.isoYear, week.isoWeek)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(Icons.insights, size: 24, color: hx.primaryText),
              const SizedBox(width: HxSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your week ${week.isoWeek} report is ready',
                      style: ReportText.body(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Tap to open',
                      style: ReportText.label(
                        context,
                      ).copyWith(color: hx.primaryText),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: hx.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
