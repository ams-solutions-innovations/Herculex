import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:intl/intl.dart';

/// Where a template picked for a scheduled workout applies.
enum TemplateScope { thisSession, everyFuture }

/// Asks whether a template covers one scheduled occurrence or every future
/// session of its program day — the difference between a one-off swap and
/// re-pointing the live link. Shared by the day sheet and the planned
/// workout preview's Edit action.
class TemplateScopeSheet {
  const TemplateScopeSheet._();

  static Future<TemplateScope?> show(
    BuildContext context, {
    required DateTime date,
    required String dayTitle,
  }) {
    return showModalBottomSheet<TemplateScope>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => HxSheet(
        scrollable: false,
        title: 'Apply to',
        subtitle: 'This template can cover one session or all of them.',
        child: Column(
          children: [
            _ScopeOption(
              icon: Icons.today_rounded,
              title: 'This session only',
              subtitle: 'Swap just ${DateFormat('MMM d').format(date)}.',
              onTap: () =>
                  Navigator.pop(sheetContext, TemplateScope.thisSession),
            ),
            const SizedBox(height: 8),
            _ScopeOption(
              icon: Icons.repeat_rounded,
              title: 'Every future $dayTitle day',
              subtitle:
                  'Re-links the program day; past sessions are untouched.',
              onTap: () =>
                  Navigator.pop(sheetContext, TemplateScope.everyFuture),
            ),
          ],
        ),
      ),
    );
  }

  /// Asks for the scope, then links [templateId] accordingly. Returns false
  /// when the user dismissed the question.
  static Future<bool> apply(
    BuildContext context,
    WidgetRef ref, {
    required int scheduleId,
    required int programDayId,
    required int programId,
    required DateTime date,
    required String dayTitle,
    required int templateId,
  }) async {
    // Resolved before the sheet: the caller may be gone when it closes.
    final repo = ref.read(programsRepositoryProvider);
    final scope = await show(context, date: date, dayTitle: dayTitle);
    if (scope == null) return false;

    Haptics.success();
    if (scope == TemplateScope.thisSession) {
      await repo.setScheduleTemplateOverride(scheduleId, templateId);
    } else {
      await repo.setProgramDayTemplate(programDayId, templateId);
      await repo.setScheduleTemplateOverride(scheduleId, null);
      await repo.rematerializeProgram(programId);
    }
    return true;
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hx.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: hx.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hx.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
