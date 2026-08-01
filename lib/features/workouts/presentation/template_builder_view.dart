import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../widgets/premium_button.dart';
import 'exercise_picker_sheet.dart';
import 'workouts_providers.dart';

class TemplateBuilderView extends ConsumerStatefulWidget {
  final WorkoutTemplateData? existing;
  final int? initialFolderId;

  const TemplateBuilderView({super.key, this.existing, this.initialFolderId});

  static Future<WorkoutTemplateData?> show(
    BuildContext context, {
    WorkoutTemplateData? existing,
    int? initialFolderId,
  }) {
    return Navigator.push<WorkoutTemplateData>(
      context,
      MaterialPageRoute(
        builder: (_) => TemplateBuilderView(
          existing: existing,
          initialFolderId: initialFolderId,
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
              onPressed: () => _save(widget.existing!),
              child: Text('Save', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: templateId == null
          ? _CreateForm(
              nameCtrl: _name,
              notesCtrl: _notes,
              initialFolderId: widget.initialFolderId,
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
  const _CreateForm({required this.nameCtrl, required this.notesCtrl, this.initialFolderId});

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
              MaterialPageRoute(builder: (_) => TemplateBuilderView(existing: template)),
            );
          },
        ),
      ],
    );
  }
}

// ── Edit body (template exists — add/reorder exercises) ─────────────────────

class _EditBody extends ConsumerWidget {
  final WorkoutTemplateData template;
  final TextEditingController nameCtrl;
  final TextEditingController notesCtrl;

  const _EditBody({required this.template, required this.nameCtrl, required this.notesCtrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final exercisesAsync = ref.watch(templateExercisesProvider(template.id));
    final catalogAsync = ref.watch(exerciseCatalogProvider(const ExerciseCatalogFilter()));
    final repo = ref.read(templatesRepositoryProvider);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            children: [
              _PillField(label: 'Name', controller: nameCtrl, hint: 'Template name'),
              const SizedBox(height: 14),
              _PillField(label: 'Notes', controller: notesCtrl, hint: 'Optional description', maxLines: 2),
              const SizedBox(height: 28),
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
                    child: TextButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                      onPressed: () async {
                        final picked = await ExercisePickerSheet.show(context);
                        if (picked == null || !context.mounted) return;
                        final target = await _TargetConfigSheet.show(
                          context,
                          exerciseName: picked.exercise.name,
                        );
                        if (target == null || !context.mounted) return;
                        await repo.addExerciseToTemplate(
                          templateId: template.id,
                          exerciseId: picked.exercise.id,
                          targetSets: target.sets,
                          targetRepsMin: target.repsMin,
                          targetRepsMax: target.repsMax,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                          Text('Tap Add to build your template', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final te in rows)
                        _TemplateExerciseTile(
                          te: te,
                          exerciseName: catalogAsync.asData?.value
                              .firstWhere((e) => e.id == te.exerciseId, orElse: () => _placeholder(te.exerciseId))
                              .name ?? '…',
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

class _TemplateExerciseTile extends StatelessWidget {
  final TemplateExerciseData te;
  final String exerciseName;
  final VoidCallback onRemove;

  const _TemplateExerciseTile({required this.te, required this.exerciseName, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
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
                  Text(exerciseName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${te.targetSets} sets'
                    '${te.targetRepsMin != null ? ' · ${te.targetRepsMin}–${te.targetRepsMax ?? te.targetRepsMin} reps' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: AppColors.secondary),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Target sets/reps config sheet ────────────────────────────────────────────

typedef _TargetConfig = ({int sets, int? repsMin, int? repsMax});

class _TargetConfigSheet extends StatefulWidget {
  final String exerciseName;
  const _TargetConfigSheet({required this.exerciseName});

  static Future<_TargetConfig?> show(
    BuildContext context, {
    required String exerciseName,
  }) {
    return showModalBottomSheet<_TargetConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TargetConfigSheet(exerciseName: exerciseName),
    );
  }

  @override
  State<_TargetConfigSheet> createState() => _TargetConfigSheetState();
}

class _TargetConfigSheetState extends State<_TargetConfigSheet> {
  final _setsCtrl = TextEditingController();
  final _repsMinCtrl = TextEditingController();
  final _repsMaxCtrl = TextEditingController();

  @override
  void dispose() {
    _setsCtrl.dispose();
    _repsMinCtrl.dispose();
    _repsMaxCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final sets = int.tryParse(_setsCtrl.text.trim());
    if (sets == null || sets < 1) return;
    final repsMin = int.tryParse(_repsMinCtrl.text.trim());
    final repsMax = int.tryParse(_repsMaxCtrl.text.trim());
    Navigator.of(context).pop<_TargetConfig>((
      sets: sets,
      repsMin: repsMin,
      repsMax: (repsMax != null && repsMax > (repsMin ?? 0)) ? repsMax : repsMin,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor ?? AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outlineVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(widget.exerciseName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Set your targets', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _NumField(label: 'Sets *', controller: _setsCtrl, hint: 'e.g. 4'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NumField(label: 'Reps (min)', controller: _repsMinCtrl, hint: 'e.g. 6'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NumField(label: 'Reps (max)', controller: _repsMaxCtrl, hint: 'e.g. 10'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          side: BorderSide(color: AppColors.outlineVariant),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Add to Template'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  const _NumField({required this.label, required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.secondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.surfaceContainer,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
      ],
    );
  }
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
