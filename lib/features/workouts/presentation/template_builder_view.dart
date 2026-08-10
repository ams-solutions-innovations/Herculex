import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../widgets/premium_button.dart';
import '../domain/set_type.dart';
import 'exercise_picker_sheet.dart';
import 'set_type_menu.dart';
import 'workouts_providers.dart';

class TemplateBuilderView extends ConsumerStatefulWidget {
  final WorkoutTemplateData? existing;
  final int? initialFolderId;

  /// When true the editor offers a "Use template" action that pops with the
  /// template, so a caller that opened the builder to fill a slot (a program
  /// day, say) gets the result back. Off by default: opened from the Templates
  /// tab there is nothing to hand the template to.
  final bool returnsSelection;

  const TemplateBuilderView({
    super.key,
    this.existing,
    this.initialFolderId,
    this.returnsSelection = false,
  });

  static Future<WorkoutTemplateData?> show(
    BuildContext context, {
    WorkoutTemplateData? existing,
    int? initialFolderId,
    bool returnsSelection = false,
  }) {
    return Navigator.push<WorkoutTemplateData>(
      context,
      MaterialPageRoute(
        builder: (_) => TemplateBuilderView(
          existing: existing,
          initialFolderId: initialFolderId,
          returnsSelection: returnsSelection,
        ),
      ),
    );
  }

  @override
  ConsumerState<TemplateBuilderView> createState() => _TemplateBuilderViewState();
}

class _TemplateBuilderViewState extends ConsumerState<TemplateBuilderView> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save(WorkoutTemplateData template) async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final repo = ref.read(templatesRepositoryProvider);
    await repo.updateTemplate(template.id, name: name, notes: _notes.text.trim().isEmpty ? null : _notes.text.trim());
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templateId = widget.existing?.id;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          templateId == null ? 'New Template' : 'Edit Template',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (templateId != null && !_saving)
            TextButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                await _save(widget.existing!);
                if (!mounted || !widget.returnsSelection) return;
                // Hand the finished template back to whatever opened us.
                navigator.pop(widget.existing);
              },
              child: Text(
                widget.returnsSelection ? 'Use template' : 'Save',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: templateId == null
          ? _CreateForm(
              nameCtrl: _name,
              notesCtrl: _notes,
              initialFolderId: widget.initialFolderId,
              returnsSelection: widget.returnsSelection,
            )
          : _EditBody(
              template: widget.existing!,
              nameCtrl: _name,
              notesCtrl: _notes,
            ),
    );
  }
}

// ── Create form (no templateId yet — create then navigate to edit) ──────────

class _CreateForm extends ConsumerStatefulWidget {
  final TextEditingController nameCtrl;
  final TextEditingController notesCtrl;
  final int? initialFolderId;
  final bool returnsSelection;
  const _CreateForm({
    required this.nameCtrl,
    required this.notesCtrl,
    this.initialFolderId,
    this.returnsSelection = false,
  });

