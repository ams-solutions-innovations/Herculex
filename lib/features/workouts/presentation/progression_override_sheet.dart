import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../theme/colors.dart';
import '../domain/progression_engine.dart';
import 'workouts_providers.dart';

class ProgressionOverrideSheet extends ConsumerStatefulWidget {
  final int exerciseId;
  final String exerciseName;

  const ProgressionOverrideSheet({
    super.key,
    required this.exerciseId,
    required this.exerciseName,
  });

  static Future<void> show(
    BuildContext context, {
    required int exerciseId,
    required String exerciseName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProgressionOverrideSheet(
        exerciseId: exerciseId,
        exerciseName: exerciseName,
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
      });
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    await ref.read(exerciseProgressionsRepositoryProvider).upsert(
          widget.exerciseId,
          goal: _goal,
          weeklyIncreasePct: _weeklyPct,
          enabled: _enabled,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing =
        ref.watch(exerciseProgressionProvider(widget.exerciseId)).asData?.value;

    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: BoxDecoration(
        color: theme.bottomSheetTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
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
          Text('Progression Override',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(widget.exerciseName,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.secondary)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ENABLED',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary, letterSpacing: 1.0)),
              Switch(
                value: _enabled,
                onChanged: _loaded ? (v) => setState(() => _enabled = v) : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('GOAL',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.secondary, letterSpacing: 1.0)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ProgressionGoal.values.map((g) {
              final selected = _goal == g;
              return ChoiceChip(
                label: Text(g.label),
                selected: selected,
                onSelected: _loaded && _enabled
                    ? (_) => setState(() => _goal = g)
                    : null,
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                side: BorderSide(
                  color: selected ? AppColors.primary : AppColors.outlineVariant,
                ),
                labelStyle: theme.textTheme.bodySmall?.copyWith(
                  color: selected ? AppColors.primary : null,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('WEEKLY INCREASE',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.secondary, letterSpacing: 1.0)),
              Text('${_weeklyPct.toStringAsFixed(1)}%',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _loaded ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
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
                        borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 20),
                  ),
                  child: const Text('Remove'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
