import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/components/premium_text_field.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/data/smart_program_planner.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
import 'package:herculex/features/programs/domain/program_muscle_volume.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/presentation/sheets/template_picker_sheet.dart';
import 'package:herculex/features/programs/presentation/views/program_method_guide_view.dart';
import 'package:herculex/features/programs/presentation/views/program_review_view.dart';
import 'package:herculex/features/programs/presentation/widgets/program_muscle_volume_card.dart';
import 'package:herculex/features/recovery/application/recovery_providers.dart';
import 'package:herculex/features/recovery/domain/joint_model.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:intl/intl.dart';

part 'block_builder_view/standalone_widgets.part.dart';

/// Five-step builder shared by Smart, Guided and Manual programming.
///
/// Step 3 attaches *real* workout templates to each split slot. The previous
/// version offered a list of seven hardcoded strings labelled "CHOOSE TEMPLATE"
/// and wrote them into the day name, so every block it built materialized
/// sessions with no exercises at all.
class BlockBuilderView extends ConsumerStatefulWidget {
  const BlockBuilderView({super.key, this.autoRecommendExperience = true});

  /// Kept injectable so the UI contract can be rendered deterministically in
  /// widget tests without launching background database reads.
  final bool autoRecommendExperience;

  @override
  ConsumerState<BlockBuilderView> createState() => _BlockBuilderViewState();
}

class _BlockBuilderViewState extends ConsumerState<BlockBuilderView> {
  static const _stepCount = 6;

  int _step = 1;
  bool _saving = false;
  bool _dreamPhysiqueTuned = false;

  ProgramBuildMode _buildMode = ProgramBuildMode.smart;
  TrainingGoal _goal = TrainingGoal.hypertrophy;
  ExperienceLevel _experience = ExperienceLevel.novice;
  ExperienceRecommendation? _experienceRecommendation;

  // Step 1
  final _nameCtrl = TextEditingController();
  int _weeks = 8;
  PeriodizationModel _model = PeriodizationModel.linear;
  TrainingStyle _trainingStyle = TrainingStyle.weightlifting;
  int _workoutDurationMinutes = 60;
  bool _allowTimeSavingSetTechniques = false;
  bool _includeAutomaticWarmups = false;
  bool _includeGppConditioning = true;
  bool _useLiftSpecialization = false;
  final _currentSquatCtrl = TextEditingController();
  final _targetSquatCtrl = TextEditingController(text: '140');
  PrimaryLift _specializationLift = PrimaryLift.squat;
  PrimaryLiftStickingPoint _liftStickingPoint =
      PrimaryLiftStickingPoint.unknown;

  // Step 2
  SplitType _split = SplitType.upperLower;
  int _daysPerWeek = SplitType.upperLower.defaultDaysPerWeek;
  ScheduleMode _mode = ScheduleMode.weekly;
  int _cycleLength = 5;
  final Map<int, String> _weeklyDayLabels = {};
  final Set<int> _weeklyTrainingWeekdays = {};
  bool _hasCustomWeeklyPlacement = false;

  // Step 3 — template per split slot.
  final Map<int, int?> _templatesBySlot = {};

  // Step 4 — per-day main slot method. Every supplemental/accessory slot is
  // still resolved independently by the planner.
  final Map<String, SlotTrainingMethod> _mainMethodByDayLabel = {};
  final Map<String, DayStressRole> _dayRoles = {};
  int? _waveOverrideWeeks;

  // Optional user-owned alternative to the Dream Physique analysis. A weight
  // is normalized in the UI, so users can think in relative percentages
  // rather than knowing programming labels such as MEV/MRV.
  bool _useManualMusclePlan = false;
  final Map<String, int> _manualMuscleWeights = {};
  final Map<String, int> _manualSetCaps = {};
  MuscleFocusWave _muscleFocusWave = MuscleFocusWave.steady;
  Map<String, String> _dreamPhysiquePriorities = const {};

