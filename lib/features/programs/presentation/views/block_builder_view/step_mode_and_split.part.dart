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
        for (final mode in const [
          ProgramBuildMode.manual,
          ProgramBuildMode.guided,
          ProgramBuildMode.smart,
          ProgramBuildMode.herculexAi,
        ])
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
              trailing: Icon(
                switch (mode) {
                  ProgramBuildMode.manual => Icons.edit_note_rounded,
                  ProgramBuildMode.guided => Icons.lightbulb_outline_rounded,
                  ProgramBuildMode.smart => Icons.auto_awesome_rounded,
                  ProgramBuildMode.herculexAi => Icons.psychology_rounded,
                },
                color: _buildMode == mode
                    ? AppColors.primary
                    : AppColors.secondary,
                size: 22,
              ),
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
        if (_buildMode == ProgramBuildMode.herculexAi) ...[
          const SizedBox(height: 24),
          _sectionLabel(theme, 'Herculex AI brief'),
          const SizedBox(height: 6),
          _builderInputCard(
            theme,
            icon: Icons.auto_awesome_rounded,
            title: 'Herculex AI design brief',
            subtitle: _acceptedHerculexBrief != null
                ? '${_acceptedHerculexBrief!.splitType.label} · '
                      '${_acceptedHerculexBrief!.periodizationModel.label}. '
                      '${_acceptedHerculexBrief!.phaseIntent}'
                : 'Herculex AI drafts a split, periodization and day-by-day '
                      'focus for you to review and confirm.',
            selected: _acceptedHerculexBrief != null,
            status: _acceptedHerculexBrief != null ? 'Applied' : null,
            actionWidget: _acceptedHerculexBrief != null
                ? PremiumButton(
                    expand: true,
                    isPrimary: false,
                    icon: Icons.auto_awesome_rounded,
                    text: _generatingBrief ? 'Generating…' : 'Regenerate',
                    onTap: _generatingBrief ? () {} : _generateHerculexBrief,
                  )
                : PremiumButton(
                    expand: true,
                    isPrimary: true,
                    icon: Icons.auto_awesome_rounded,
                    text: _generatingBrief
                        ? 'Generating…'
                        : 'Generate with Herculex AI',
                    onTap: _generatingBrief ? () {} : _generateHerculexBrief,
                  ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('training-style-note'),
            controller: _trainingStyleNoteCtrl,
            maxLines: 3,
            maxLength: 400,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'How do you like to train? (optional)',
              hintText:
                  'For example: few hard sets, myo-reps on isolations, or a '
                  'lot of exercise variety.',
              helperText:
                  'Herculex AI reads this and picks from the options in '
                  'this app. You can change everything afterwards.',
              helperMaxLines: 2,
            ),
          ),
          if (_herculexRejectionMessage != null) ...[
            const SizedBox(height: 12),
            AiBriefRejectionBanner(
              heading: "Herculex AI suggestion couldn't be used",
              body: _herculexRejectionMessage!,
              footer:
                  'Showing the recommended Smart/Guided setup instead — you '
                  'can still adjust anything below.',
            ),
          ],
          if (_herculexDegradationMessage != null) ...[
            const SizedBox(height: 12),
            AiBriefRejectionBanner(
              heading: _herculexDegradationMessage!,
              body: '',
              footer: '',
            ),
          ],
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
                  _clearCustomWeeklyPlacement();
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
        _sectionLabel(
          theme,
          plan.mode == ScheduleMode.weekly ? 'Your week' : 'Your cycle',
        ),
        const SizedBox(height: 6),
        _planPreview(theme, plan),
        const SizedBox(height: 8),
        Text(
          plan.mode == ScheduleMode.weekly
              ? 'Auto = placed by the app from your split and days. Tap any '
                    'day to choose what you train, or to make it a rest day.'
              : 'Auto = placed by the app. Cycles repeat in the order shown.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.secondary,
          ),
        ),
        if (_recoveryWarnings(plan).isNotEmpty) ...[
          const SizedBox(height: 12),
          _recoveryWarning(theme, _recoveryWarnings(plan)),
        ],
      ],
    );
  }

  @override
  void _clearCustomWeeklyPlacement() {
    _weeklyDayLabels.clear();
    _weeklyTrainingWeekdays.clear();
    _userSetWeekdays.clear();
    _hasCustomWeeklyPlacement = false;
  }

  @override
  Future<void> _editWeeklyDay(int weekday) async {
    final options = _split.slots.isEmpty
        ? _plan.slotSummary.map((slot) => slot.label).toList()
        : SplitTemplates.slotsFor(
            _split,
            daysPerWeek: _daysPerWeek,
            distinctRepeatedDays: _buildMode != ProgramBuildMode.manual,
          );
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
                'What do you train on ${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][weekday - 1]}?',
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
          // A program needs at least one training day; keep the last one.
          if (_weeklyTrainingWeekdays.length <= 1 &&
              _weeklyTrainingWeekdays.contains(weekday)) {
            return;
          }
          _weeklyTrainingWeekdays.remove(weekday);
          _weeklyDayLabels.remove(weekday);
        } else {
          _weeklyTrainingWeekdays.add(weekday);
          _weeklyDayLabels[weekday] = selected;
        }
        _userSetWeekdays.add(weekday);
        // Days per week follows the weekdays the user actually picked, so the
        // stepper and the schedule can never disagree (the generator would
        // otherwise silently drop the last day).
        _daysPerWeek = _weeklyTrainingWeekdays.length;
        _templatesBySlot.clear();
      });
    }
  }

  // ── Step 2: exercise pools ─────────────────────────────────────────────────
}
