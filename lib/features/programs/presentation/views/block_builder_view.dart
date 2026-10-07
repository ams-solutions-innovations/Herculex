import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/components/premium_text_field.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/hx_colors.dart';
import 'package:herculex/design_system/tokens/hx_geometry.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/data/herculex_ai_brief_service.dart';
import 'package:herculex/features/programs/data/smart_program_planner.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
import 'package:herculex/features/programs/domain/program_brief.dart';
import 'package:herculex/features/programs/domain/program_guardrails.dart';
import 'package:herculex/features/programs/domain/program_muscle_volume.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/presentation/sheets/template_picker_sheet.dart';
import 'package:herculex/features/programs/presentation/views/program_method_guide_view.dart';
import 'package:herculex/features/programs/presentation/views/program_review_view.dart';
import 'package:herculex/features/programs/presentation/widgets/ai_brief_rejection_banner.dart';
import 'package:herculex/features/programs/presentation/widgets/program_muscle_volume_card.dart';
import 'package:herculex/features/programs/presentation/widgets/specialization_volume_floor_card.dart';
import 'package:herculex/features/recovery/application/recovery_providers.dart';
import 'package:herculex/features/recovery/domain/joint_model.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:intl/intl.dart';

part 'block_builder_view/standalone_widgets.part.dart';
part 'block_builder_view/shared_helpers.part.dart';
part 'block_builder_view/dialogs.part.dart';
part 'block_builder_view/step_mode_and_split.part.dart';
part 'block_builder_view/step_parameters.part.dart';
part 'block_builder_view/step_parameters_specialization.part.dart';
part 'block_builder_view/step_pools.part.dart';
part 'block_builder_view/step_methods.part.dart';
part 'block_builder_view/step_schedule_summary.part.dart';
part 'block_builder_view/actions.part.dart';

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

/// Field-holding base for the builder's state. Every concern-grouped mixin
/// below is declared `on _BuilderStateBase` so it can share this private
/// field surface and call sibling mixins' methods via the abstract stubs
/// declared here — Dart cannot split one class body across files, so this
/// abstract-base-plus-mixins shape is the part/part-of-compatible substitute.
abstract class _BuilderStateBase extends ConsumerState<BlockBuilderView> {
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

  // Herculex AI mode (27-11): Generate/Regenerate state. _acceptedHerculexBrief
  // and _herculexBriefProvenance are the "brief accepted, ready to pre-fill"
  // signal plan 27-13's pre-fill/persistence wiring consumes directly.
  bool _generatingBrief = false;
  ProgramBrief? _acceptedHerculexBrief;
  // Read by _create() (plan 27-13) to pass through to
  // HerculexAiBriefService.persistBrief()'s provenance parameter.
  Map<String, dynamic> _herculexBriefProvenance = const {};
  String? _herculexRejectionMessage;
  String? _herculexDegradationMessage;

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

  // ── Abstract stubs: cross-mixin private-method surface ──────────────────
  // Each mixin below is declared `on _BuilderStateBase` only, so a mixin
  // calling a method implemented by a *different* mixin (or by the final
  // glue class) needs a signature-only stub here. Discovered mechanically
  // by iterating `flutter analyze` until zero "isn't defined" errors
  // remained — see 27-01-SUMMARY.md for the full method-to-file map.

  // Implemented on the final composed class (_BlockBuilderViewState) only.
  void _applySmartDefaults();
  void _applyDreamPhysiqueTuning();
  String get _effectiveName;

  // Implemented in shared_helpers.part.dart.
  Widget _title(
    ThemeData theme,
    String title,
    String subtitle, {
    bool centered = false,
  });
  Widget _sectionLabel(ThemeData theme, String text);
  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  });
  Widget _pickerTile(
    ThemeData theme, {
    Key? key,
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
    String? badge,
    required VoidCallback onTap,
  });
  Widget _settingToggleTile(
    ThemeData theme, {
    Key? key,
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required VoidCallback onInfoTap,
    String? tooltip,
  });
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
  });
  Widget _radioCard(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
    bool recommended = false,
    bool centered = false,
  });

  // Implemented in dialogs.part.dart.
  Widget _dreamPhysiqueAutoFillBanner(ThemeData theme);
  void _showGoalPicker(ThemeData theme);
  void _showTrainingStylePicker(ThemeData theme);
  void _showExperiencePicker(ThemeData theme);
  void _showLengthPicker(ThemeData theme);
  void _showSpecializationInfoDialog(ThemeData theme);
  void _showInfoDialog(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required String body,
  });

  // Implemented in step_mode_and_split.part.dart.
  void _clearCustomWeeklyPlacement();

  // Implemented in step_pools.part.dart.
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
  });
  String get _manualPlanSummary;
  Future<void> _showManualMusclePlan();
  Widget _slotCard(
    ThemeData theme,
    ({int slotIndex, String label}) slot,
    List<WorkoutTemplateData> templates,
  );

  // Implemented in step_parameters_specialization.part.dart.
  Future<bool> _showSpecializationModal(ThemeData theme);
  double? get _currentSquatKg;
  double get _targetSquatKg;
  int get _liftRecommendedWeeks;
  PrimaryLiftSpecialization? get _primaryLiftSpecialization;

  // Implemented in actions.part.dart.
  Future<void> _create();
  Future<void> _loadDreamPhysiquePriorities();
  Future<void> _generateHerculexBrief();
  String get _trainingStyleDescription;
}

class _BlockBuilderViewState extends _BuilderStateBase
    with
        _SharedHelpersMixin,
        _DialogsMixin,
        _StepModeAndSplitMixin,
        _StepParametersMixin,
        _StepParametersSpecializationMixin,
        _StepPoolsMixin,
        _StepMethodsMixin,
        _StepScheduleSummaryMixin,
        _BuilderActionsMixin {
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

  @override
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

  @override
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

  @override
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
}