  static const _manualMuscleLabels = <String, String>{
    'chest': 'Chest',
    'back': 'Back',
    'side_delts': 'Shoulders',
    'biceps': 'Biceps',
    'triceps': 'Triceps',
    'quads': 'Quads',
    'hamstrings': 'Hamstrings',
    'glutes': 'Glutes',
    'calves': 'Calves',
    'abs': 'Core',
  };

  // Step 4
  DateTime _startDate = _today();
  DateTimeRange? _vacation;
  TimeOfDay? _defaultStartTime;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  SplitPlan get _plan => SplitTemplates.generate(
    type: _split,
    daysPerWeek: _daysPerWeek,
    mode: _mode,
    cycleLength: _mode == ScheduleMode.cycle ? _cycleLength : null,
    weeklyDayLabels: _mode == ScheduleMode.weekly ? _weeklyDayLabels : null,
    preferredWeekdays: _mode == ScheduleMode.weekly && _hasCustomWeeklyPlacement
        ? _weeklyTrainingWeekdays.toList()
        : null,
  );

  @override
  void initState() {
    super.initState();
    if (widget.autoRecommendExperience) {
      Future<void>.microtask(_recommendExperience);
    }
    Future<void>.microtask(_loadDreamPhysiquePriorities);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currentSquatCtrl.dispose();
    _targetSquatCtrl.dispose();
    super.dispose();
  }

  String get _effectiveName {
    final typed = _nameCtrl.text.trim();
    if (typed.isNotEmpty) return typed;
    return '$_weeks-week ${_split.label}';
  }

  Future<void> _recommendExperience() async {
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now();
    final recent =
        await (db.select(db.workoutSessions)..where(
              (t) => t.startedAt.isBiggerOrEqualValue(
                now.subtract(const Duration(days: 84)),
              ),
            ))
            .get();
    final all = await (db.select(
      db.workoutSessions,
    )..orderBy([(t) => OrderingTerm(expression: t.startedAt)])).get();
    final rpeRows =
        await (db.select(db.setEntries)
              ..where((t) => t.rpeX10.isNotNull())
              ..limit(1))
            .get();
    final structured =
        await (db.select(db.programs)
              ..where((t) => t.periodizationModel.isNotIn(['none']))
              ..limit(1))
            .get();
    final months = all.isEmpty
        ? 0
        : now.difference(all.first.startedAt).inDays ~/ 30;
    final recommendation = ExperienceLevel.recommend(
      consistentTrainingMonths: months,
      sessionsLast12Weeks: recent.length,
      understandsRirRpe: rpeRows.isNotEmpty,
      hasRunStructuredBlocks: structured.isNotEmpty,
    );
    if (!mounted) return;
    setState(() {
      _experienceRecommendation = recommendation;
      _experience = recommendation.level;
      _applySmartDefaults();
    });
  }

  void _applySmartDefaults() {
    _model = switch ((_goal, _experience)) {
      (TrainingGoal.strength, ExperienceLevel.advanced) =>
        PeriodizationModel.block,
      (TrainingGoal.strength, _) => PeriodizationModel.linear,
      (TrainingGoal.powerbuilding, _) => PeriodizationModel.concurrent,
      (TrainingGoal.athletic, _) => PeriodizationModel.concurrent,
      _ => PeriodizationModel.linear,
    };
  }

