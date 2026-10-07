part of '../block_builder_view.dart';

mixin _StepMethodsMixin on _BuilderStateBase {
  Widget _stepContentAndMethods(ThemeData theme) {
    final slots = _plan.slotSummary;
    final templates = ref.watch(workoutTemplatesProvider(-1)).value ?? const [];
    const methods = [
      SlotTrainingMethod.auto,
      SlotTrainingMethod.straightSets,
      SlotTrainingMethod.doubleProgression,
      SlotTrainingMethod.topSetBackoff,
      SlotTrainingMethod.maxEffort,
      SlotTrainingMethod.dynamicEffort,
    ];
    final maxEffortCount = _mainMethodByDayLabel.values
        .where((method) => method == SlotTrainingMethod.maxEffort)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        _programRhythmCard(theme),
        const SizedBox(height: 20),
        _sectionLabel(theme, 'Main exercise method'),
        const SizedBox(height: 10),
        for (final slot in _plan.slotSummary)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: .4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '${slot.label} · main exercise',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final method in methods)
                      _choiceChip(
                        label: method.label,
                        selected:
                            (_mainMethodByDayLabel[slot.label] ??
                                SlotTrainingMethod.auto) ==
                            method,
                        onTap: () => setState(() {
                          if (method == SlotTrainingMethod.auto) {
                            _mainMethodByDayLabel.remove(slot.label);
                          } else {
                            _mainMethodByDayLabel[slot.label] = method;
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ),
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

  Widget _programRhythmCard(ThemeData theme) {
    final canSetWave =
        _model != PeriodizationModel.block &&
        _model != PeriodizationModel.maxEffort;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Program rhythm',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_model == PeriodizationModel.concurrent) ...[
            const SizedBox(height: 16),
            Text(
              'Concurrent day structure',
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
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final slot in _plan.slotSummary)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
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
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Keep your percentages steady, or have one selected group take the heavy focus each week while the others ease back.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
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
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Text(
            'Exercise rotation',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            canSetWave
                ? 'Choose this only if you want a fixed rotation. Otherwise Herculex uses the model’s default and shows every change in the review calendar.'
                : _model == PeriodizationModel.maxEffort
                ? 'Westside (Conjugate) rotates its main lift as part of the method; it is not a separate wave setting.'
                : 'Block phases determine when lifts change, so a fixed rotation would conflict with the plan.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          if (canSetWave) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _choiceChip(
                  label: 'Auto',
                  selected: _waveOverrideWeeks == null,
                  onTap: () => setState(() => _waveOverrideWeeks = null),
                ),
                for (final weeks in const [2, 3, 4])
                  _choiceChip(
                    label: 'Every $weeks weeks',
                    selected: _waveOverrideWeeks == weeks,
                    onTap: () => setState(() => _waveOverrideWeeks = weeks),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _rotationPreview,
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
    if (_waveOverrideWeeks == null) {
      return 'Review will list the exact lift and its replacement for every week.';
    }
    final changes = <String>[];
    for (var week = 1; week <= _weeks; week += _waveOverrideWeeks!) {
      final end = (week + _waveOverrideWeeks! - 1).clamp(week, _weeks);
      changes.add('W$week–$end');
    }
    return 'The selected exercises stay for ${changes.join(', ')}; the next window uses the next suitable variation.';
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
