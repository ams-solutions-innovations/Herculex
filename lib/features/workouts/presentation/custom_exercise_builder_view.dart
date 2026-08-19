import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../domain/logging_metric.dart';
import 'workouts_providers.dart';

/// Full-screen builder for a fully-attributed custom exercise. Returns the
/// created [ExerciseCatalogData] when popped, so callers (e.g. the exercise
/// picker) can immediately use it.
class CustomExerciseBuilderView extends ConsumerStatefulWidget {
  const CustomExerciseBuilderView({super.key});

  static Future<ExerciseCatalogData?> show(BuildContext context) {
    return Navigator.of(context).push<ExerciseCatalogData>(
      MaterialPageRoute(builder: (_) => const CustomExerciseBuilderView()),
    );
  }

  @override
  ConsumerState<CustomExerciseBuilderView> createState() =>
      _CustomExerciseBuilderViewState();
}

const _muscles = [
  'Chest', 'Lats', 'Rhomboids', 'Traps', 'Erectors',
  'Front Delts', 'Side Delts', 'Rear Delts',
  'Biceps', 'Brachialis', 'Triceps', 'Forearms',
  'Quads', 'Hamstrings', 'Glutes', 'Adductors', 'Abductors',
  'Calves', 'Tibialis', 'Abs', 'Obliques', 'Hip Flexors', 'Neck', 'Serratus',
];
const _categories = [
  'strength', 'hypertrophy', 'powerlifting', 'calisthenics', 'crossfit',
  'cardio', 'mobility',
];
const _modalities = [
  'barbell', 'dumbbell', 'machine_plate', 'machine_selectorized', 'cable',
  'smith', 'kettlebell', 'band', 'bodyweight', 'other',
];
const _patterns = [
  'squat', 'hinge', 'horizontal_push', 'vertical_push', 'horizontal_pull',
  'vertical_pull', 'lunge', 'carry', 'core', 'isolation', 'other',
];
// Derived from the registry rather than restated, because this list had
// already drifted from it: `weight_distance` shipped on Sled Push without ever
// appearing here, so a custom sled variant could not be given the metric its
// seeded counterpart uses.
final _metrics = [for (final m in LoggingMetric.values) m.id];
const _equipmentOptions = [
  'Barbell', 'Dumbbell', 'Cable', 'Machine', 'Smith Machine', 'Bodyweight',
  'Kettlebell', 'Band', 'Plate', 'Rings', 'TRX', 'EZ Bar', 'Trap Bar', 'Other',
];

class _CustomExerciseBuilderViewState
    extends ConsumerState<CustomExerciseBuilderView> {
  final _name = TextEditingController();
  final _aliases = TextEditingController();
  final _attachments = TextEditingController();

  String _category = 'strength';
  String _modality = 'barbell';
  String _equipment = 'Barbell';
  String? _pattern;
  String _metric = 'weight_reps';
  int _cns = 3;
  int _recovery = 3;
  int _rest = 120;
  bool _weightedBw = false;
  bool _saving = false;

  final _primary = <String>{};
  final _secondary = <String>{};
  final _stabilizers = <String>{};

  @override
  void dispose() {
    _name.dispose();
    _aliases.dispose();
    _attachments.dispose();
    super.dispose();
  }

  List<String> _split(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Give the exercise a name.');
      return;
    }
    if (_primary.isEmpty) {
      _snack('Select at least one primary muscle.');
      return;
    }
    setState(() => _saving = true);
    try {
      final created =
          await ref.read(workoutsRepositoryProvider).createCustomExercise(
                name: name,
                primaryMuscles: _primary.toList(),
                secondaryMuscles: _secondary.toList(),
                stabilizers: _stabilizers.toList(),
                category: _category,
                movementPattern: _pattern,
                modality: _modality,
                equipment: _equipment,
                cnsScore: _cns,
                recoveryImpact: _recovery,
                loggingMetric: _metric,
                supportsWeightedBodyweight: _weightedBw,
                attachments: _split(_attachments.text),
                aliases: _split(_aliases.text),
                defaultRestSeconds: _rest,
              );
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      setState(() => _saving = false);
      _snack('Could not save: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Exercise')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _field(_name, 'Name', Icons.fitness_center),
            const SizedBox(height: 12),
            _field(_aliases, 'Alternate names (comma-separated)', Icons.search),
            const SizedBox(height: 20),
            _muscleSection('Primary muscles', _primary, theme),
            _muscleSection('Secondary muscles', _secondary, theme),
            _muscleSection('Stabilizers', _stabilizers, theme),
            const SizedBox(height: 8),
            _dropdown('Category', _category, _categories,
                (v) => setState(() => _category = v!)),
            _dropdown('Modality', _modality, _modalities,
                (v) => setState(() => _modality = v!)),
            _dropdown('Equipment', _equipment, _equipmentOptions,
                (v) => setState(() => _equipment = v!)),
            _dropdown('Movement pattern', _pattern ?? '', ['', ..._patterns],
                (v) => setState(() => _pattern = v!.isEmpty ? null : v),
                labelFor: (v) => v.isEmpty ? '—' : v),
            _dropdown('Logging metric', _metric, _metrics,
                (v) => setState(() => _metric = v!)),
            const SizedBox(height: 8),
            _slider('CNS score', _cns, 1, 10, (v) => setState(() => _cns = v)),
            _slider('Recovery impact', _recovery, 1, 5,
                (v) => setState(() => _recovery = v)),
            _slider('Default rest (sec)', _rest, 30, 300,
                (v) => setState(() => _rest = v),
                divisions: 18, step: 15),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Supports weighted bodyweight'),
              subtitle: const Text('Enables a "+ added weight" field'),
              value: _weightedBw,
              onChanged: (v) => setState(() => _weightedBw = v),
            ),
            const SizedBox(height: 8),
            _field(_attachments, 'Attachments (comma-separated)', Icons.link),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.primary,
          ),
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save exercise'),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _muscleSection(String title, Set<String> sel, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final m in _muscles)
                FilterChip(
                  label: Text(m, style: theme.textTheme.bodySmall),
                  selected: sel.contains(m),
                  onSelected: (on) =>
                      setState(() => on ? sel.add(m) : sel.remove(m)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> options,
      ValueChanged<String?> onChanged,
      {String Function(String)? labelFor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppColors.surfaceContainerLowest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        items: [
          for (final o in options)
            DropdownMenuItem(value: o, child: Text(labelFor?.call(o) ?? o)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _slider(String label, int value, int min, int max,
      ValueChanged<int> onChanged,
      {int? divisions, int step = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $value'),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: divisions ?? (max - min),
          label: '$value',
          onChanged: (v) {
            final snapped = (v / step).round() * step;
            onChanged(snapped.clamp(min, max));
          },
        ),
      ],
    );
  }
}
