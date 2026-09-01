import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/presentation/circuit_builder_view.dart';
import 'package:herculex/features/workouts/presentation/circuits_providers.dart';
import 'package:herculex/features/workouts/presentation/custom_exercise_builder_view.dart';
import 'package:herculex/features/workouts/presentation/equipment_icon.dart';
import 'package:herculex/features/workouts/presentation/exercise_ai_scan_dialog.dart';
import 'package:herculex/features/workouts/presentation/exercise_artwork.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';
import 'package:herculex/theme/colors.dart';

/// Result from [ExercisePickerSheet.show]. [equipmentAlreadyChosen] is true
/// when the user picked from a multi-variant family style chooser, meaning the
/// equipment is already encoded in the catalog entry and a second equipment
/// prompt would be redundant.
class ExercisePickResult {
  final ExerciseCatalogData exercise;
  final bool equipmentAlreadyChosen;
  final String? equipmentVariant;
  final int? circuitId;
  final int? circuitRounds;
  final int? circuitRestSeconds;
  final int? targetReps;
  final double? targetWeightKg;

  const ExercisePickResult({
    required this.exercise,
    this.equipmentAlreadyChosen = false,
    this.equipmentVariant,
    this.circuitId,
    this.circuitRounds,
    this.circuitRestSeconds,
    this.targetReps,
    this.targetWeightKg,
  });
}

const exercisePickerFilterChips = <String>[
  'Recent',
  'Circuits',
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
  'CrossFit',
];

