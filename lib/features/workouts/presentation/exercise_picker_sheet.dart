import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:image_picker/image_picker.dart';

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../services/ai_service.dart';
import 'custom_exercise_builder_view.dart';
import 'workouts_providers.dart';

/// Result from [ExercisePickerSheet.show]. [equipmentAlreadyChosen] is true
/// when the user picked from a multi-variant family style chooser, meaning the
/// equipment is already encoded in the catalog entry and a second equipment
/// prompt would be redundant.
typedef ExercisePickResult = ({
  ExerciseCatalogData exercise,
  bool equipmentAlreadyChosen,
});

const exercisePickerFilterChips = <String>[
  'Recent',
  'All',
  'Compound',
  'Isolation',
  'Push',
  'Pull',
  'Chest',
  'Back',
  'Lats',
  'Legs',
  'Quads',
  'Hamstrings',
  'Glutes',
  'Shoulders',
  'Biceps',
  'Triceps',
  'Forearms',
  'Core',
  'Abs',
  'Obliques',
  'Calves',
  'Adductors',
  'Abductors',
  'Traps',
  'Rear Delts',
  'Side Delts',
  'Front Delts',
  'Calisthenics',
  'Cardio',
  'Mobility',
];

List<ExerciseCatalogData> sortRecentExercisesFirst(
  List<ExerciseCatalogData> exercises,
  Set<int> recentIds,
) {
  if (recentIds.isEmpty) return exercises;
  return [...exercises]..sort((a, b) {
    final aRecent = recentIds.contains(a.id);
    final bRecent = recentIds.contains(b.id);
    if (aRecent != bRecent) return aRecent ? -1 : 1;
    return a.name.compareTo(b.name);
  });
}

class ExercisePickerSheet extends ConsumerStatefulWidget {
  const ExercisePickerSheet({super.key});

