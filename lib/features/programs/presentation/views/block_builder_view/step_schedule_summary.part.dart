part of '../block_builder_view.dart';

mixin _StepScheduleSummaryMixin on _BuilderStateBase {
  Widget _stepSchedule(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(theme, 'Schedule', 'When does week 1 begin?'),
        _radioCard(
          theme,
          title: DateFormat('EEEE, MMMM d, yyyy').format(_startDate),
          subtitle: 'Start date',
          selected: true,
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _startDate,
              firstDate: _BuilderStateBase._today().subtract(
                const Duration(days: 30),
              ),
              lastDate: _BuilderStateBase._today().add(
                const Duration(days: 365),
              ),
            );
            if (picked != null) setState(() => _startDate = picked);
          },
        ),
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Default start time (optional)'),
        _radioCard(
          theme,
          title: _defaultStartTime == null
              ? 'No particular time'
              : _defaultStartTime!.format(context),
          subtitle: 'Applied to every session; edit any one later',
          selected: true,
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime:
                  _defaultStartTime ?? const TimeOfDay(hour: 7, minute: 0),
            );
            if (picked != null) setState(() => _defaultStartTime = picked);
          },
          trailing: _defaultStartTime == null
              ? null
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, color: AppColors.secondary),
                  onPressed: () => setState(() => _defaultStartTime = null),
                ),
        ),
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Planned break (optional)'),
        GlassContainer(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.beach_access, color: AppColors.primary, size: 34),
              const SizedBox(height: 12),
              Text(
                'Sessions in this range are marked skipped instead of missed.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 18),
              PremiumButton(
                text: _vacation == null
                    ? 'Select trip dates'
                    : '${DateFormat('MMM d').format(_vacation!.start)} – '
                          '${DateFormat('MMM d').format(_vacation!.end)}',
                isPrimary: false,
                icon: Icons.date_range,
                onTap: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: _startDate,
                    lastDate: _startDate.add(const Duration(days: 365)),
                  );
                  if (range != null) setState(() => _vacation = range);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _summaryCard(theme),
      ],
    );
  }

  Widget _summaryCard(ThemeData theme) {
    final plan = _plan;
    final linked = plan.slotSummary
        .where((s) => _templatesBySlot[s.slotIndex] != null)
        .length;
    final total = plan.slotSummary.length;
    final completeByPlanner = _buildMode != ProgramBuildMode.manual;
    final contentComplete = completeByPlanner || linked == total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _effectiveName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_split.label} · $_weeks weeks · '
            '${plan.trainingDayCount} sessions per '
            '${_mode == ScheduleMode.weekly ? 'week' : 'cycle'} · '
            '${_model.label} · ${_goal.label} · ${_experience.label}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                contentComplete
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                size: 16,
                color: contentComplete ? AppColors.primary : AppColors.tertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  completeByPlanner
                      ? 'All unlinked days will be generated with exercises, sets, targets and rotations.'
                      : linked == total
                      ? 'All $total days have a template.'
                      : '$linked of $total days have a template — the rest '
                            'start empty.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: contentComplete
                        ? AppColors.primary
                        : AppColors.tertiary,
                  ),
                ),
              ),
            ],
          ),
          if (linked > 0) ...[
            const SizedBox(height: 16),
            FutureBuilder<ProgramVolumeBreakdown>(
              future: ProgramVolumeCalculator.computeFromTemplates(
                db: ref.read(appDatabaseProvider),
                templatesBySlot: _templatesBySlot,
                plan: plan,
                weeks: _weeks,
                model: _model,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  return ProgramMuscleVolumeCard(
                    breakdown: snapshot.data!,
                    title: 'Estimated Volume per Muscle Group',
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ],
      ),
    );
  }

  // ── Shared bits ────────────────────────────────────────────────────────────
}
