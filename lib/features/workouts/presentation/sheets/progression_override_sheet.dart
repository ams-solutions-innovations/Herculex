import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';

class ProgressionOverrideSheet extends ConsumerStatefulWidget {
  final int exerciseId;
  final String exerciseName;
  final ScrollController? scrollController;

  const ProgressionOverrideSheet({
    super.key,
    required this.exerciseId,
    required this.exerciseName,
    this.scrollController,
  });

  static Future<void> show(
    BuildContext context, {
    required int exerciseId,
    required String exerciseName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ProgressionOverrideSheet(
          exerciseId: exerciseId,
          exerciseName: exerciseName,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  ConsumerState<ProgressionOverrideSheet> createState() =>
      _ProgressionOverrideSheetState();
}

class _ProgressionOverrideSheetState
    extends ConsumerState<ProgressionOverrideSheet> {
  ProgressionGoal _goal = ProgressionGoal.muscleGain;
  double _weeklyPct = 5.0;
  bool _enabled = true;
  String _progressionModel = 'linear';
  int _targetSets = 3;
  int _targetRepsMin = 8;
  int _targetRepsMax = 12;
  bool _autoAddSets = false;
  int _autoAddSetsCount = 3;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final existing = await ref
        .read(exerciseProgressionsRepositoryProvider)
        .forExercise(widget.exerciseId);
    if (existing != null && mounted) {
      setState(() {
        _goal = ProgressionGoal.values.firstWhere(
          (g) => g.name == existing.goal,
          orElse: () => ProgressionGoal.muscleGain,
        );
        _weeklyPct = existing.weeklyIncreasePct;
        _enabled = existing.enabled;
        _progressionModel = existing.progressionModel;
        _targetSets = existing.targetSets ?? 3;
        _targetRepsMin = existing.targetRepsMin ?? _goal.repsMin;
        _targetRepsMax = existing.targetRepsMax ?? _goal.repsMax;
        _autoAddSets = existing.autoAddSets;
        _autoAddSetsCount = existing.autoAddSetsCount;
      });
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    await ref
        .read(exerciseProgressionsRepositoryProvider)
        .upsert(
          widget.exerciseId,
          goal: _goal,
          weeklyIncreasePct: _weeklyPct,
          enabled: _enabled,
          progressionModel: _progressionModel,
          targetSets: _targetSets,
          targetRepsMin: _targetRepsMin,
          targetRepsMax: _targetRepsMax,
          autoAddSets: _autoAddSets,
          autoAddSetsCount: _autoAddSetsCount,
        );
    ref.invalidate(exerciseProgressionProvider(widget.exerciseId));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await ref
        .read(exerciseProgressionsRepositoryProvider)
        .delete(widget.exerciseId);
    ref.invalidate(exerciseProgressionProvider(widget.exerciseId));
    if (mounted) Navigator.of(context).pop();
  }

  void _selectGoal(ProgressionGoal goal) {
    setState(() {
      _goal = goal;
      // Choosing a goal is intentionally meaningful: it gives the user a
      // sensible progression behaviour and targets straight away. They can
      // still override every one of these settings below.
      _progressionModel = goal.recommendedProgressionModel;
      _weeklyPct = goal.weeklyIncreasePct;
      _targetRepsMin = goal.repsMin;
      _targetRepsMax = goal.repsMax;
    });
  }

  String get _progressionExplanation {
    if (_progressionModel == 'double') {
      return 'Keep the same load until you complete $_targetSets sets of '
          '$_targetRepsMax reps. Then Herculex increases the load and takes '
          'you back to $_targetRepsMin reps.';
    }
    return 'Work toward $_targetRepsMax reps. Once you reach the top of the '
        'range, Herculex adds ${_weeklyPct.toStringAsFixed(1)}% load and '
        'returns to $_targetRepsMin reps.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = ref
        .watch(exerciseProgressionProvider(widget.exerciseId))
        .asData
        ?.value;

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: BoxDecoration(
        color: theme.bottomSheetTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'How should this exercise progress?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                widget.exerciseName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose what a good next workout means for ${widget.exerciseName}. '
                'You can fine-tune the rule below.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ENABLED',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Switch(
                    value: _enabled,
                    onChanged: _loaded
                        ? (v) => setState(() => _enabled = v)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'PROGRESSION FOCUS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              ...ProgressionGoal.values.map(
                (goal) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ProgressionGoalOption(
                    goal: goal,
                    selected: _goal == goal,
                    enabled: _loaded && _enabled,
                    onTap: () => _selectGoal(goal),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_graph_rounded, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Current rule: $_targetSets × $_targetRepsMin–$_targetRepsMax reps '
                        '• ${_progressionModel == 'double' ? 'Reps first' : 'Load first'}\n'
                        '$_progressionExplanation',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'WEEKLY INCREASE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    '${_weeklyPct.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _weeklyPct,
                min: 0.5,
                max: 10.0,
                divisions: 19,
                onChanged: _loaded && _enabled
                    ? (v) => setState(() => _weeklyPct = v)
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                'HOW TO EARN THE NEXT INCREASE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ProgressionModelOption(
                      title: 'Load first',
                      subtitle: 'Add load after a top-range set.',
                      selected: _progressionModel == 'linear',
                      enabled: _loaded && _enabled,
                      onTap: () => setState(() => _progressionModel = 'linear'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ProgressionModelOption(
                      title: 'Reps first',
                      subtitle: 'Own every set before adding load.',
                      selected: _progressionModel == 'double',
                      enabled: _loaded && _enabled,
                      onTap: () => setState(() => _progressionModel = 'double'),
                    ),
                  ),
                ],
              ),
              if (_progressionModel == 'double') ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TARGET SETS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      '$_targetSets',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _targetSets.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: _loaded && _enabled
                      ? (v) => setState(() => _targetSets = v.toInt())
                      : null,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TARGET REP RANGE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      '$_targetRepsMin–$_targetRepsMax',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                RangeSlider(
                  values: RangeValues(
                    _targetRepsMin.toDouble(),
                    _targetRepsMax.toDouble(),
                  ),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  onChanged: _loaded && _enabled
                      ? (v) => setState(() {
                          _targetRepsMin = v.start.round();
                          _targetRepsMax = v.end.round();
                        })
                      : null,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'AUTO-ADD SETS ON LOG',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Switch(
                    value: _autoAddSets,
                    onChanged: _loaded && _enabled
                        ? (v) => setState(() => _autoAddSets = v)
                        : null,
                  ),
                ],
              ),
              if (_autoAddSets) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SETS TO ADD',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.secondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      '$_autoAddSetsCount',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _autoAddSetsCount.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: _loaded && _enabled && _autoAddSets
                      ? (v) => setState(() => _autoAddSetsCount = v.toInt())
                      : null,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _loaded ? _save : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                  if (existing != null) ...[
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _delete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 20,
                        ),
                      ),
                      child: const Text('Remove'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressionGoalOption extends StatelessWidget {
  const _ProgressionGoalOption({
    required this.goal,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ProgressionGoal goal;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  IconData get _icon => switch (goal) {
    ProgressionGoal.strength => Icons.fitness_center_rounded,
    ProgressionGoal.muscleGain => Icons.stacked_line_chart_rounded,
    ProgressionGoal.aesthetics => Icons.visibility_outlined,
    ProgressionGoal.fatLoss => Icons.local_fire_department_outlined,
    ProgressionGoal.endurance => Icons.directions_run_rounded,
    ProgressionGoal.athletic => Icons.bolt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? AppColors.primary : AppColors.outlineVariant;
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.09)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _icon,
                color: selected ? AppColors.primary : AppColors.secondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            goal.label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: selected ? AppColors.primary : null,
                            ),
                          ),
                        ),
                        Text(
                          '${goal.repsMin}–${goal.repsMax} reps',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: selected
                                ? AppColors.primary
                                : AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(goal.description, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.primary : AppColors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressionModelOption extends StatelessWidget {
  const _ProgressionModelOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: selected ? AppColors.primary : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
