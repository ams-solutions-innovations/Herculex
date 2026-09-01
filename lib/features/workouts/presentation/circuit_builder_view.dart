import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/circuits_repository.dart';
import 'package:herculex/features/workouts/presentation/circuits_providers.dart';
import 'package:herculex/features/workouts/presentation/exercise_picker_sheet.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';
import 'package:herculex/theme/colors.dart';
import 'package:herculex/ui/ui.dart';
import 'package:herculex/widgets/premium_button.dart';

class CircuitBuilderView extends ConsumerStatefulWidget {
  final WorkoutCircuitData? existing;

  const CircuitBuilderView({super.key, this.existing});

  static Future<WorkoutCircuitData?> show(
    BuildContext context, {
    WorkoutCircuitData? existing,
  }) {
    return Navigator.push<WorkoutCircuitData>(
      context,
      MaterialPageRoute(builder: (_) => CircuitBuilderView(existing: existing)),
    );
  }

  @override
  ConsumerState<CircuitBuilderView> createState() => _CircuitBuilderViewState();
}

class _CircuitBuilderViewState extends ConsumerState<CircuitBuilderView> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _notesCtrl;
  int _rounds = 3;
  int _restSeconds = 90;
  bool _saving = false;
  bool _loadingExisting = false;

  final List<_CircuitExerciseDraft> _draftExercises = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _notesCtrl = TextEditingController(text: widget.existing?.notes ?? '');
    if (widget.existing != null) {
      _rounds = widget.existing!.rounds;
      _restSeconds = widget.existing!.restSeconds;
      _loadExistingExercises();
    }
  }

  Future<void> _loadExistingExercises() async {
    setState(() => _loadingExisting = true);
    final repo = ref.read(circuitsRepositoryProvider);
    final entries = await repo.getCircuitExercises(widget.existing!.id);
    final snapshot = await ref
        .read(workoutsRepositoryProvider)
        .watchExerciseCatalog()
        .first;
    final catalogMap = {for (final e in snapshot.exercises) e.id: e};

    if (mounted) {
      setState(() {
        _draftExercises.clear();
        for (final entry in entries) {
          final catalog = catalogMap[entry.exerciseId];
          if (catalog != null) {
            _draftExercises.add(
              _CircuitExerciseDraft(
                exercise: catalog,
                targetReps: entry.targetReps ?? 10,
                targetWeightKg: entry.targetWeightKg,
              ),
            );
          }
        }
        _loadingExisting = false;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a circuit name')),
      );
      return;
    }
    if (_draftExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one exercise to the circuit'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(circuitsRepositoryProvider);

    final exerciseInputs = _draftExercises.map((draft) {
      return CircuitExerciseInput(
        exerciseId: draft.exercise.id,
        targetReps: draft.targetReps,
        targetWeightKg: draft.targetWeightKg,
      );
    }).toList();

    try {
      WorkoutCircuitData saved;
      if (widget.existing == null) {
        saved = await repo.createCircuit(
          name: name,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          rounds: _rounds,
          restSeconds: _restSeconds,
          exercises: exerciseInputs,
        );
      } else {
        await repo.updateCircuit(
          widget.existing!.id,
          name: name,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          rounds: _rounds,
          restSeconds: _restSeconds,
          exercises: exerciseInputs,
        );
        saved = (await repo.getCircuitById(widget.existing!.id))!;
      }

      if (mounted) {
        Navigator.of(context).pop(saved);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;

    return HxScreenShell(
      title: isEdit ? 'Edit Circuit' : 'New Circuit',
      actions: [
        if (!_saving)
          TextButton(
            onPressed: _save,
            child: Text(
              'Save',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
      children: [
        if (_loadingExisting)
          const Center(child: CircularProgressIndicator())
        else ...[
          // Name & Notes
          _PillField(
            label: 'Circuit Name *',
            controller: _nameCtrl,
            hint: 'e.g. Core Burner Circuit, Arm Blast',
          ),
          const SizedBox(height: 12),
          _PillField(
            label: 'Notes',
            controller: _notesCtrl,
            hint: 'Optional circuit description',
            maxLines: 2,
          ),
          const SizedBox(height: 20),

          // Rounds Selector
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CIRCUIT ROUNDS',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.secondary,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Number of times all exercises are performed',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _RoundStepperButton(
                          icon: Icons.remove,
                          onTap: _rounds > 1
                              ? () => setState(() => _rounds--)
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            '$_rounds',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        _RoundStepperButton(
                          icon: Icons.add,
                          onTap: _rounds < 20
                              ? () => setState(() => _rounds++)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Rest Between Rounds Selector
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PAUSE BETWEEN ROUNDS',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.secondary,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Rest time after completing all exercises in round',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer.withValues(
                          alpha: 0.35,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _formatSeconds(_restSeconds),
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [30, 45, 60, 90, 120, 180].map((sec) {
                    final isSelected = _restSeconds == sec;
                    return ChoiceChip(
                      label: Text(_formatSeconds(sec)),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _restSeconds = sec),
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.secondary,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 12,
                      ),
                      backgroundColor: AppColors.surfaceContainer,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Exercises in Circuit Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CIRCUIT EXERCISES (${_draftExercises.length})',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.secondary,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Exercise'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                onPressed: () async {
                  final results = await ExercisePickerSheet.show(context);
                  if (results == null || results.isEmpty || !context.mounted)
                    return;
                  setState(() {
                    for (final picked in results) {
                      _draftExercises.add(
                        _CircuitExerciseDraft(
                          exercise: picked.exercise,
                          targetReps: 10,
                        ),
                      );
                    }
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_draftExercises.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.repeat_rounded,
                    size: 40,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No exercises in circuit',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add 2 or more exercises to build your circuit',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _draftExercises.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < newIndex) newIndex -= 1;
                  final item = _draftExercises.removeAt(oldIndex);
                  _draftExercises.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final item = _draftExercises[index];
                return _CircuitExerciseTile(
                  key: ValueKey('${item.exercise.id}_$index'),
                  index: index,
                  draft: item,
                  onUpdateReps: (reps) =>
                      setState(() => item.targetReps = reps),
                  onUpdateWeight: (weight) =>
                      setState(() => item.targetWeightKg = weight),
                  onRemove: () =>
                      setState(() => _draftExercises.removeAt(index)),
                );
              },
            ),

          const SizedBox(height: 32),
          PremiumButton(
            text: _saving
                ? 'Saving Circuit…'
                : (isEdit ? 'Update Circuit' : 'Create Circuit'),
            icon: isEdit ? Icons.check : Icons.add,
            onTap: _saving ? () {} : _save,
          ),
        ],
      ],
    );
  }

  String _formatSeconds(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }
}

class _CircuitExerciseDraft {
  final ExerciseCatalogData exercise;
  int targetReps;
  double? targetWeightKg;

  _CircuitExerciseDraft({
    required this.exercise,
    required this.targetReps,
    this.targetWeightKg,
  });
}

class _CircuitExerciseTile extends StatelessWidget {
  final int index;
  final _CircuitExerciseDraft draft;
  final ValueChanged<int> onUpdateReps;
  final ValueChanged<double?> onUpdateWeight;
  final VoidCallback onRemove;

  const _CircuitExerciseTile({
    super.key,
    required this.index,
    required this.draft,
    required this.onUpdateReps,
    required this.onUpdateWeight,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ex = draft.exercise;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '#${index + 1}',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ex.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  ex.primaryMuscle.isNotEmpty ? ex.primaryMuscle : ex.category,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _InlineMetricInput(
                      label: 'Reps',
                      value: '${draft.targetReps}',
                      onTap: () async {
                        final val = await _pickNumber(
                          context,
                          current: draft.targetReps,
                          title: 'Target Reps',
                        );
                        if (val != null && val > 0) onUpdateReps(val);
                      },
                    ),
                    const SizedBox(width: 12),
                    _InlineMetricInput(
                      label: 'Kg (opt)',
                      value:
                          draft.targetWeightKg != null &&
                              draft.targetWeightKg! > 0
                          ? '${draft.targetWeightKg}kg'
                          : '—',
                      onTap: () async {
                        final val = await _pickDouble(
                          context,
                          current: draft.targetWeightKg ?? 0,
                          title: 'Target Weight (kg)',
                        );
                        onUpdateWeight(val != null && val > 0 ? val : null);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: AppColors.secondary),
            onPressed: onRemove,
          ),
          Icon(Icons.drag_handle, size: 20, color: AppColors.secondary),
        ],
      ),
    );
  }

  Future<int?> _pickNumber(
    BuildContext context, {
    required int current,
    required String title,
  }) async {
    final ctrl = TextEditingController(text: '$current');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Reps'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<double?> _pickDouble(
    BuildContext context, {
    required double current,
    required String title,
  }) async {
    final ctrl = TextEditingController(text: current > 0 ? '$current' : '');
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Weight (kg)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _InlineMetricInput extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _InlineMetricInput({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundStepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _RoundStepperButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: onTap != null
              ? AppColors.surfaceContainer
              : AppColors.surfaceContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null
              ? AppColors.primary
              : AppColors.secondary.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

class _PillField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  const _PillField({
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.secondary,
              letterSpacing: 1.1,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}
