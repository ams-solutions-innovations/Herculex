import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/section_card_scaffold.dart';

/// Analytics entry to the weekly report history (D-09).
class WeeklyReportsEntryCard extends StatelessWidget {
  const WeeklyReportsEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    return HxCard(
      onTap: () => context.push(AppRoutes.weeklyReports),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(Icons.insights_outlined, size: 20, color: hx.onSurface),
            const SizedBox(width: HxSpace.x3),
            Expanded(
              child: Text(
                'Weekly reports',
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
