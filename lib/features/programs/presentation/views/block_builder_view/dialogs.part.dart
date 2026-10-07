part of '../block_builder_view.dart';

mixin _DialogsMixin on _BuilderStateBase {
  @override
  Widget _dreamPhysiqueAutoFillBanner(ThemeData theme) {
    final summary = ref.watch(dreamPhysiqueSummaryProvider).valueOrNull;
    final style = summary?.targetAestheticStyle;
    final timeframe = summary?.timeframeRange;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Parameters tuned from Dream Physique',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Auto-tuned for ${style ?? "Hypertrophy"}${timeframe != null && timeframe.isNotEmpty ? " · $timeframe" : ""}. You can customize any setting.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void _showGoalPicker(ThemeData theme) {
    HxSheet.show(
      context,
      builder: (sheetContext) => HxSheet(
        scrollable: false,
        title: 'Primary Goal',
        subtitle: 'Select your primary objective for this training block',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final goal in TrainingGoal.values)
              _sheetOptionCard<TrainingGoal>(
                sheetContext: sheetContext,
                theme: theme,
                item: goal,
                selectedItem: _goal,
                title: goal.label,
                subtitle: switch (goal) {
                  TrainingGoal.hypertrophy =>
                    'Maximize muscle mass, symmetry, and muscle fullness with optimal weekly volume.',
                  TrainingGoal.strength =>
                    'Focus on compound lift force production and neuromuscular adaptation.',
                  TrainingGoal.powerbuilding =>
                    'Combines heavy main compound lifts with high-volume bodybuilding accessory work.',
                  TrainingGoal.athletic =>
                    'Blends explosive power, movement capacity, core stability, and structural balance.',
                },
                icon: switch (goal) {
                  TrainingGoal.hypertrophy => Icons.fitness_center_rounded,
                  TrainingGoal.strength => Icons.bolt_rounded,
                  TrainingGoal.powerbuilding => Icons.whatshot_rounded,
                  TrainingGoal.athletic => Icons.speed_rounded,
                },
                onSelected: (selected) {
                  setState(() {
                    _goal = selected;
                    _applySmartDefaults();
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void _showTrainingStylePicker(ThemeData theme) {
    HxSheet.show(
      context,
      builder: (sheetContext) => HxSheet(
        scrollable: true,
        initialSize: 0.75,
        maxSize: 0.9,
        title: 'Training Style',
        subtitle:
            'Exercise selection filter. You can still customize variations later.',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final style in TrainingStyle.values)
              _sheetOptionCard<TrainingStyle>(
                sheetContext: sheetContext,
                theme: theme,
                item: style,
                selectedItem: _trainingStyle,
                title: style.label,
                subtitle: switch (style) {
                  TrainingStyle.weightlifting =>
                    'Common free-weight and machine movements, matched to your experience.',
                  TrainingStyle.calisthenics =>
                    'Bodyweight-first exercise selection, with advanced skills kept out of automatic plans.',
                  TrainingStyle.mixedCalisthenicsWeights =>
                    'A balanced pool of bodyweight movements and common loaded exercises.',
                  TrainingStyle.basic =>
                    'Only common machines, dumbbells and barbells — no specialty bars or niche variations.',
                  TrainingStyle.crossfit =>
                    'High-density conditioning-first sessions with functional movement patterns.',
                  TrainingStyle.fullBody2xGpp =>
                    'Two full-body strength sessions with optional general physical-preparedness work.',
                },
                icon: switch (style) {
                  TrainingStyle.weightlifting => Icons.fitness_center_rounded,
                  TrainingStyle.calisthenics => Icons.accessibility_new_rounded,
                  TrainingStyle.mixedCalisthenicsWeights =>
                    Icons.layers_rounded,
                  TrainingStyle.basic => Icons.home_work_outlined,
                  TrainingStyle.crossfit => Icons.timer_outlined,
                  TrainingStyle.fullBody2xGpp => Icons.all_inclusive_rounded,
                },
                onSelected: (selected) {
                  setState(() {
                    _trainingStyle = selected;
                    if (selected == TrainingStyle.fullBody2xGpp) {
                      _split = SplitType.fullBodyAbGpp;
                      _daysPerWeek = 3;
                      _includeGppConditioning = true;
                      _clearCustomWeeklyPlacement();
                    } else if (selected == TrainingStyle.crossfit) {
                      _split = SplitType.crossfit;
                      _daysPerWeek = 3;
                      _clearCustomWeeklyPlacement();
                    }
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void _showExperiencePicker(ThemeData theme) {
    HxSheet.show(
      context,
      builder: (sheetContext) => HxSheet(
        scrollable: false,
        title: 'Training Experience',
        subtitle: 'Calibrates volume, fatigue management, and progression ramp',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final level in ExperienceLevel.values)
              _sheetOptionCard<ExperienceLevel>(
                sheetContext: sheetContext,
                theme: theme,
                item: level,
                selectedItem: _experience,
                title: level.label,
                subtitle: switch (level) {
                  ExperienceLevel.novice =>
                    'Building consistency and progressing session to session.',
                  ExperienceLevel.intermediate =>
                    'Needs planned progression, fatigue control and exercise waves.',
                  ExperienceLevel.advanced =>
                    'Experienced with RIR/RPE and structured training blocks.',
                },
                icon: switch (level) {
                  ExperienceLevel.novice => Icons.school_rounded,
                  ExperienceLevel.intermediate => Icons.trending_up_rounded,
                  ExperienceLevel.advanced => Icons.military_tech_rounded,
                },
                isRecommended: _experienceRecommendation?.level == level,
                onSelected: (selected) {
                  setState(() {
                    _experience = selected;
                    _applySmartDefaults();
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void _showLengthPicker(ThemeData theme) {
    const lengths = [4, 6, 8, 12, 16, 24];
    final kgSpec = _primaryLiftSpecialization;
    final kgIssues = kgSpec == null
        ? const <ProgramGuardrailIssue>[]
        : ProgramGuardrails.validateKgIncrease(
            specialization: kgSpec,
            experience: _experience,
          );
    HxSheet.show(
      context,
      builder: (sheetContext) => HxSheet(
        scrollable: true,
        initialSize: 0.7,
        maxSize: 0.85,
        title: 'Block Length',
        subtitle: 'Total duration of this training mesocycle',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            kgIssues.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(bottom: HxSpace.x3),
                    child: AiBriefRejectionBanner(
                      heading: "That's a big jump",
                      body: kgIssues.first.message,
                      footer: '',
                    ),
                  )
                : const SizedBox.shrink(),
            for (final w in lengths)
              _sheetOptionCard<int>(
                sheetContext: sheetContext,
                theme: theme,
                item: w,
                selectedItem: _weeks,
                title: '$w weeks',
                subtitle: switch (w) {
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
                  _ => '$w weeks training block.',
                },
                icon: Icons.calendar_today_rounded,
                isRecommended: w == 8,
                onSelected: (selected) {
                  if (_useLiftSpecialization &&
                      selected < _liftRecommendedWeeks) {
                    final recommended = _liftRecommendedWeeks;
                    setState(() => _weeks = recommended);
                    // The pill holds one line: the adjustment is the
                    // headline, the reason sits above it.
                    AppNotice.show(
                      context,
                      'Block set to $recommended weeks for '
                      '${_targetSquatKg.toStringAsFixed(0)} kg '
                      '${_specializationLift.label}',
                      title: 'Not enough time to progress safely',
                      kind: AppNoticeKind.info,
                      duration: const Duration(seconds: 6),
                    );
                  } else {
                    setState(() => _weeks = selected);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void _showSpecializationInfoDialog(ThemeData theme) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.help_outline_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            const Text('Lift Specialization'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Primary lift specialization configures your block to focus heavily on progressing one main compound movement (Squat, Deadlift, Bench Press, Overhead Press, or Pull-up).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.secondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '• 3 exposures per week for maximum skill and strength adaptation\n'
              '• Tailored assistance exercises to fix your exact sticking point\n'
              '• Maintains overall full-body muscular balance',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onSurface,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  void _showInfoDialog(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required String body,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.secondary,
            height: 1.4,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