  void _applyDreamPhysiqueTuning() {
    if (_useManualMusclePlan || _dreamPhysiquePriorities.isEmpty) return;
    final summary = ref.read(dreamPhysiqueSummaryProvider).valueOrNull;
    _goal = TrainingGoal.hypertrophy;
    _trainingStyle = TrainingStyle.weightlifting;
    if (summary != null && summary.estimatedMonths > 0) {
      if (summary.estimatedMonths <= 2) {
        _weeks = 8;
      } else {
        _weeks = 12;
      }
    }
    _applySmartDefaults();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _step == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _step == 1 || _saving) return;
        _goBackStep();
      },
      child: HxScreenShell(
        key: ValueKey('block-builder-step-$_step'),
        title: 'New block',
        padding: EdgeInsets.symmetric(horizontal: _step == 5 ? 12 : 20),
        pinnedBottom: _footer(theme),
        children: [
          switch (_step) {
            1 => _stepBuildModeAndPriorities(theme),
            2 => _stepExercisePools(theme),
            3 => _stepParameters(theme),
            4 => _stepSplit(theme),
            5 => _stepContentAndMethods(theme),
            _ => _stepSchedule(theme),
          },
        ],
      ),
    );
  }

  // ── Step 1: build mode & muscle priorities ─────────────────────────────────

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
                  Text('30 min', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary)),
                  Text('60 min', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary)),
                  Text('90 min', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary)),
                  Text('120 min', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary)),
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
                  TrainingStyle.calisthenics =>
                    Icons.accessibility_new_rounded,
                  TrainingStyle.mixedCalisthenicsWeights => Icons.layers_rounded,
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

  void _showExperiencePicker(ThemeData theme) {
    HxSheet.show(
      context,
      builder: (sheetContext) => HxSheet(
        scrollable: false,
        title: 'Training Experience',
        subtitle:
            'Calibrates volume, fatigue management, and progression ramp',
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

  void _showLengthPicker(ThemeData theme) {
    const lengths = [4, 6, 8, 12, 16, 24];
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
                  setState(() => _weeks = selected);
                },
              ),
          ],
        ),
      ),
    );
  }

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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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

  Future<bool> _showSpecializationModal(ThemeData theme) async {
    var tempLift = _specializationLift;
    final currentCtrl = TextEditingController(text: _currentSquatCtrl.text);
    final targetCtrl = TextEditingController(
      text: _targetSquatCtrl.text.isEmpty
          ? _defaultTargetFor(_specializationLift).toString()
          : _targetSquatCtrl.text,
    );
    var tempStickingPoint = _liftStickingPoint;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final stickingPoints = PrimaryLiftStickingPoint.values
                .where((point) => point.supportedLifts.contains(tempLift))
                .toList(growable: false);
            if (!stickingPoints.contains(tempStickingPoint)) {
              tempStickingPoint = PrimaryLiftStickingPoint.unknown;
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 8,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Primary lift specialization',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select which lift to prioritize and set your current baseline and target.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<PrimaryLift>(
                        initialValue: tempLift,
                        dropdownColor: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurface,
                        ),
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.secondary,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Target lift',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        items: [
                          for (final lift in PrimaryLift.values)
                            DropdownMenuItem(value: lift, child: Text(lift.label)),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() {
                            final oldDefault =
                                _defaultTargetFor(tempLift).toString();
                            if (targetCtrl.text.trim() == oldDefault) {
                              targetCtrl.text =
                                  _defaultTargetFor(value).toString();
                            }
                            tempLift = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: PremiumTextField(
                              controller: currentCtrl,
                              hintText: tempLift == PrimaryLift.pullUp
                                  ? 'Current added kg'
                                  : 'Current load (kg)',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PremiumTextField(
                              controller: targetCtrl,
                              hintText: tempLift == PrimaryLift.pullUp
                                  ? 'Target added kg'
                                  : 'Target load (kg)',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<PrimaryLiftStickingPoint>(
                        initialValue: tempStickingPoint,
                        dropdownColor: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(16),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurface,
                        ),
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.secondary,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Where does the lift slow down?',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        items: [
                          for (final point in stickingPoints)
                            DropdownMenuItem(
                              value: point,
                              child: Text(point.label),
                            ),
                        ],
                        onChanged: (value) => setSheetState(
                          () => tempStickingPoint =
                              value ?? PrimaryLiftStickingPoint.unknown,
                        ),
                      ),
                      if (tempLift == PrimaryLift.pullUp) ...[
                        const SizedBox(height: 10),
                        Text(
                          'For pull-ups, use 0 for bodyweight and enter added external load in kg when applicable.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final current = double.tryParse(
                                  currentCtrl.text.trim().replaceAll(',', '.'),
                                );
                                if (current == null || current < 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please enter your current load (kg).',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.pop(context, true);
                              },
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == true && mounted) {
      setState(() {
        _specializationLift = tempLift;
        _currentSquatCtrl.text = currentCtrl.text.trim();
        _targetSquatCtrl.text = targetCtrl.text.trim();
        _liftStickingPoint = tempStickingPoint;
        _useLiftSpecialization = true;
        _split = SplitType.fullBody;
        _daysPerWeek = 3;
        _model = PeriodizationModel.linear;
        _weeks = _liftRecommendedWeeks;
        _clearCustomWeeklyPlacement();
      });
      return true;
    }
    return false;
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

  Widget _stepSplit(ThemeData theme) {
    final plan = _plan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          theme,
          'Split',
          'Choose weekly or cycling rhythm.',
        ),
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

  Widget _stepExercisePools(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          theme,
          'Exercise pools',
          'Equipment and movement affinities.',
          centered: true,
        ),
        _builderInputCard(
          theme,
          icon: Icons.favorite_outline_rounded,
          title: 'Exercise preferences',
          subtitle: 'Movement affinities (Never, Like, Core).',
          action: 'Review',
          onTap: () => context.push(AppRoutes.exercises),
        ),
        _builderInputCard(
          theme,
          icon: Icons.fitness_center_rounded,
          title: 'Available equipment',
          subtitle: 'Gym profile and equipment access.',
          action: 'Configure',
          onTap: () => context.push(AppRoutes.gyms),
        ),
      ],
    );
  }

  Widget _builderInputCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? actionWidget,
    String? action,
    VoidCallback? onTap,
    VoidCallback? onCardTap,
    bool selected = false,
    String? status,
  }) {
    return GestureDetector(
      onTap: () {
        if (onCardTap != null) {
          Haptics.selection();
          onCardTap();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: .08)
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: .35),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: .18)
                          : AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary.withValues(alpha: .5)
                            : AppColors.outlineVariant.withValues(alpha: .3),
                      ),
                    ),
                    child: Text(
                      status,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected
                            ? AppColors.primary
                            : AppColors.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
                height: 1.3,
              ),
            ),
            if (actionWidget != null || action != null) ...[
              const SizedBox(height: 12),
              actionWidget ??
                  OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(action!),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  String get _manualPlanSummary {
    if (_manualMuscleWeights.isEmpty) {
      return 'Choose the muscles you want to prioritise.';
    }
    final total = _manualMuscleWeights.values.fold(0, (a, b) => a + b);
    return _manualMuscleWeights.entries
        .map((entry) {
          final pct = total == 0 ? 0 : (entry.value / total * 100).round();
          final cap = _manualSetCaps[entry.key] ?? 10;
          return '${_manualMuscleLabels[entry.key]} $pct% · ≤$cap sets';
        })
        .join('  •  ');
  }

  Future<void> _showManualMusclePlan() async {
    final result =
        await showModalBottomSheet<
          ({Map<String, int> weights, Map<String, int> caps})
        >(
          context: context,
          isScrollControlled: true,
          builder: (context) => _ManualMusclePlanSheet(
            labels: _manualMuscleLabels,
            initialWeights: _manualMuscleWeights,
            initialCaps: _manualSetCaps,
          ),
        );
    if (result == null || !mounted) return;
    setState(() {
      _useManualMusclePlan = true;
      _manualMuscleWeights
        ..clear()
        ..addAll(result.weights);
      _manualSetCaps
        ..clear()
        ..addAll(result.caps);
    });
  }

  Widget _slotCard(
    ThemeData theme,
    ({int slotIndex, String label}) slot,
    List<WorkoutTemplateData> templates,
  ) {
    final templateId = _templatesBySlot[slot.slotIndex];
    final template = templateId == null
        ? null
        : templates.where((t) => t.id == templateId).firstOrNull;
    final repeats = _plan.trainingDays
        .where((d) => d.slotIndex == slot.slotIndex)
        .length;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        final picked = await TemplatePickerSheet.show(context);
        if (picked == null) return;
        setState(() => _templatesBySlot[slot.slotIndex] = picked.id);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: template != null
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.outlineVariant.withValues(alpha: 0.4),
            width: template != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template?.name ??
                        'Tap to link a template'
                            '${repeats > 1 ? ' · used $repeats× per week' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: template != null
                          ? AppColors.primary
                          : AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (template != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, color: AppColors.secondary),
                onPressed: () =>
                    setState(() => _templatesBySlot.remove(slot.slotIndex)),
              )
            else
              Icon(Icons.add_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  // ── Step 5: content & methods ──────────────────────────────────────────────

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
        .map((id) => _manualMuscleLabels[id] ?? id)
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
              firstDate: _today().subtract(const Duration(days: 30)),
              lastDate: _today().add(const Duration(days: 365)),
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

  Widget _title(
    ThemeData theme,
    String title,
    String subtitle, {
    bool centered = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: centered
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Text(
              title,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.secondary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _pickerTile(
    ThemeData theme, {
    Key? key,
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
    String? badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: () {
        Haptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          fontSize: 10,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.secondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingToggleTile(
    ThemeData theme, {
    Key? key,
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required VoidCallback onInfoTap,
    String? tooltip,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, size: 20),
            tooltip: tooltip ?? '$title info',
            visualDensity: VisualDensity.compact,
            color: AppColors.secondary,
            onPressed: () {
              Haptics.selection();
              onInfoTap();
            },
          ),
          const SizedBox(width: 4),
          Switch.adaptive(
            key: key,
            value: value,
            onChanged: (val) {
              Haptics.selection();
              onChanged(val);
            },
          ),
        ],
      ),
    );
  }

  Widget _sheetOptionCard<T>({
    required BuildContext sheetContext,
    required ThemeData theme,
    required T item,
    required T selectedItem,
    required String title,
    String? subtitle,
    IconData? icon,
    bool isRecommended = false,
    required ValueChanged<T> onSelected,
  }) {
    final isSelected = item == selectedItem;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          Haptics.selection();
          onSelected(item);
          Navigator.pop(sheetContext);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.12)
                : AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : isRecommended
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.outlineVariant.withValues(alpha: 0.3),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? AppColors.primary : AppColors.secondary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.onSurface,
                          ),
                        ),
                        if (isRecommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'RECOMMENDED',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.secondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.outlineVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _radioCard(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
    bool recommended = false,
    bool centered = false,
  }) {
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.10)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : recommended
                ? AppColors.primary.withValues(alpha: 0.65)
                : AppColors.outlineVariant.withValues(alpha: 0.3),
            width: selected || recommended ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: centered
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                crossAxisAlignment: centered
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: centered ? TextAlign.center : TextAlign.start,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                    textAlign: centered ? TextAlign.center : TextAlign.start,
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: PremiumButton(
          text: _saving
              ? 'Creating…'
              : _step == _stepCount
              ? 'Create block'
              : 'Continue',
          onTap: _saving
              ? () {}
              : () {
                  if (_step < _stepCount) {
                    if (_step == 1 &&
                        !_useManualMusclePlan &&
                        _dreamPhysiquePriorities.isNotEmpty &&
                        !_dreamPhysiqueTuned) {
                      _applyDreamPhysiqueTuning();
                      _dreamPhysiqueTuned = true;
                    }
                    setState(() => _step++);
                  } else {
                    _create();
                  }
                },
        ),
      ),
    );
  }

  void _goBackStep() {
    if (_step <= 1 || _saving) return;
    Haptics.selection();
    setState(() => _step--);
  }

  Future<void> _loadDreamPhysiquePriorities() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final row =
          await (db.select(db.physiqueProgrammingProfiles)
                ..where((table) => table.active.equals(true))
                ..orderBy([(table) => OrderingTerm.desc(table.confirmedAt)])
                ..limit(1))
              .getSingleOrNull();
      if (!mounted) return;
      if (row == null) {
        setState(() => _dreamPhysiquePriorities = const {});
        return;
      }
      final decoded = jsonDecode(row.prioritiesJson);
      final priorities = decoded is Map ? decoded['musclePriorities'] : null;
      final parsed = <String, String>{};
      if (priorities is List) {
        for (final item in priorities.whereType<Map>()) {
          final muscleId = item['muscleId'];
          final priority = item['priority'];
          if (muscleId is String && priority is String) {
            parsed[muscleId] = priority;
          }
        }
      }
      setState(() {
        _dreamPhysiquePriorities = parsed;
        if (parsed.isNotEmpty && !_dreamPhysiqueTuned && !_useManualMusclePlan) {
          _applyDreamPhysiqueTuning();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _dreamPhysiquePriorities = const {});
    }
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    final repo = ref.read(programsRepositoryProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    int? createdProgramId;
    try {
      if (_mode == ScheduleMode.weekly &&
          _plan.trainingDayCount != _daysPerWeek) {
        throw StateError(
          'Choose exactly $_daysPerWeek training days before creating the block.',
        );
      }
      if (_useLiftSpecialization && _primaryLiftSpecialization == null) {
        throw StateError(
          'Enter your current ${_specializationLift.label} before creating a specialization block.',
        );
      }
      final explicitMaxEffort = _mainMethodByDayLabel.values
          .where((method) => method == SlotTrainingMethod.maxEffort)
          .length;
      if (_buildMode != ProgramBuildMode.manual && explicitMaxEffort > 2) {
        throw StateError(
          'A Smart program can use at most two Max Effort patterns per week.',
        );
      }
      if (_buildMode != ProgramBuildMode.manual &&
          _model == PeriodizationModel.maxEffort &&
          _split == SplitType.ppl) {
        throw StateError(
          'A six-day PPL would create three Max Effort days. Use per-slot Max Effort or choose a Conjugate 3–4 day structure.',
        );
      }

      final programId = await repo.createProgramFromSplit(
        name: _effectiveName,
        description:
            '${_goal.label} · ${_experience.label} · ${_model.label}.${_primaryLiftSpecialization == null ? '' : ' ${_primaryLiftSpecialization!.lift.label} specialization: ${_primaryLiftSpecialization!.assistanceFocus}'}',
        weeks: _weeks,
        plan: _plan,
        startDate: _startDate,
        periodizationModel: _model.id,
        templateIdsBySlot: _templatesBySlot,
        defaultStartTimeMinutes: _defaultStartTime == null
            ? null
            : _defaultStartTime!.hour * 60 + _defaultStartTime!.minute,
        buildMode: _buildMode,
        trainingGoal: _goal,
        experienceLevel: _experience,
        adaptationMode: AdaptationMode.reviewStructural,
        // A plan is invisible and unscheduled until the user has reviewed its
        // exercises and explicitly confirmed it on ProgramReviewView.
        activate: false,
        archived: true,
        materialize: false,
      );
      createdProgramId = programId;

      if (_buildMode != ProgramBuildMode.manual) {
        final jointStatuses = await ref
            .read(jointPainRepositoryProvider)
            .watchCurrentStatuses()
            .first;
        final flaggedJoints = {
          for (final status in jointStatuses.values)
            if (status.isFlagged) status.joint,
        };
        final excludedMuscles = JointModel.excludedMusclesFor(flaggedJoints);
        await SmartProgramPlanner(ref.read(appDatabaseProvider)).populate(
          programId,
          SmartProgramConfiguration(
            goal: _goal,
            experience: _experience,
            trainingStyle: _trainingStyle,
            excludedMuscles: excludedMuscles,
            workoutDurationMinutes: _workoutDurationMinutes,
            allowTimeSavingSetTechniques: _allowTimeSavingSetTechniques,
            includeAutomaticWarmups: _includeAutomaticWarmups,
            includeGppConditioning:
                _trainingStyle == TrainingStyle.fullBody2xGpp
                ? _includeGppConditioning
                : null,
            primaryLiftSpecialization: _primaryLiftSpecialization,
            buildMode: _buildMode,
            mainMethodByDayLabel: _mainMethodByDayLabel,
            dayRoles: _dayRoles,
            musclePriorities: _manualPriorities,
            muscleVolumeWeights: _manualWeights,
            weeklySetCaps: _useManualMusclePlan ? _manualSetCaps : const {},
            muscleFocusWave: _useManualMusclePlan
                ? _muscleFocusWave
                : MuscleFocusWave.steady,
            waveOverrideWeeks: _waveOverrideWeeks,
          ),
        );
      }
      await repo.snapshotLinkedTemplates(programId);

      if (_vacation != null) {
        await repo.addExternalEvent(
          from: _vacation!.start,
          to: _vacation!.end,
          type: 'vacation',
        );
      }

      if (!mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProgramReviewView(programId: programId),
        ),
      );
    } catch (e) {
      if (createdProgramId != null) {
        await repo.deleteProgram(createdProgramId);
      }
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create the block: $e')),
      );
    }
  }

  Map<String, String> get _manualPriorities {
    if (!_useManualMusclePlan || _manualMuscleWeights.isEmpty) return const {};
    final highest = _manualMuscleWeights.values.reduce((a, b) => a > b ? a : b);
    return {
      for (final entry in _manualMuscleWeights.entries)
        entry.key: entry.value == highest ? 'high' : 'medium',
    };
  }

  Map<String, double> get _manualWeights {
    if (!_useManualMusclePlan || _manualMuscleWeights.isEmpty) return const {};
    final total = _manualMuscleWeights.values.fold(0, (a, b) => a + b);
    if (total == 0) return const {};
    return {
      for (final entry in _manualMuscleWeights.entries)
        entry.key: entry.value / total,
    };
  }

  double? get _currentSquatKg =>
      double.tryParse(_currentSquatCtrl.text.trim().replaceAll(',', '.'));

  double get _targetSquatKg =>
      double.tryParse(_targetSquatCtrl.text.trim().replaceAll(',', '.')) ?? 140;

  int get _liftRecommendedWeeks => PrimaryLiftSpecialization.recommendedWeeks(
    currentKg: _currentSquatKg ?? 0,
    targetKg: _targetSquatKg,
    isNovice: _experience == ExperienceLevel.novice,
  );

  PrimaryLiftSpecialization? get _primaryLiftSpecialization {
    if (!_useLiftSpecialization || _currentSquatKg == null) return null;
    return PrimaryLiftSpecialization(
      lift: _specializationLift,
      currentKg: _currentSquatKg!,
      targetKg: _targetSquatKg,
      weeks: _weeks,
      stickingPoint: _liftStickingPoint,
    );
  }

  int _defaultTargetFor(PrimaryLift lift) => switch (lift) {
    PrimaryLift.squat => 140,
    PrimaryLift.deadlift => 180,
    PrimaryLift.benchPress => 100,
    PrimaryLift.overheadPress => 60,
    PrimaryLift.pullUp => 20,
  };

  String get _trainingStyleDescription => switch (_trainingStyle) {
    TrainingStyle.weightlifting =>
      'Common free-weight and machine movements, matched to your experience.',
    TrainingStyle.calisthenics =>
      'Bodyweight-first exercise selection, with advanced skills kept out of automatic plans.',
    TrainingStyle.basic =>
      'Only common machines, dumbbells and barbells—no specialty bars or niche variations.',
    TrainingStyle.crossfit =>
      'Conditioning-first sessions. The first version stays conservative: novice plans do not auto-select technical Olympic lifts or advanced skills.',
    TrainingStyle.mixedCalisthenicsWeights =>
      'A balanced pool of bodyweight and common loaded movements.',
    TrainingStyle.fullBody2xGpp =>
      'Two full-body strength sessions with optional general physical-preparedness work.',
  };
}
