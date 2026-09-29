part of '../block_builder_view.dart';

mixin _StepParametersMixin on _BuilderStateBase {
  Widget _stepParameters(ThemeData theme) {
    final dreamPrioritiesActive =
        _dreamPhysiquePriorities.isNotEmpty && !_useManualMusclePlan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          theme,
          'Training parameters',
          'Tune the core rules that guide your progression and schedule.',
        ),
        if (dreamPrioritiesActive) _dreamPhysiqueAutoFillBanner(theme),
        _sectionLabel(theme, 'Primary goal'),
        _pickerTile(
          theme,
          key: const ValueKey('picker-goal'),
          icon: switch (_goal) {
            TrainingGoal.hypertrophy => Icons.fitness_center_rounded,
            TrainingGoal.strength => Icons.bolt_rounded,
            TrainingGoal.powerbuilding => Icons.whatshot_rounded,
            TrainingGoal.athletic => Icons.speed_rounded,
          },
          label: 'Primary goal',
          value: _goal.label,
          subtitle: switch (_goal) {
            TrainingGoal.hypertrophy =>
              'Maximize muscle mass, symmetry, and muscle fullness.',
            TrainingGoal.strength =>
              'Focus on compound lift force production and neural adaptations.',
            TrainingGoal.powerbuilding =>
              'Heavy compound lifts combined with hypertrophy accessories.',
            TrainingGoal.athletic =>
              'Power, movement capacity, core stability, and balance.',
          },
          onTap: () => _showGoalPicker(theme),
        ),
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Training style'),
        _pickerTile(
          theme,
          key: const ValueKey('picker-style'),
          icon: switch (_trainingStyle) {
            TrainingStyle.weightlifting => Icons.fitness_center_rounded,
            TrainingStyle.calisthenics => Icons.accessibility_new_rounded,
            TrainingStyle.mixedCalisthenicsWeights => Icons.layers_rounded,
            TrainingStyle.basic => Icons.home_work_outlined,
            TrainingStyle.crossfit => Icons.timer_outlined,
            TrainingStyle.fullBody2xGpp => Icons.all_inclusive_rounded,
          },
          label: 'Training style',
          value: _trainingStyle.label,
          subtitle: _trainingStyleDescription,
          onTap: () => _showTrainingStylePicker(theme),
        ),
        if (_trainingStyle == TrainingStyle.fullBody2xGpp) ...[
          const SizedBox(height: 10),
          _settingToggleTile(
            theme,
            icon: Icons.sports_gymnastics_rounded,
            title: 'Include GPP conditioning',
            value: _includeGppConditioning,
            onInfoTap: () => _showInfoDialog(
              theme,
              title: 'GPP Conditioning',
              icon: Icons.sports_gymnastics_rounded,
              body:
                  'Adds a dedicated conditioning session alongside two full-body strength sessions. Turn off for Full Body A/B only.',
            ),
            onChanged: (value) => setState(() {
              _includeGppConditioning = value;
              _split = value ? SplitType.fullBodyAbGpp : SplitType.fullBodyAb;
              _daysPerWeek = value ? 3 : 2;
              _clearCustomWeeklyPlacement();
            }),
          ),
        ],
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Time per workout'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Target workout time',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '$_workoutDurationMinutes min',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Slider(
                value: _workoutDurationMinutes.toDouble().clamp(30.0, 120.0),
                min: 30,
                max: 120,
                divisions: 6,
                label: '$_workoutDurationMinutes min',
                onChanged: (val) =>
                    setState(() => _workoutDurationMinutes = val.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '30 min',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                  Text(
                    '60 min',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                  Text(
                    '90 min',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                  Text(
                    '120 min',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel(theme, 'Workout options'),
        _settingToggleTile(
          theme,
          icon: Icons.local_fire_department_rounded,
          title: 'Auto warm-up sets',
          value: _includeAutomaticWarmups,
          onInfoTap: () => _showInfoDialog(
            theme,
            title: 'Auto Warm-up Sets',
            icon: Icons.local_fire_department_rounded,
            body:
                'Automatically calculates ramp-up warmup sets for compound free-weight exercises to prepare your muscles and nervous system safely.',
          ),
          onChanged: (value) =>
              setState(() => _includeAutomaticWarmups = value),
        ),
        _settingToggleTile(
          theme,
          icon: Icons.bolt_rounded,
          title: 'Time-saving sets',
          value: _allowTimeSavingSetTechniques,
          onInfoTap: () => _showInfoDialog(
            theme,
            title: 'Time-saving Sets',
            icon: Icons.bolt_rounded,
            body:
                'Uses density techniques such as Myo-reps exclusively on safe isolation exercises to significantly shorten session duration.',
          ),
          onChanged: (value) =>
              setState(() => _allowTimeSavingSetTechniques = value),
        ),
        _settingToggleTile(
          theme,
          key: const ValueKey('specialization-switch'),
          icon: Icons.track_changes_rounded,
          title: 'Primary lift specialization',
          tooltip: 'Specialization info',
          value: _useLiftSpecialization,
          onInfoTap: () => _showSpecializationInfoDialog(theme),
          onChanged: (value) async {
            if (value) {
              final configured = await _showSpecializationModal(theme);
              if (!configured &&
                  (_currentSquatKg == null || _currentSquatKg! <= 0)) {
                if (mounted) setState(() => _useLiftSpecialization = false);
              }
            } else {
              setState(() => _useLiftSpecialization = false);
            }
          },
        ),
        if (_useLiftSpecialization) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: .35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_specializationLift.label} Specialization',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _showSpecializationModal(theme),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Current: ${_currentSquatCtrl.text.isEmpty ? "Not set" : "${_currentSquatCtrl.text} kg"} → Target: ${_targetSquatCtrl.text} kg',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_liftStickingPoint != PrimaryLiftStickingPoint.unknown) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Sticking point: ${_liftStickingPoint.label}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '$_liftRecommendedWeeks weeks · 3 exposures / week',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Training experience'),
        _pickerTile(
          theme,
          key: const ValueKey('picker-experience'),
          icon: switch (_experience) {
            ExperienceLevel.novice => Icons.school_rounded,
            ExperienceLevel.intermediate => Icons.trending_up_rounded,
            ExperienceLevel.advanced => Icons.military_tech_rounded,
          },
          label: 'Training experience',
          value: _experience.label,
          badge: _experienceRecommendation?.level == _experience
              ? 'Recommended'
              : null,
          subtitle: switch (_experience) {
            ExperienceLevel.novice =>
              'Building consistency and progressing session to session.',
            ExperienceLevel.intermediate =>
              'Needs planned progression, fatigue control and exercise waves.',
            ExperienceLevel.advanced =>
              'Experienced with RIR/RPE and structured training blocks.',
          },
          onTap: () => _showExperiencePicker(theme),
        ),
        if (_experienceRecommendation != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${(_experienceRecommendation!.confidence * 100).round()}% confidence · ${_experienceRecommendation!.reason}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Block name'),
        PremiumTextField(controller: _nameCtrl, hintText: _effectiveName),
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Length'),
        _pickerTile(
          theme,
          key: const ValueKey('picker-length'),
          icon: Icons.calendar_today_rounded,
          label: 'Block length',
          value: '$_weeks weeks',
          subtitle: switch (_weeks) {
            4 =>
              'Short micro-block, ideal for a quick strength peak or technique focus.',
            6 => 'Standard introductory or short specialization block.',
            8 =>
              'Optimal balance of progressive overload, adaptation, and deload.',
            12 =>
              'Full progressive macro-cycle across distinct training phases.',
            16 =>
              'Extended progression cycle for disciplined long-term adaptations.',
            24 =>
              'Half-year continuous block with multiple scheduled deload waves.',
            _ => '$_weeks weeks training block.',
          },
          onTap: () => _showLengthPicker(theme),
        ),
        const SizedBox(height: 24),
        _sectionLabel(theme, 'Periodization'),
        for (final model in PeriodizationModel.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _radioCard(
              theme,
              title: model.label,
              subtitle: _modelDescriptions[model]!,
              selected: _model == model,
              recommended: model == _recommendedPeriodizationModel,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (model == _recommendedPeriodizationModel)
                    const _RecommendedPill(),
                  IconButton(
                    icon: const Icon(Icons.help_outline_rounded),
                    tooltip: 'How ${model.label} is programmed',
                    onPressed: () =>
                        ProgramMethodGuideView.show(context, model),
                  ),
                ],
              ),
              onTap: () => setState(() => _model = model),
            ),
          ),
      ],
    );
  }

  static const _modelDescriptions = {
    PeriodizationModel.none:
        'Flat load across all weeks. You control progression manually.',
    PeriodizationModel.linear:
        'Intensity rises ~2.5%/week; volume tapers. Deload every 4th week.',
    PeriodizationModel.concurrent:
        'All qualities trained together on a heavy/medium/light wave.',
    PeriodizationModel.block:
        'Accumulation → Transmutation → Realization, peaking to high intensity.',
    PeriodizationModel.maxEffort:
        'Westside-style: work up to a safe 1–3 rep top set; rotate the lift.',
  };

  PeriodizationModel get _recommendedPeriodizationModel =>
      switch ((_goal, _experience)) {
        (TrainingGoal.strength, ExperienceLevel.advanced) =>
          PeriodizationModel.block,
        (TrainingGoal.strength, _) => PeriodizationModel.linear,
        (TrainingGoal.powerbuilding, _) => PeriodizationModel.concurrent,
        (TrainingGoal.athletic, _) => PeriodizationModel.concurrent,
        _ => PeriodizationModel.linear,
      };

  // ── Step 2: split ──────────────────────────────────────────────────────────
}