  static Future<ExercisePickResult?> show(BuildContext context) async {
    final raw = await showModalBottomSheet<(ExerciseCatalogData, bool)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ExercisePickerSheet(),
    );
    if (raw == null) return null;
    return (exercise: raw.$1, equipmentAlreadyChosen: raw.$2);
  }

  @override
  ConsumerState<ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<ExercisePickerSheet> {
  String _query = '';
  String? _category;
  bool _isScanningAi = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Collapses equipment variants of the same movement into one group while
  /// preserving the catalog's alphabetical order: a group takes the position of
  /// its first-seen member, and rows without a family stay standalone. Each
  /// group's variants are ordered with the base/free-weight option first.
  List<List<ExerciseCatalogData>> _groupByFamily(
    List<ExerciseCatalogData> list,
  ) {
    final groups = <List<ExerciseCatalogData>>[];
    final byFamily = <String, List<ExerciseCatalogData>>{};
    for (final e in list) {
      final fam = e.movementFamily;
      if (fam == null) {
        groups.add([e]);
        continue;
      }
      final existing = byFamily[fam];
      if (existing == null) {
        final group = <ExerciseCatalogData>[e];
        byFamily[fam] = group;
        groups.add(group);
      } else {
        existing.add(e);
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercises = ref.watch(
      exerciseCatalogProvider(
        ExerciseCatalogFilter(query: _query, category: _category),
      ),
    );
    final recentIdsAsync = ref.watch(recentExerciseIdsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.bottomSheetTheme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add Exercise',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Custom'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                    onPressed: () async {
                      final created = await CustomExerciseBuilderView.show(
                        context,
                      );
                      if (created != null && context.mounted) {
                        Navigator.of(context).pop((created, false));
                      }
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search exercises…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  suffixIcon: _isScanningAi
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: Icon(
                            Icons.document_scanner,
                            color: AppColors.primary,
                          ),
                          tooltip: 'AI: Slikaj mašino/vajo',
                          onPressed: () async {
                            final picker = ImagePicker();
                            final xfile = await picker.pickImage(
                              source: ImageSource.camera,
                            );
                            if (xfile == null) return;

                            setState(() => _isScanningAi = true);
                            try {
                              final ai = ref.read(aiServiceProvider);
                              final match = await ai.identifyExerciseFromImage(
                                xfile,
                              );
                              if (context.mounted && match != null) {
                                Navigator.of(context).pop((match, false));
                              } else if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'AI could not confidently identify this machine.',
                                    ),
                                  ),
                                );
                              }
                            } finally {
                              if (context.mounted) {
                                setState(() => _isScanningAi = false);
                              }
                            }
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ...exercisePickerFilterChips.map((c) {
                    final isSelected = c == 'All'
                        ? _category == null
                        : _category == c;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          c,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : AppColors.secondary,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.surfaceContainer,
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            _category = c == 'All' ? null : c;
                          });
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: exercises.when(
                data: (list) {
                  final recentIds = recentIdsAsync.asData?.value ?? <int>{};
                  var filteredList = list;
                  if (_category == 'Recent') {
                    filteredList = list
                        .where((e) => recentIds.contains(e.id))
                        .toList();
                  } else if (recentIds.isNotEmpty) {
                    filteredList = sortRecentExercisesFirst(list, recentIds);
                  }

                  if (filteredList.isEmpty) {
                    return Center(
                      child: Text(
                        _category == 'Recent'
                            ? 'No recent exercises logged yet'
                            : 'No exercises found',
                        style: theme.textTheme.bodyMedium,
                      ),
                    );
                  }
                  final groups = _groupByFamily(filteredList);
                  return ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: groups.length,
                    itemBuilder: (_, i) {
                      final g = groups[i];
                      if (g.length == 1) {
                        return _ExerciseTile(
                          exercise: g.first,
                          onTap: () =>
                              Navigator.of(context).pop((g.first, false)),
                        );
                      }
                      return _FamilyTile(
                        variants: g,
                        onPick: (picked) =>
                            Navigator.of(context).pop((picked, true)),
                      );
                    },
                  );
                },
                error: (e, _) => Center(child: Text('Failed to load: $e')),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A collapsed movement that has multiple equipment variants. Tapping opens a
/// style chooser; the chosen real catalog row is returned to the picker caller.
class _FamilyTile extends StatelessWidget {
  final List<ExerciseCatalogData> variants;
  final ValueChanged<ExerciseCatalogData> onPick;
  const _FamilyTile({required this.variants, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = familyLabel(variants);
    final styles = variants.map((v) => v.equipment).toSet().toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          final picked = await _StyleChooserSheet.show(
            context,
            label,
            variants,
          );
          if (picked != null) onPick(picked);
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.fitness_center,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${variants.first.primaryMuscle} · ${styles.join(' / ')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${variants.length} styles',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 20, color: AppColors.secondary),
            ],
          ),
        ),
      ),
    );
  }

  /// Display name for the collapsed movement: the shared words across the
  /// variant names with equipment terms removed (e.g. "Incline Press"). Falls
  /// back to the shortest variant name if nothing meaningful remains.
  static String familyLabel(List<ExerciseCatalogData> variants) {
    String clean(String name) {
      var n = ' ${name.toLowerCase()} ';
      for (final t in _equipmentWords) {
        n = n.replaceAll(' $t ', ' ');
      }
      n = n.replaceAll(RegExp(r'\s+'), ' ').trim();
      n = n.replaceAll('bench press', 'press').replaceAll('bench', 'press');
      return n.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    final base = clean(variants.first.name);
    if (base.isEmpty) {
      return variants
          .map((v) => v.name)
          .reduce((a, b) => a.length <= b.length ? a : b);
    }
    // Title-case the cleaned base.
    return base
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  static const _equipmentWords = <String>[
    'swiss bar',
    'safety bar',
    'axle bar',
    'cambered bar',
    'duffalo bar',
    'trap bar',
    'hex bar',
    'ez bar',
    'ez-bar',
    'landmine',
    'meadows',
    'smith machine',
    'smith',
    'machine',
    'cable',
    'band-assisted',
    'banded',
    'band',
    'kettlebell',
    'dumbbell',
    'barbell',
    'plate-loaded',
    'plate',
    'iso-lateral',
    'hammer',
    'pendulum',
    'v-squat',
    'belt squat',
    'sled',
    'yoke',
    'rings',
    'ring',
    'trx',
    'suspension',
    'neck harness',
  ];
}

/// Equipment-style chooser shown after tapping a collapsed movement. Lists the
/// real catalog variants by their equipment label and returns the chosen row.
/// When any bodyweight variant supports weighted execution, a synthetic
/// "Weighted" option is appended (returns the same bodyweight catalog entry —
/// the logging view's weight field activates via [supportsWeightedBodyweight]).
class _StyleChooserSheet extends StatelessWidget {
  final String movement;
  final List<ExerciseCatalogData> variants;
  const _StyleChooserSheet({required this.movement, required this.variants});

  static Future<ExerciseCatalogData?> show(
    BuildContext context,
    String movement,
    List<ExerciseCatalogData> variants,
  ) {
    return showModalBottomSheet<ExerciseCatalogData>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _StyleChooserSheet(movement: movement, variants: variants),
    );
  }

  /// Returns the bodyweight catalog entry that supports weighted execution, if
  /// one exists in this family and no dedicated "weighted" variant is already
  /// present (avoiding a duplicate option).
  ExerciseCatalogData? _weightedBase() {
    final hasWeightedEntry = variants.any(
      (v) =>
          v.name.toLowerCase().contains('weight') ||
          v.equipment.toLowerCase().contains('weight'),
    );
    if (hasWeightedEntry) return null;
    try {
      return variants.firstWhere(
        (v) => v.modality == 'bodyweight' && v.supportsWeightedBodyweight,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weightedBase = _weightedBase();
    return Container(
      decoration: BoxDecoration(
        color:
            theme.bottomSheetTheme.backgroundColor ??
            AppColors.surfaceContainerLowest,
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
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                movement,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text('Choose a style', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              for (final v in variants)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _StyleOption(
                    icon: Icons.fitness_center,
                    label: v.equipment,
                    subtitle: v.name,
                    onTap: () => Navigator.of(context).pop(v),
                  ),
                ),
              if (weightedBase != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _StyleOption(
                    icon: Icons.monitor_weight_outlined,
                    label: 'Weighted',
                    subtitle: '${weightedBase.name} + added load',
                    onTap: () => Navigator.of(context).pop(weightedBase),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _StyleOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.add, size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  final ExerciseCatalogData exercise;
  final VoidCallback onTap;
  const _ExerciseTile({required this.exercise, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.fitness_center,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${exercise.primaryMuscle} · ${exercise.equipment} · ${exercise.mechanics}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
