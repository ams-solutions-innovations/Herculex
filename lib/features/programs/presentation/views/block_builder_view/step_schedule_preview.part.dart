part of '../block_builder_view.dart';

/// The weekly/cycle schedule preview on the split step: one row per weekday
/// (or cycle day), tagged Auto or You, plus the checks that stop an unusable
/// schedule before the user leaves the step.
mixin _StepSchedulePreviewMixin on _BuilderStateBase {
  @override
  Widget _planPreview(ThemeData theme, SplitPlan plan) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          if (plan.mode == ScheduleMode.weekly)
            for (var i = 0; i < 7; i++)
              _previewRow(
                theme,
                weekdays[i],
                plan.days
                    .where((d) => d.index == i)
                    .map((d) => d.label)
                    .join(', '),
                onTap: () => _editWeeklyDay(i + 1),
                provenance: _userSetWeekdays.contains(i + 1) ? 'You' : 'Auto',
              )
          else
            for (final day in plan.days)
              _previewRow(
                theme,
                'Day ${day.index + 1}',
                day.isRest ? '' : day.label,
                provenance: 'Auto',
              ),
        ],
      ),
    );
  }

  /// [provenance] says who decided this row: `Auto` for the app's own
  /// placement, `You` for a day the user set by hand.
  Widget _previewRow(
    ThemeData theme,
    String slot,
    String label, {
    VoidCallback? onTap,
    String? provenance,
  }) {
    final isRest = label.isEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                slot,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ),
            if (isRest)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.bedtime_outlined,
                  size: 16,
                  color: AppColors.outlineVariant,
                ),
              ),
            Expanded(
              child: Text(
                isRest ? 'Rest day' : label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isRest ? FontWeight.w400 : FontWeight.w600,
                  color: isRest ? AppColors.outlineVariant : null,
                ),
              ),
            ),
            if (provenance != null) _ProvenancePill(label: provenance),
            const SizedBox(width: 6),
            if (onTap != null)
              Icon(Icons.edit_outlined, size: 17, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  /// The first thing that would make this schedule unusable, or null.
  @override
  String? _scheduleProblem() {
    final plan = _plan;
    if (plan.mode == ScheduleMode.cycle) {
      final hasRest = plan.days.any((day) => day.isRest);
      return hasRest
          ? null
          : 'This cycle has no rest day. Make the cycle longer than the '
                'number of training days.';
    }
    if (plan.trainingDayCount != _daysPerWeek) {
      return 'Choose $_daysPerWeek training days; '
          '${plan.trainingDayCount} are currently scheduled.';
    }
    return null;
  }

  @override
  List<String> _recoveryWarnings(SplitPlan plan) {
    if (plan.mode == ScheduleMode.cycle) {
      final restDays = plan.days.where((day) => day.isRest).length;
      return restDays == 0
          ? [
              'This cycle has no planned rest day. Add recovery before creating it.',
            ]
          : const [];
    }
    final days = plan.trainingDays..sort((a, b) => a.index.compareTo(b.index));
    final warnings = <String>[];
    if (days.length != _daysPerWeek) {
      warnings.add(
        'Choose $_daysPerWeek training days; ${days.length} are currently scheduled.',
      );
    }
    if (days.length >= 6) {
      warnings.add('Six or more training days leave little room for recovery.');
    }
    for (var i = 0; i < days.length; i++) {
      final current = days[i];
      final next = days[(i + 1) % days.length];
      final gap = (next.index - current.index) % 7;
      if (gap == 1 && current.label == next.label) {
        warnings.add('${current.label} is scheduled on consecutive days.');
      }
    }
    return warnings;
  }

  @override
  Widget _recoveryWarning(ThemeData theme, List<String> warnings) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: .45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.health_and_safety_outlined, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Recovery check: ${warnings.join(' ')}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
