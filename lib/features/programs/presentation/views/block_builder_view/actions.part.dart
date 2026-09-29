part of '../block_builder_view.dart';

mixin _BuilderActionsMixin on _BuilderStateBase {
  void _goBackStep() {
    if (_step <= 1 || _saving) return;
    Haptics.selection();
    setState(() => _step--);
  }

  @override
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
        if (parsed.isNotEmpty &&
            !_dreamPhysiqueTuned &&
            !_useManualMusclePlan) {
          _applyDreamPhysiqueTuning();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _dreamPhysiquePriorities = const {});
    }
  }

  @override
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

  @override
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
