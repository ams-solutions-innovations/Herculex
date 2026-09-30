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

      if (_buildMode == ProgramBuildMode.herculexAi &&
          _acceptedHerculexBrief != null) {
        try {
          await ref
              .read(herculexAiBriefServiceProvider)
              .persistBrief(
                programId: programId,
                brief: _acceptedHerculexBrief!,
                provenance: _herculexBriefProvenance,
              );
        } catch (_) {
          // Non-fatal (D-08, T-27-20): the program itself was created
          // successfully above. The brief's provenance/rationale is
          // enrichment data ProgramReviewView reads opportunistically
          // (plan 27-12, itself wrapped in its own isolated try/catch) -
          // not required for the program to function. A persistence
          // failure here (e.g. a database error) must never roll back or
          // block an otherwise-successful program creation, so it is
          // swallowed rather than rethrown into this method's outer catch
          // (which would delete the just-created program).
        }
      }

      if (_buildMode != ProgramBuildMode.manual) {
        final jointStatuses = await ref
            .read(jointPainRepositoryProvider)
            .currentStatuses();
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
        // D-01: musclePriorities flows through the EXISTING Dream Physique
        // tuning seam - build the same muscleId -> priority.wireValue map
        // _loadDreamPhysiquePriorities() would build from a
        // PhysiqueProgrammingProfiles row, then call the unchanged
        // _applyDreamPhysiqueTuning() so its existing consumer logic fires.
        // Herculex AI's own brief fully supersedes any earlier Dream
        // Physique load for this builder session (the user explicitly chose
        // Herculex AI mode) - a REPLACE, not a merge.
        final musclePriorities = <String, String>{
          for (final priority in brief.musclePriorities)
            priority.muscleId: priority.priority.wireValue,
        };
        setState(() {
          _acceptedHerculexBrief = brief;
          _herculexBriefProvenance = provenance;
          // Cleared so _applyDreamPhysiqueTuning()'s existing early-return
          // guard (`if (_useManualMusclePlan || ...) return;`) does not
          // block it - mirrors the Dream Physique priorities card's own
          // onCardTap, which pairs this same reset with the same call.
          _useManualMusclePlan = false;
          _dreamPhysiquePriorities = musclePriorities;
          _applyDreamPhysiqueTuning();
          _dreamPhysiqueTuned = true;
          // D-03: pre-fills the same Step 1-5 pickers Smart/Guided already
          // render - no new screen. Direct assignment, mirroring how
          // _applySmartDefaults already assigns _model directly elsewhere
          // in this file. Assigned AFTER _applyDreamPhysiqueTuning() (which
          // calls _applySmartDefaults() internally and would otherwise
          // overwrite _model from _goal/_experience) so the brief's own
          // periodizationModel wins. Fully user-editable afterward via the
          // existing pickers - this method never runs again until the next
          // Generate/Regenerate tap.
          _split = brief.splitType;
          _model = brief.periodizationModel;
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
