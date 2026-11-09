part of '../block_builder_view.dart';

mixin _StepMethodsMixin on _BuilderStateBase {
  Widget _stepContentAndMethods(ThemeData theme) {
    final slots = _plan.slotSummary;
    final templates = ref.watch(workoutTemplatesProvider(-1)).value ?? const [];
    final maxEffortCount = _mainMethodByDayLabel.values
        .where((method) => method == SlotTrainingMethod.maxEffort)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(
          theme,
          'Workout content & methods',
          'Templates and exercise methods.',
          centered: true,
        ),
        _sectionLabel(theme, 'Workout templates'),
        const SizedBox(height: 10),
        for (final slot in slots)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _slotCard(theme, slot, templates),
          ),
        const SizedBox(height: 20),
        _programFocusCard(theme),
        const SizedBox(height: 20),
        _programRhythmCard(theme),
        const SizedBox(height: 20),
        _sectionLabel(theme, 'Main exercise method'),
        const SizedBox(height: 10),
        for (final slot in _plan.slotSummary)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _mainMethodTile(theme, slot.label),
          ),
        if (maxEffortCount > 0)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.tertiary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.tertiary.withValues(alpha: .35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: AppColors.tertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _experience == ExperienceLevel.novice
                        ? 'Max Effort is not recommended at novice level. Herculex will still enforce one lift per workout, RPE 8.5–9.5 and a safe rotation pool.'
                        : '$maxEffortCount Max Effort pattern${maxEffortCount == 1 ? '' : 's'} selected. Smart programs allow at most two per week and require three suitable variations.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static const _pickableMethods = [
    SlotTrainingMethod.auto,
    SlotTrainingMethod.straightSets,
    SlotTrainingMethod.doubleProgression,
    SlotTrainingMethod.topSetBackoff,
    SlotTrainingMethod.pyramidUp,
    SlotTrainingMethod.reversePyramid,
    SlotTrainingMethod.maxEffort,
    SlotTrainingMethod.dynamicEffort,
  ];

  static IconData _methodIcon(SlotTrainingMethod method) => switch (method) {
    SlotTrainingMethod.pyramidUp => Icons.trending_up_rounded,
    SlotTrainingMethod.reversePyramid ||
    SlotTrainingMethod.topSetBackoff ||
    SlotTrainingMethod.maxEffort => Icons.trending_down_rounded,
    SlotTrainingMethod.dynamicEffort => Icons.bolt_rounded,
    SlotTrainingMethod.auto => Icons.auto_awesome_rounded,
    _ => Icons.fitness_center_rounded,
  };

  Widget _mainMethodTile(ThemeData theme, String dayLabel) {
    final method = _mainMethodByDayLabel[dayLabel] ?? SlotTrainingMethod.auto;
    final followsFocus =
        method == SlotTrainingMethod.auto &&
        _effectiveTrainingFocus == TrainingFocus.intensity;
    return _pickerTile(
      theme,
      key: ValueKey('main-method-$dayLabel'),
      icon: _methodIcon(method),
      label: dayLabel,
      value: followsFocus
          ? SlotTrainingMethod.intensityFocus.label
          : method.label,
      subtitle: followsFocus
          ? SlotTrainingMethod.intensityFocus.description
          : method.description,
      onTap: () => _showMainMethodPicker(theme, dayLabel),
    );
  }

  void _showMainMethodPicker(ThemeData theme, String dayLabel) {
    HxSheet.show(
      context,
      builder: (sheetContext) => HxSheet(
        scrollable: true,
        initialSize: 0.75,
        maxSize: 0.9,
        title: '$dayLabel · main exercise',
        subtitle: 'How the first lift of this day is structured.',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final method in _pickableMethods)
              _sheetOptionCard<SlotTrainingMethod>(
                sheetContext: sheetContext,
                theme: theme,
                item: method,
                selectedItem:
                    _mainMethodByDayLabel[dayLabel] ?? SlotTrainingMethod.auto,
                title: method.label,
                subtitle: method.description,
                icon: _methodIcon(method),
                onSelected: (selected) => setState(() {
                  if (selected == SlotTrainingMethod.auto) {
                    _mainMethodByDayLabel.remove(dayLabel);
                  } else {
                    _mainMethodByDayLabel[dayLabel] = selected;
                  }
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _programFocusCard(ThemeData theme) {
    final available = _intensityFocusAvailable;
    final reason = _experience == ExperienceLevel.novice
        ? 'Available from intermediate level. New lifters need reps in reserve while technique settles.'
        : _model == PeriodizationModel.maxEffort
        ? 'Not available with Westside, which has its own set structure.'
        : 'Not available with CrossFit, which is conditioning-first.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: .35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Program focus',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _radioCard(
            theme,
            title: TrainingFocus.balanced.label,
            subtitle: 'More sets per exercise, with reps left in reserve.',
            selected: _effectiveTrainingFocus == TrainingFocus.balanced,
            onTap: () =>
                setState(() => _trainingFocus = TrainingFocus.balanced),
          ),
          const SizedBox(height: 8),
          _radioCard(
            theme,
            title: TrainingFocus.variety.label,
            subtitle:
                'More exercise variety: accessories and isolations change '
                'every 3 weeks. Main lifts stay fixed.',
            selected: _effectiveTrainingFocus == TrainingFocus.variety,
            onTap: () => setState(() => _trainingFocus = TrainingFocus.variety),
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: available ? 1 : .55,
            child: _radioCard(
              theme,
              title: TrainingFocus.intensity.label,
              subtitle: available
                  ? SlotTrainingMethod.intensityFocus.description
                  : reason,
              selected: _effectiveTrainingFocus == TrainingFocus.intensity,
              onTap: () {
                if (!available) return;
                setState(() => _trainingFocus = TrainingFocus.intensity);
              },
            ),
          ),
          if (_acceptedHerculexBrief?.trainingPreferences
              case final preferences?) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Herculex AI understood: ${preferences.rationale}'
                '${_techniqueLimitNote(preferences) ?? ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Why a requested technique may not appear in the plan. Mirrors
  /// [TimeSavingPolicy]: its rules are the single source of truth.
  String? _techniqueLimitNote(TrainingPreferencesBrief preferences) {
    if (!preferences.usesSetTechnique) return null;
    if (_experience == ExperienceLevel.novice) {
      return ' Set techniques wait until you have more experience, so '
          'isolations stay on controlled straight sets for now.';
    }
    if (preferences.isolationTechnique == TimeSavingTechnique.forcedReps &&
        _experience != ExperienceLevel.advanced) {
      return ' Forced reps are only planned for advanced lifters, so '
          'isolations stay on straight sets.';
    }
    return ' Applied to stable isolation work only; heavy lifts keep their '
        'own progression.';
  }

  Widget _programRhythmCard(ThemeData theme) {
    final isWestside = _model == PeriodizationModel.maxEffort;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: .35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Program rhythm',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_model == PeriodizationModel.concurrent) ...[
            const SizedBox(height: 16),
            Text(
              'Concurrent day structure',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _concurrentPreset(
              theme,
              title: 'Full Body A / B',
              subtitle:
                  'A is volume; B is intensity. Both qualities remain in the same week.',
              selected: _isConcurrentPreset(const {
                'Full Body A': DayStressRole.volume,
                'Full Body B': DayStressRole.intensity,
              }),
              onTap: () => setState(() {
                _split = SplitType.fullBodyAb;
                _daysPerWeek = 2;
                _dayRoles
                  ..clear()
                  ..addAll(const {
                    'Full Body A': DayStressRole.volume,
                    'Full Body B': DayStressRole.intensity,
                  });
                _clearCustomWeeklyPlacement();
              }),
            ),
            const SizedBox(height: 8),
            _concurrentPreset(
              theme,
              title: 'Full Body A / B / C',
              subtitle: 'A is heavy, B is medium-volume, C is light/technique.',
              selected: _isConcurrentPreset(const {
                'Full Body A': DayStressRole.intensity,
                'Full Body B': DayStressRole.volume,
                'Full Body C': DayStressRole.mixed,
              }),
              onTap: () => setState(() {
                _split = SplitType.fullBody;
                _daysPerWeek = 3;
                _dayRoles
                  ..clear()
                  ..addAll(const {
                    'Full Body A': DayStressRole.intensity,
                    'Full Body B': DayStressRole.volume,
                    'Full Body C': DayStressRole.mixed,
                  });
                _clearCustomWeeklyPlacement();
              }),
            ),
            const SizedBox(height: 12),
            Text(
              'Or set the role for each day',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final slot in _plan.slotSummary)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(slot.label, style: theme.textTheme.bodySmall),
                    for (final role in [
                      DayStressRole.intensity,
                      DayStressRole.volume,
                      DayStressRole.mixed,
                      if (_model == PeriodizationModel.maxEffort)
                        DayStressRole.dynamicTechnique,
                    ])
                      _choiceChip(
                        label: role.label,
                        selected:
                            (_dayRoles[slot.label] ??
                                _defaultDayRole(slot.slotIndex)) ==
                            role,
                        onTap: () =>
                            setState(() => _dayRoles[slot.label] = role),
                      ),
                  ],
                ),
              ),
          ],
          if (_useManualMusclePlan && _manualMuscleWeights.length >= 2) ...[
            const SizedBox(height: 16),
            Text(
              'Weekly muscle focus',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Keep your percentages steady, or have one selected group take the heavy focus each week while the others ease back.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in MuscleFocusWave.values)
                  _choiceChip(
                    label: option.label,
                    selected: _muscleFocusWave == option,
                    onTap: () => setState(() => _muscleFocusWave = option),
                  ),
              ],
            ),
            if (_muscleFocusWave == MuscleFocusWave.alternating) ...[
              const SizedBox(height: 8),
              Text(
                _muscleFocusPreview,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Text(
            'Exercise rotation',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isWestside
                ? 'Westside changes its variations as part of the method. You can change the cadence or turn it off.'
                : 'Off unless you want it. Your exercises stay the same for the whole block, so progress is easy to compare.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isWestside)
                _choiceChip(
                  label: 'Westside default',
                  selected: _waveOverrideWeeks == null,
                  onTap: () => setState(() => _waveOverrideWeeks = null),
                ),
              _choiceChip(
                label: 'Off',
                selected: isWestside
                    ? _waveOverrideWeeks == 0
                    : (_waveOverrideWeeks ?? 0) == 0,
                onTap: () =>
                    setState(() => _waveOverrideWeeks = isWestside ? 0 : null),
              ),
              for (final weeks in const [2, 3, 4])
                _choiceChip(
                  label: 'Every $weeks weeks',
                  selected: _waveOverrideWeeks == weeks,
                  onTap: () => setState(() => _waveOverrideWeeks = weeks),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _rotationPreview,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  bool _isConcurrentPreset(Map<String, DayStressRole> expected) =>
      expected.entries.every((entry) => _dayRoles[entry.key] == entry.value);

  DayStressRole _defaultDayRole(int index) => switch (index % 3) {
    0 => DayStressRole.intensity,
    1 => DayStressRole.volume,
    _ => DayStressRole.mixed,
  };

  String get _rotationPreview {
    final every = _waveOverrideWeeks;
    if (every == null && _model == PeriodizationModel.maxEffort) {
      return 'Review will list every planned change. Main lifts stay fixed.';
    }
    if (every == null || every == 0) {
      return 'The same exercises for all $_weeks weeks.';
    }
    final changes = <String>[];
    for (var week = 1; week <= _weeks; week += every) {
      final end = (week + every - 1).clamp(week, _weeks);
      changes.add('W$week–$end');
    }
    return 'Exercises change at ${changes.join(', ')}. Main lifts stay fixed so progress stays comparable.';
  }

  String get _muscleFocusPreview {
    final groups = _manualMuscleWeights.keys
        .map((id) => _BuilderStateBase._manualMuscleLabels[id] ?? id)
        .toList(growable: false);
    if (groups.isEmpty) return '';
    return List<String>.generate(
      _weeks,
      (week) => 'W${week + 1}: ${groups[week % groups.length]} high focus',
    ).join('  •  ');
  }

  Widget _concurrentPreset(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) => _radioCard(
    theme,
    title: title,
    subtitle: subtitle,
    selected: selected,
    onTap: onTap,
  );

  // ── Step 5: schedule & full preview ────────────────────────────────────────
}
