part of '../block_builder_view.dart';

mixin _StepModeAndSplitMixin on _BuilderStateBase {
  Widget _stepBuildModeAndPriorities(ThemeData theme) {
    final dreamPrioritiesSaved = _dreamPhysiquePriorities.isNotEmpty;
    final dreamPrioritiesActive = dreamPrioritiesSaved && !_useManualMusclePlan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          theme,
          'How do you want to build?',
          'Every path uses the same safe programming engine.',
        ),
        for (final mode in ProgramBuildMode.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _radioCard(
              theme,
              title: mode.label,
              subtitle: switch (mode) {
                ProgramBuildMode.smart =>
                  'Answer the essentials; Herculex builds the complete block.',
                ProgramBuildMode.guided =>
                  'Start with recommendations, then tune every important choice.',
                ProgramBuildMode.manual =>
                  'Create the structure yourself with no automatic exercise selection.',
                ProgramBuildMode.herculexAi =>
                  'Herculex AI drafts a design brief — split, periodization and day '
                      'focus — grounded in your goals. You review and confirm every choice.',
              },
              selected: _buildMode == mode,
              onTap: () => setState(() => _buildMode = mode),
            ),
          ),
        if (_buildMode != ProgramBuildMode.manual) ...[
          const SizedBox(height: 24),
          _sectionLabel(theme, 'Muscle priority'),
          const SizedBox(height: 6),
          _builderInputCard(
            theme,
            icon: Icons.auto_awesome_rounded,
            title: 'Dream Physique priorities',
            subtitle: !dreamPrioritiesSaved
                ? 'AI-recommended muscle priorities based on photos.'
                : dreamPrioritiesActive
                ? 'AI-analyzed priorities applied to program volume.'
                : 'Saved Dream Physique priorities ready to use.',
            selected: dreamPrioritiesActive,
            status: !dreamPrioritiesSaved
                ? null
                : dreamPrioritiesActive
                ? 'Active'
                : 'Inactive',
            onCardTap: () {
              if (dreamPrioritiesSaved) {
                setState(() {
                  _useManualMusclePlan = false;
                  _applyDreamPhysiqueTuning();
                  _dreamPhysiqueTuned = true;
                });
              } else {
                context
                    .push(AppRoutes.dreamPhysique)
                    .then((_) => _loadDreamPhysiquePriorities());
              }
            },
            actionWidget: dreamPrioritiesSaved
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          setState(() {
                            _useManualMusclePlan = false;
                            _applyDreamPhysiqueTuning();
                            _dreamPhysiqueTuned = true;
                          });
                          await context.push(AppRoutes.dreamPhysiquePriorities);
                          await _loadDreamPhysiquePriorities();
                        },
                        icon: const Icon(Icons.check_circle_rounded, size: 16),
                        label: const Text('Goals set'),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await context.push(AppRoutes.dreamPhysique);
                          await _loadDreamPhysiquePriorities();
                        },
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: const Text('Set new goal'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  )
                : OutlinedButton(
                    onPressed: () async {
                      await context.push(AppRoutes.dreamPhysique);
                      await _loadDreamPhysiquePriorities();
                    },
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Set priorities'),
                  ),
          ),
          _builderInputCard(
            theme,
            icon: Icons.tune_rounded,
            title: 'Muscle priorities & weekly sets',
            subtitle: _useManualMusclePlan
                ? (_manualMuscleWeights.isNotEmpty
                      ? _manualPlanSummary
                      : 'Custom focus percentages & set caps.')
                : 'Custom focus percentages & set caps.',
            selected: _useManualMusclePlan,
            status: _useManualMusclePlan ? 'Active' : null,
            onCardTap: () {
              if (!_useManualMusclePlan) {
                if (_manualMuscleWeights.isNotEmpty) {
                  setState(() => _useManualMusclePlan = true);
                } else {
                  _showManualMusclePlan();
                }
              } else {
                _showManualMusclePlan();
              }
            },
            action: _useManualMusclePlan ? 'Edit' : 'Set myself',
            onTap: _showManualMusclePlan,
          ),
        ],
      ],
    );
  }

  // ── Step 3: training parameters ────────────────────────────────────────────

  Widget _stepSplit(ThemeData theme) {
    final plan = _plan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(theme, 'Split', 'Choose weekly or cycling rhythm.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in SplitType.values)
              _choiceChip(
                label: type.label,
                selected: _split == type,
                onTap: () => setState(() {
                  _split = type;
                  _daysPerWeek = type.defaultDaysPerWeek;
                  _weeklyDayLabels.clear();
                  _weeklyTrainingWeekdays.clear();
                  _hasCustomWeeklyPlacement = false;
                  _templatesBySlot.clear();
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionLabel(
          theme,
          _mode == ScheduleMode.weekly
              ? 'Training days per week'
              : 'Training days per cycle',
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded),
              onPressed: _daysPerWeek <= 1
                  ? null
                  : () => setState(() {
                      _daysPerWeek--;
                      _clearCustomWeeklyPlacement();
                      _templatesBySlot.clear();
                    }),
            ),
            Expanded(
              child: Text(
                '$_daysPerWeek',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: _daysPerWeek >= (_mode == ScheduleMode.weekly ? 7 : 10)
                  ? null
                  : () => setState(() {
                      _daysPerWeek++;
                      _clearCustomWeeklyPlacement();
                      if (_cycleLength <= _daysPerWeek) {
                        _cycleLength = _daysPerWeek + 1;
                      }
                      _templatesBySlot.clear();
                    }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionLabel(theme, 'Repeat'),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 144,
                child: _radioCard(
                  theme,
                  title: 'Weekly',
                  subtitle: 'Fixed weekdays, repeating every 7 days.',
                  selected: _mode == ScheduleMode.weekly,
                  onTap: () => setState(() => _mode = ScheduleMode.weekly),
                  centered: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 144,
                child: _radioCard(
                  theme,
                  title: 'Cycle',
                  subtitle: 'N-on / N-off, drifting across the calendar.',
                  selected: _mode == ScheduleMode.cycle,
                  onTap: () => setState(() {
                    _mode = ScheduleMode.cycle;
                    if (_cycleLength <= _daysPerWeek) {
                      _cycleLength = _daysPerWeek + 1;
                    }
                  }),
                  centered: true,
                ),
              ),
            ),
          ],
        ),
        if (_mode == ScheduleMode.cycle) ...[
          const SizedBox(height: 16),
          _sectionLabel(theme, 'Cycle length'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var len = _daysPerWeek; len <= _daysPerWeek + 4; len++)
                if (len >= 1)
                  _choiceChip(
                    label: '$len days',
                    selected: _cycleLength == len,
                    onTap: () => setState(() => _cycleLength = len),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_daysPerWeek on, ${_cycleLength - _daysPerWeek} off — repeating '
            'every $_cycleLength days regardless of the weekday.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
        ],
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Preview'),
        const SizedBox(height: 6),
        _planPreview(theme, plan),
        if (_recoveryWarnings(plan).isNotEmpty) ...[
          const SizedBox(height: 12),
          _recoveryWarning(theme, _recoveryWarnings(plan)),
        ],
      ],
    );
  }

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
              )
          else
            for (final day in plan.days)
              _previewRow(
                theme,
                'Day ${day.index + 1}',
                day.isRest ? '' : day.label,
              ),
        ],
      ),
    );
  }

  Widget _previewRow(
    ThemeData theme,
    String slot,
    String label, {
    VoidCallback? onTap,
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
            Expanded(
              child: Text(
                isRest ? 'Rest' : label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isRest ? FontWeight.w400 : FontWeight.w600,
                  color: isRest ? AppColors.outlineVariant : null,
                ),
              ),
            ),
            if (onTap != null)
              Icon(Icons.edit_outlined, size: 17, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  @override
  void _clearCustomWeeklyPlacement() {
    _weeklyDayLabels.clear();
    _weeklyTrainingWeekdays.clear();
    _hasCustomWeeklyPlacement = false;
  }

  Future<void> _editWeeklyDay(int weekday) async {
    final options = _split.slots.isEmpty
        ? _plan.slotSummary.map((slot) => slot.label).toList()
        : _split.slots;
    if (options.isEmpty) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose workout split',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final label in options)
                ListTile(
                  title: Text(label),
                  trailing:
                      (_weeklyDayLabels[weekday] == label ||
                          (_weeklyDayLabels[weekday] == null &&
                              _plan.days.any(
                                (day) =>
                                    day.dayOfWeek == weekday &&
                                    day.label == label,
                              )))
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, label),
                ),
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('Rest day'),
                onTap: () => Navigator.pop(context, '__rest__'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        if (!_hasCustomWeeklyPlacement) {
          _weeklyTrainingWeekdays
            ..clear()
            ..addAll(_plan.trainingDays.map((day) => day.dayOfWeek));
          _hasCustomWeeklyPlacement = true;
        }
        if (selected == '__rest__') {
          _weeklyTrainingWeekdays.remove(weekday);
          _weeklyDayLabels.remove(weekday);
        } else {
          _weeklyTrainingWeekdays.add(weekday);
          _weeklyDayLabels[weekday] = selected;
        }
        _templatesBySlot.clear();
      });
    }
  }

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

  // ── Step 2: exercise pools ─────────────────────────────────────────────────
}
