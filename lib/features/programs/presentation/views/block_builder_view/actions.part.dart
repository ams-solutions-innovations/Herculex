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
      final configIssues = ProgramGuardrails.validateConfiguration(
        buildMode: _buildMode,
        model: _model,
        split: _split,
        mainMethodByDayLabel: _mainMethodByDayLabel,
      );
      if (configIssues.any((issue) => issue.isBlocking)) {
        throw StateError(
          configIssues.firstWhere((issue) => issue.isBlocking).message,
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

  /// Calls [HerculexAiBriefService.generateBrief] exactly once per tap (D-04
  /// — "Generate"/"Regenerate" both route through this one method), then
  /// gates the result through [ProgramGuardrails.validateConfiguration]
  /// before it is allowed to become the accepted brief. The brief has not
  /// been applied to `_model`/`_split`/`_mainMethodByDayLabel` yet, so the
  /// guardrail is called against the brief's own implied configuration
  /// directly: `mainMethodByDayLabel` is intentionally an empty map because
  /// the brief never assigns per-day training methods (AIP-02 forbids that
  /// level of detail), so only the 6-day-PPL+Max-Effort structural check is
  /// meaningful here — the Max-Effort-per-week count check naturally yields
  /// zero issues because there are no method assignments yet, not because it
  /// was skipped.
  ///
  /// Every outcome branch (guardrail rejection, offline/unconfigured,
  /// over-quota, success) falls back to leaving the existing Smart/Guided
  /// recommendation as the active builder state — this method only ever sets
  /// Herculex-AI-scoped fields, never clears `_model`/`_split`/etc (D-05,
  /// AIP-05).
  @override
  Future<void> _generateHerculexBrief() async {
    setState(() {
      _generatingBrief = true;
      _herculexRejectionMessage = null;
      _herculexDegradationMessage = null;
      _acceptedHerculexBrief = null;
      _herculexBriefProvenance = const {};
    });
    try {
      final (brief, provenance) = await ref
          .read(herculexAiBriefServiceProvider)
          .generateBrief(
            profileInputs: {
              'goal': _goal.id,
              'experience': _experience.id,
              'weeks': _weeks,
            },
          );
      final configIssues = ProgramGuardrails.validateConfiguration(
        buildMode: ProgramBuildMode.herculexAi,
        model: brief.periodizationModel,
        split: brief.splitType,
        mainMethodByDayLabel: const {},
      );
      final blocking = configIssues.where((issue) => issue.isBlocking);
      if (!mounted) return;
      if (blocking.isNotEmpty) {
        setState(() => _herculexRejectionMessage = blocking.first.message);
      } else {
        setState(() {
          _acceptedHerculexBrief = brief;
          _herculexBriefProvenance = provenance;
        });
      }
    } on HerculexAiBriefException catch (e) {
      if (!mounted) return;
      setState(() {
        _herculexDegradationMessage = e.isQuotaExhausted
            ? "Today's Herculex AI program briefs are used up — try again "
                  'tomorrow. Continuing with the Smart/Guided recommendation.'
            : "Herculex AI isn't available right now — continuing with the "
                  'Smart/Guided recommendation.';
      });
    } finally {
      if (mounted) setState(() => _generatingBrief = false);
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