/// Display name for a collapsed movement group, e.g. the barbell/dumbbell/
/// cable variants of a curl all render under "Bicep Curl".
///
/// Deliberately independent of the order [variants] arrives in: search ranking
/// reorders groups, and a label that changed per query would read as a
/// different exercise.
String exerciseFamilyLabel(List<ExerciseCatalogData> variants) =>
    _FamilyTile.familyLabel(variants);

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

  static Future<List<ExercisePickResult>?> show(BuildContext context) async {
    final raw = await showModalBottomSheet<List<ExercisePickResult>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ExercisePickerSheet(),
    );
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  @override
  ConsumerState<ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<ExercisePickerSheet> {
  String _query = '';
  String? _category;
  final _ctrl = TextEditingController();
  Timer? _debounce;
  final _selectedMap = <int, ExercisePickResult>{};

  /// Long enough to coalesce a burst of typing, short enough that the list
  /// still feels live. Debouncing here rather than in the provider keeps the
  /// provider synchronous and directly testable.
  static const _debounceDelay = Duration(milliseconds: 180);

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    // Clearing the field should feel instant; only typing is debounced.
    if (value.isEmpty) {
      setState(() => _query = '');
      return;
    }
    _debounce = Timer(_debounceDelay, () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _toggleSelection(
    ExerciseCatalogData exercise,
    bool equipmentAlreadyChosen, {
    String? equipmentVariant,
  }) {
    setState(() {
      if (_selectedMap.containsKey(exercise.id)) {
        _selectedMap.remove(exercise.id);
      } else {
        _selectedMap[exercise.id] = ExercisePickResult(
          exercise: exercise,
          equipmentAlreadyChosen: equipmentAlreadyChosen,
          equipmentVariant: equipmentVariant,
        );
      }
    });
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
      // Authored movement first; the derived family remains the fallback for
      // rows the movement layer does not cover yet (and for custom rows).
      final fam = e.movementSlug ?? e.movementFamily;
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
      exerciseSearchProvider(
        ExerciseCatalogFilter(
          query: _query,
          category: _category == 'Circuits' ? null : _category,
        ),
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
        child: Stack(
          children: [
            Column(
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
                            Navigator.of(context).pop([
                              ExercisePickResult(
                                exercise: created,
                                equipmentAlreadyChosen: false,
                              ),
                            ]);
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
                    onChanged: _onQueryChanged,
                    decoration: InputDecoration(
                      hintText: 'Search exercises…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: AppColors.surfaceVariant,
                      suffixIcon: IconButton(
                        icon: Icon(
                          Icons.camera_alt_outlined,
                          color: AppColors.primary,
                        ),
                        tooltip: 'Gemini AI: Skeniraj napravo / vajo',
                        onPressed: () async {
                          final match = await ExerciseAiScanDialog.show(
                            context,
                          );
                          if (context.mounted && match != null) {
                            Navigator.of(context).pop([
                              ExercisePickResult(
                                exercise: match,
                                equipmentAlreadyChosen: false,
                                equipmentVariant: null,
                              ),
                            ]);
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
                  child: _category == 'Circuits'
                      ? _CircuitsPickerList(
                          controller: controller,
                          query: _query,
                        )
                      : exercises.when(
                          data: (list) {
                            final recentIds =
                                recentIdsAsync.asData?.value ?? <int>{};
                            var filteredList = list;
                            if (_category == 'Recent') {
                              filteredList = list
                                  .where((e) => recentIds.contains(e.id))
                                  .toList();
                            } else if (recentIds.isNotEmpty && _query.isEmpty) {
                              // Recency only orders the unfiltered browse list. While a
                              // query is typed, relevance wins — otherwise any of the 50
                              // recent exercises outranks an exact name match.
                              filteredList = sortRecentExercisesFirst(
                                list,
                                recentIds,
                              );
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
                              padding: EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                _selectedMap.isNotEmpty ? 90 : 32,
                              ),
                              itemCount: groups.length,
                              itemBuilder: (_, i) {
                                final g = groups[i];
                                if (g.length == 1) {
                                  final isSelected = _selectedMap.containsKey(
                                    g.first.id,
                                  );
                                  return _ExerciseTile(
                                    exercise: g.first,
                                    isSelected: isSelected,
                                    onTap: () =>
                                        _toggleSelection(g.first, false),
                                  );
                                }
                                final selectedCount = g
                                    .where(
                                      (v) => _selectedMap.containsKey(v.id),
                                    )
                                    .length;
                                return _FamilyTile(
                                  variants: g,
                                  selectedCount: selectedCount,
                                  onPick: (picked, {variant}) =>
                                      _toggleSelection(
                                        picked,
                                        true,
                                        equipmentVariant: variant,
                                      ),
                                );
                              },
                            );
                          },
                          error: (e, _) =>
                              Center(child: Text('Failed to load: $e')),
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                        ),
                ),
              ],
            ),
            if (_selectedMap.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(_selectedMap.values.toList());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                        elevation: 6,
                      ),
                      child: Text(
                        'Add ${_selectedMap.length} ${_selectedMap.length == 1 ? "exercise" : "exercises"}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
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
  final int selectedCount;
  final void Function(ExerciseCatalogData exercise, {String? variant}) onPick;
  const _FamilyTile({
    required this.variants,
    required this.selectedCount,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = familyLabel(variants);
    final styles = variants.map((v) => v.equipment).toSet().toList();
    final isSelected = selectedCount > 0;
    final bgColor = isSelected
        ? AppColors.primaryContainer.withValues(alpha: 0.35)
        : AppColors.surfaceContainerLowest;
    final borderColor = isSelected
        ? AppColors.primary
        : AppColors.outlineVariant.withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          final picked = await _StyleChooserSheet.show(
            context,
            label,
            variants,
          );
          if (picked != null) {
            onPick(picked.exercise, variant: picked.variant);
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              ExerciseArtwork(
                // The default picture is the family's first (base) style, but
                // fall through to the first style that actually has artwork so
                // a missing base illustration does not blank the whole family.
                exercise: variants.firstWhere(
                  (v) => exerciseArtworkAsset(v) != null,
                  orElse: () => variants.first,
                ),
                size: 48,
                radius: 10,
                fallbackColor: isSelected
                    ? AppColors.primary
                    : AppColors.primaryContainer.withValues(alpha: 0.35),
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
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isSelected
                      ? '$selectedCount selected'
                      : '${variants.length} styles',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isSelected ? Colors.white : AppColors.secondary,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
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

  /// See [exerciseFamilyLabel]. Picks the plainest cleaned variant name rather
  /// than the first, so the label does not shift when ranking reorders the
  /// group.
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

    final cleaned = variants
        .map((v) => clean(v.name))
        .where((n) => n.isNotEmpty)
        .toList();
    final base = cleaned.isEmpty
        ? ''
        : cleaned.reduce((a, b) {
            final byWords = a.split(' ').length.compareTo(b.split(' ').length);
            if (byWords != 0) return byWords < 0 ? a : b;
            final byLength = a.length.compareTo(b.length);
            if (byLength != 0) return byLength < 0 ? a : b;
            return a.compareTo(b) <= 0 ? a : b;
          });
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

  static Future<({ExerciseCatalogData exercise, String? variant})?> show(
    BuildContext context,
    String movement,
    List<ExerciseCatalogData> variants,
  ) {
    return showModalBottomSheet<
      ({ExerciseCatalogData exercise, String? variant})
    >(
      context: context,
      isScrollControlled: true,
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
    final maxHeight = MediaQuery.of(context).size.height * 0.70;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
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
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final v in variants)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _StyleOption(
                              equipmentVariant: v.equipment,
                              exercise: v,
                              label: v.equipment,
                              subtitle: v.name,
                              onTap: () => Navigator.of(
                                context,
                              ).pop((exercise: v, variant: v.modality)),
                            ),
                          ),
                        if (weightedBase != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _StyleOption(
                              equipmentVariant: 'weighted',
                              exercise: weightedBase,
                              label: 'Weighted',
                              subtitle: '${weightedBase.name} + added load',
                              onTap: () => Navigator.of(context).pop((
                                exercise: weightedBase,
                                variant: 'weighted',
                              )),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleOption extends StatelessWidget {
  final String equipmentVariant;

  /// The catalog row behind this style, so the thumbnail shows the illustration
  /// for *this* equipment rather than a generic glyph.
  final ExerciseCatalogData? exercise;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _StyleOption({
    required this.equipmentVariant,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.exercise,
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
            if (exercise != null)
              ExerciseArtwork(
                exercise: exercise!,
                size: 44,
                radius: 8,
                equipmentVariant: equipmentVariant,
              )
            else
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
                alignment: Alignment.center,
                child: EquipmentGlyph(
                  variant: equipmentVariant,
                  size: 22,
                  color: AppColors.primary,
                ),
              ),
            const SizedBox(width: 14),
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
  final bool isSelected;
  final VoidCallback onTap;
  const _ExerciseTile({
    required this.exercise,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = isSelected
        ? AppColors.primaryContainer.withValues(alpha: 0.35)
        : AppColors.surfaceContainerLowest;
    final borderColor = isSelected
        ? AppColors.primary
        : AppColors.outlineVariant.withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  ExerciseArtwork(
                    exercise: exercise,
                    size: 48,
                    radius: 10,
                    fallbackColor: isSelected
                        ? AppColors.primary
                        : AppColors.primaryContainer.withValues(alpha: 0.35),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.outline,
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : Icon(Icons.add, color: AppColors.outline, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Circuits Picker List ───────────────────────────────────────────────────

class _CircuitsPickerList extends ConsumerWidget {
  final ScrollController controller;
  final String query;

  const _CircuitsPickerList({required this.controller, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final circuitsAsync = ref.watch(workoutCircuitsProvider);

    return circuitsAsync.when(
      data: (circuits) {
        final filtered = query.trim().isEmpty
            ? circuits
            : circuits
                  .where(
                    (c) => c.name.toLowerCase().contains(query.toLowerCase()),
                  )
                  .toList();

        if (filtered.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.repeat_rounded,
                    size: 48,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    circuits.isEmpty
                        ? 'No circuits created yet'
                        : 'No circuits match "$query"',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Create circuits to perform sequential giant supersets with round pauses.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Create Circuit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () async {
                      final created = await CircuitBuilderView.show(context);
                      if (created != null && context.mounted) {
                        final repo = ref.read(circuitsRepositoryProvider);
                        final exList = await repo.getCircuitExercises(
                          created.id,
                        );
                        final snapshot = await ref
                            .read(workoutsRepositoryProvider)
                            .watchExerciseCatalog()
                            .first;
                        final catMap = {
                          for (final c in snapshot.exercises) c.id: c,
                        };
                        final results = exList.map((ce) {
                          final cat =
                              catMap[ce.exerciseId] ??
                              ExerciseCatalogData(
                                id: ce.exerciseId,
                                name: 'Exercise #${ce.exerciseId}',
                                primaryMuscle: '',
                                equipment: '',
                                mechanics: '',
                                force: '',
                                plane: '',
                                defaultRestSeconds: 90,
                                isCustom: false,
                                category: 'strength',
                                modality: 'barbell',
                                cnsScore: 3,
                                recoveryImpact: 3,
                                loggingMetric: 'weight_reps',
                                supportsWeightedBodyweight: false,
                                isReviewed: false,
                              );
                          return ExercisePickResult(
                            exercise: cat,
                            circuitId: created.id,
                            circuitRounds: created.rounds,
                            circuitRestSeconds: created.restSeconds,
                            targetReps: ce.targetReps,
                            targetWeightKg: ce.targetWeightKg,
                          );
                        }).toList();
                        if (context.mounted) {
                          Navigator.of(context).pop(results);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final circuit = filtered[index];
            return _CircuitPickerCard(circuit: circuit);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load circuits: $e')),
    );
  }
}

class _CircuitPickerCard extends ConsumerWidget {
  final WorkoutCircuitData circuit;

  const _CircuitPickerCard({required this.circuit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final exercisesAsync = ref.watch(circuitExercisesProvider(circuit.id));
    final exercises = exercisesAsync.asData?.value ?? [];

    final restFormatted = circuit.restSeconds >= 60
        ? '${circuit.restSeconds ~/ 60}m${circuit.restSeconds % 60 > 0 ? ' ${circuit.restSeconds % 60}s' : ''}'
        : '${circuit.restSeconds}s';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
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
                  color: AppColors.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.repeat_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            circuit.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'CIRCUIT',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${exercises.length} exercises • ${circuit.rounds} rounds • $restFormatted pause',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  minimumSize: const Size(60, 32),
                ),
                onPressed: () async {
                  final repo = ref.read(circuitsRepositoryProvider);
                  final exList = await repo.getCircuitExercises(circuit.id);
                  final snapshot = await ref
                      .read(workoutsRepositoryProvider)
                      .watchExerciseCatalog()
                      .first;
                  final catMap = {for (final c in snapshot.exercises) c.id: c};
                  final results = exList.map((ce) {
                    final cat =
                        catMap[ce.exerciseId] ??
                        ExerciseCatalogData(
                          id: ce.exerciseId,
                          name: 'Exercise #${ce.exerciseId}',
                          primaryMuscle: '',
                          equipment: '',
                          mechanics: '',
                          force: '',
                          plane: '',
                          defaultRestSeconds: 90,
                          isCustom: false,
                          category: 'strength',
                          modality: 'barbell',
                          cnsScore: 3,
                          recoveryImpact: 3,
                          loggingMetric: 'weight_reps',
                          supportsWeightedBodyweight: false,
                          isReviewed: false,
                        );
                    return ExercisePickResult(
                      exercise: cat,
                      circuitId: circuit.id,
                      circuitRounds: circuit.rounds,
                      circuitRestSeconds: circuit.restSeconds,
                      targetReps: ce.targetReps,
                      targetWeightKg: ce.targetWeightKg,
                    );
                  }).toList();
                  if (context.mounted) {
                    Navigator.of(context).pop(results);
                  }
                },
                child: const Text(
                  'Add',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          if (circuit.notes != null && circuit.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              circuit.notes!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