  @override
  ConsumerState<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends ConsumerState<_CreateForm> {
  int? _selectedFolder;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedFolder = widget.initialFolderId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foldersAsync = ref.watch(workoutFoldersProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      children: [
        _PillField(label: 'Name *', controller: widget.nameCtrl, hint: 'e.g. Push Day A'),
        const SizedBox(height: 14),
        _PillField(label: 'Notes', controller: widget.notesCtrl, hint: 'Optional description', maxLines: 3),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'FOLDER',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, letterSpacing: 1.2),
          ),
        ),
        const SizedBox(height: 10),
        foldersAsync.when(
          data: (folders) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FolderChip(
                label: 'No folder',
                emoji: '—',
                selected: _selectedFolder == null,
                onTap: () => setState(() => _selectedFolder = null),
              ),
              for (final f in folders)
                _FolderChip(
                  label: f.name,
                  emoji: f.emoji,
                  selected: _selectedFolder == f.id,
                  onTap: () => setState(() => _selectedFolder = f.id),
                ),
            ],
          ),
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 32),
        PremiumButton(
          text: _saving ? 'Creating…' : 'Create & Add Exercises',
          icon: Icons.add,
          onTap: _saving ? () {} : () async {
            final name = widget.nameCtrl.text.trim();
            if (name.isEmpty) return;
            setState(() => _saving = true);
            final repo = ref.read(templatesRepositoryProvider);
            final navigator = Navigator.of(context);
            final template = await repo.createTemplate(
              name: name,
              notes: widget.notesCtrl.text.trim().isEmpty ? null : widget.notesCtrl.text.trim(),
              folderId: _selectedFolder,
            );
            if (!mounted) return;
            navigator.pushReplacement(
              MaterialPageRoute(
                builder: (_) => TemplateBuilderView(
                  existing: template,
                  returnsSelection: widget.returnsSelection,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Edit body (template exists — add/reorder exercises) ─────────────────────

// ── Edit body (template exists — add/reorder exercises) ─────────────────────

class _EditBody extends ConsumerStatefulWidget {
  final WorkoutTemplateData template;
  final TextEditingController nameCtrl;
  final TextEditingController notesCtrl;

  const _EditBody({required this.template, required this.nameCtrl, required this.notesCtrl});

  @override
  ConsumerState<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends ConsumerState<_EditBody> {
  // Sticky "sets" count applied to exercises added via "Add Exercise" (item
  // 6): lets the user type e.g. 20 once instead of tapping "Add Set" 20x.
  int _defaultTargetSets = 3;

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    final nameCtrl = widget.nameCtrl;
    final notesCtrl = widget.notesCtrl;
    final theme = Theme.of(context);
    final exercisesAsync = ref.watch(templateExercisesProvider(template.id));
    final catalogAsync = ref.watch(exerciseCatalogProvider(const ExerciseCatalogFilter()));
    final repo = ref.read(templatesRepositoryProvider);
    final catalog = catalogAsync.asData?.value ?? [];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            children: [
              _PillField(label: 'Name', controller: nameCtrl, hint: 'Template name'),
              const SizedBox(height: 14),
              _PillField(label: 'Notes', controller: notesCtrl, hint: 'Optional description', maxLines: 2),
              const SizedBox(height: 20),

              // Muscle Group Volume Breakdown Header Card
              exercisesAsync.maybeWhen(
                data: (rows) => _MuscleGroupHeaderCard(exercises: rows, catalog: catalog),
                orElse: () => const SizedBox.shrink(),
              ),

              Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    'EXERCISES',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, letterSpacing: 1.2),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SetsCountChip(
                          label: 'Sets',
                          count: _defaultTargetSets,
                          onTap: () async {
                            final chosen = await _pickSetCount(
                              context,
                              current: _defaultTargetSets,
                              title: 'Default Sets For New Exercises',
                            );
                            if (chosen != null && chosen > 0) {
                              setState(() => _defaultTargetSets = chosen.clamp(1, 50));
                            }
                          },
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Exercise'),
                          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                          onPressed: () async {
                            final results = await ExercisePickerSheet.show(context);
                            if (results == null || results.isEmpty || !context.mounted) return;
                            for (final picked in results) {
                              await repo.addExerciseToTemplate(
                                templateId: template.id,
                                exerciseId: picked.exercise.id,
                                targetSets: _defaultTargetSets,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              exercisesAsync.when(
                data: (rows) {
                  if (rows.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.fitness_center_outlined, size: 40, color: AppColors.primary),
                          const SizedBox(height: 12),
                          Text('No exercises yet', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Tap Add Exercise to build your template', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final te in rows)
                        _TemplateExerciseCard(
                          key: ValueKey(te.id),
                          te: te,
                          exercise: catalog.firstWhere(
                            (e) => e.id == te.exerciseId,
                            orElse: () => _placeholder(te.exerciseId),
                          ),
                          onRemove: () => repo.removeExerciseFromTemplate(te.id),
                        ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: PremiumButton(
              text: 'Done',
              icon: Icons.check,
              onTap: () async {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  await repo.updateTemplate(template.id, name: name, notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim());
                }
                if (context.mounted) Navigator.of(context).pop(template);
              },
            ),
          ),
        ),
      ],
    );
  }

  ExerciseCatalogData _placeholder(int id) => ExerciseCatalogData(
        id: id, name: '…', primaryMuscle: '', equipment: '', mechanics: '',
        force: '', plane: '', defaultRestSeconds: 120, isCustom: false,
        category: 'strength', modality: 'barbell', cnsScore: 3,
        recoveryImpact: 3, loggingMetric: 'weight_reps',
        supportsWeightedBodyweight: false, isReviewed: false,
      );
}

// ── Muscle Group Breakdown Header ──────────────────────────────────────────

class _MuscleGroupHeaderCard extends ConsumerWidget {
  final List<TemplateExerciseData> exercises;
  final List<ExerciseCatalogData> catalog;

  const _MuscleGroupHeaderCard({required this.exercises, required this.catalog});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Collect muscle set counts
    final Map<String, int> muscleSetCounts = {};
    int totalWorkingSets = 0;
    int totalWarmupSets = 0;

    for (final te in exercises) {
      final ex = catalog.firstWhere(
        (c) => c.id == te.exerciseId,
        orElse: () => _placeholder(te.exerciseId),
      );
      final muscle = ex.primaryMuscle.trim().isNotEmpty ? _normalizeMuscle(ex.primaryMuscle) : 'Other';

      final setsAsync = ref.watch(templateExerciseSetsProvider(te.id));
      final sets = setsAsync.asData?.value ?? [];

      if (sets.isNotEmpty) {
        for (final s in sets) {
          if (s.isWarmup) {
            totalWarmupSets++;
          } else {
            totalWorkingSets++;
            muscleSetCounts[muscle] = (muscleSetCounts[muscle] ?? 0) + 1;
          }
        }
      } else {
        final count = te.targetSets > 0 ? te.targetSets : 3;
        totalWorkingSets += count;
        muscleSetCounts[muscle] = (muscleSetCounts[muscle] ?? 0) + count;
      }
    }

    if (exercises.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fitness_center_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Mišične skupine / Volume',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              Text(
                '$totalWorkingSets serij${totalWarmupSets > 0 ? ' (+$totalWarmupSets ogrevanje)' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in muscleSetCounts.entries)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_muscleEmoji(entry.key), style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 6),
                      Text(entry.key, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${entry.value} ${entry.value == 1 ? 'serija' : (entry.value == 2 ? 'seriji' : (entry.value == 3 || entry.value == 4 ? 'serije' : 'serij'))}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _normalizeMuscle(String raw) {
    final lower = raw.trim();
    if (lower.isEmpty) return 'Other';
    return lower.split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
  }

  String _muscleEmoji(String muscle) {
    final m = muscle.toLowerCase();
    if (m.contains('chest')) return '🏋️';
    if (m.contains('back') || m.contains('lat')) return '🪵';
    if (m.contains('shoulder') || m.contains('delt')) return '🛡️';
    if (m.contains('bicep')) return '💪';
    if (m.contains('tricep')) return '⚡';
    if (m.contains('quad') || m.contains('leg') || m.contains('thigh')) return '🦵';
    if (m.contains('glute')) return '🍑';
    if (m.contains('hamstring') || m.contains('calf') || m.contains('calves')) return '🦵';
    if (m.contains('ab') || m.contains('core')) return '🔥';
    return '🎯';
  }

  ExerciseCatalogData _placeholder(int id) => ExerciseCatalogData(
        id: id, name: '…', primaryMuscle: '', equipment: '', mechanics: '',
        force: '', plane: '', defaultRestSeconds: 120, isCustom: false,
        category: 'strength', modality: 'barbell', cnsScore: 3,
        recoveryImpact: 3, loggingMetric: 'weight_reps',
        supportsWeightedBodyweight: false, isReviewed: false,
      );
}

// ── Interactive Exercise Card with Empty Workout Set Table ─────────────────

class _TemplateExerciseCard extends ConsumerWidget {
  final TemplateExerciseData te;
  final ExerciseCatalogData exercise;
  final VoidCallback onRemove;

  const _TemplateExerciseCard({
    super.key,
    required this.te,
    required this.exercise,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(templatesRepositoryProvider);
    final setsAsync = ref.watch(templateExerciseSetsProvider(te.id));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.fitness_center, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      '${exercise.primaryMuscle}${exercise.equipment.isNotEmpty ? ' • ${exercise.equipment}' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                    ),
                  ],
                ),
              ),
              _SetsCountChip(
                label: 'Sets',
                count: te.targetSets > 0 ? te.targetSets : 3,
                onTap: () async {
                  final chosen = await _pickSetCount(
                    context,
                    current: te.targetSets > 0 ? te.targetSets : 3,
                    title: 'Number of Sets',
                  );
                  if (chosen != null && chosen > 0) {
                    await repo.updateTemplateExercise(
                      te.id,
                      targetSets: chosen.clamp(1, 50),
                    );
                  }
                },
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: AppColors.secondary),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Table header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text('SET', textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 48,
                  child: Text('TYPE', textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('TARGET KG', textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('TARGET REPS', textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
                const SizedBox(width: 32), // space for delete button
              ],
            ),
          ),
          const Divider(height: 10),
          setsAsync.when(
            data: (sets) {
              if (sets.isEmpty) {
                Future.microtask(() => repo.getTemplateSets(te.id));
                return const SizedBox(height: 32, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
              }
              return Column(
                children: [
                  for (var i = 0; i < sets.length; i++)
                    _TemplateSetRow(
                      key: ValueKey(sets[i].id),
                      index: i + 1,
                      set: sets[i],
                      onUpdateSetType: (selection) {
                        if (selection.delete) {
                          repo.deleteTemplateSet(sets[i].id);
                        } else if (selection.isWarmup != null) {
                          repo.updateTemplateSet(sets[i].id, isWarmup: selection.isWarmup);
                        } else {
                          repo.updateTemplateSet(
                            sets[i].id,
                            setType: selection.type.id,
                            setTypeMetaJson: selection.metaJson,
                            clearMetaJson: selection.metaJson == null,
                          );
                        }
                      },
                      onUpdateWeight: (kg) => repo.updateTemplateSet(sets[i].id, targetWeightKg: kg),
                      onUpdateReps: (reps) => repo.updateTemplateSet(sets[i].id, targetReps: reps),
                      onDelete: () => repo.deleteTemplateSet(sets[i].id),
                    ),
                ],
              );
            },
            loading: () => const SizedBox(height: 32, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Text('Error loading sets: $e'),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Set'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => repo.addTemplateSet(templateExerciseId: te.id),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Interactive Set Row (Empty Workout style) ───────────────────────────────

class _TemplateSetRow extends StatefulWidget {
  final int index;
  final TemplateSetData set;
  final Function(SetTypeSelection) onUpdateSetType;
  final Function(double?) onUpdateWeight;
  final Function(int?) onUpdateReps;
  final VoidCallback onDelete;

  const _TemplateSetRow({
    super.key,
    required this.index,
    required this.set,
    required this.onUpdateSetType,
    required this.onUpdateWeight,
    required this.onUpdateReps,
    required this.onDelete,
  });

  @override
  State<_TemplateSetRow> createState() => _TemplateSetRowState();
}

class _TemplateSetRowState extends State<_TemplateSetRow> {
  late final TextEditingController _weightCtrl;
  late final TextEditingController _repsCtrl;

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController(
      text: (widget.set.targetWeightKg != null && widget.set.targetWeightKg! > 0)
          ? widget.set.targetWeightKg!.toStringAsFixed(widget.set.targetWeightKg! % 1 == 0 ? 0 : 1)
          : '',
    );
    _repsCtrl = TextEditingController(
      text: widget.set.targetReps != null ? widget.set.targetReps!.toString() : '',
    );
  }

  @override
  void didUpdateWidget(covariant _TemplateSetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.set.targetWeightKg != widget.set.targetWeightKg) {
      final text = (widget.set.targetWeightKg != null && widget.set.targetWeightKg! > 0)
          ? widget.set.targetWeightKg!.toStringAsFixed(widget.set.targetWeightKg! % 1 == 0 ? 0 : 1)
          : '';
      if (_weightCtrl.text != text) _weightCtrl.text = text;
    }
    if (oldWidget.set.targetReps != widget.set.targetReps) {
      final text = widget.set.targetReps != null ? widget.set.targetReps!.toString() : '';
      if (_repsCtrl.text != text) _repsCtrl.text = text;
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final setType = SetType.fromId(widget.set.setType);
    final isWarmup = widget.set.isWarmup;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // Set index badge
          SizedBox(
            width: 32,
            child: Center(
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isWarmup
                      ? Colors.orange.withValues(alpha: 0.2)
                      : AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${widget.index}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isWarmup ? Colors.orange : AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Set type selector button
          SizedBox(
            width: 48,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final selection = await SetTypeMenu.show(
                  context,
                  current: setType,
                  isWarmup: isWarmup,
                );
                if (selection != null) {
                  widget.onUpdateSetType(selection);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isWarmup
                      ? Colors.orange.withValues(alpha: 0.15)
                      : (setType != SetType.standard
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : AppColors.surfaceContainer),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isWarmup
                        ? Colors.orange.withValues(alpha: 0.4)
                        : (setType != SetType.standard
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : AppColors.outlineVariant.withValues(alpha: 0.4)),
                  ),
                ),
                child: Center(
                  child: isWarmup
                      ? const Icon(Icons.local_fire_department, size: 14, color: Colors.orange)
                      : Text(
                          setType == SetType.standard ? '—' : SetTypeMenu.badge(setType),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: setType != SetType.standard ? AppColors.primary : AppColors.secondary,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Target Weight input
          Expanded(
            child: TextField(
              controller: _weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'kg',
                filled: true,
                fillColor: AppColors.surfaceContainer,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              onChanged: (val) {
                final parsed = double.tryParse(val.trim().replaceAll(',', '.'));
                widget.onUpdateWeight(parsed);
              },
            ),
          ),
          const SizedBox(width: 8),
          // Target Reps input
          Expanded(
            child: TextField(
              controller: _repsCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'reps',
                filled: true,
                fillColor: AppColors.surfaceContainer,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              onChanged: (val) {
                final parsed = int.tryParse(val.trim());
                widget.onUpdateReps(parsed);
              },
            ),
          ),
          const SizedBox(width: 4),
          // Delete set button
          IconButton(
            icon: Icon(Icons.close, size: 16, color: AppColors.secondary),
            onPressed: widget.onDelete,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ── Set count picker (item 6) ───────────────────────────────────────────────

/// Small tappable "Sets: N" chip that opens [_pickSetCount].
class _SetsCountChip extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback onTap;
  const _SetsCountChip({required this.label, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: AppColors.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              '$label: $count',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog for typing an exact set count (e.g. "20" instead of tapping
/// "Add Set" twenty times) — feeds [TemplatesRepository.updateTemplateExercise]
/// or the add-time default.
Future<int?> _pickSetCount(
  BuildContext context, {
  required int current,
  String title = 'Number of Sets',
}) {
  final ctrl = TextEditingController(text: current.toString());
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'e.g. 20'),
        onSubmitted: (v) => Navigator.of(ctx).pop(int.tryParse(v)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(int.tryParse(ctrl.text)),
          child: const Text('Set'),
        ),
      ],
    ),
  );
}

// ── Shared widgets ───────────────────────────────────────────────────────────

class _PillField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  const _PillField({required this.label, required this.controller, required this.hint, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.surfaceContainer,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
      ],
    );
  }
}

class _FolderChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _FolderChip({required this.label, required this.emoji, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Text(
          '$emoji $label',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.onSurfaceVariant),
        ),
      ),
    );
  }
}
