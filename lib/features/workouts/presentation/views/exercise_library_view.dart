import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/presentation/views/custom_exercise_builder_view.dart';
import 'package:herculex/features/workouts/presentation/widgets/exercise_artwork.dart';

const _exerciseLibraryFilterChips = <String>[
  'All',
  'Custom',
  'Chest',
  'Back',
  'Shoulders',
  'Biceps',
  'Triceps',
  'Legs',
  'Quads',
  'Hamstrings',
  'Glutes',
  'Calves',
  'Core',
  'Abs',
  'Forearms',
  'Compound',
  'Isolation',
  'Push',
  'Pull',
  'Cardio',
  'Calisthenics',
];

class ExerciseLibraryView extends ConsumerStatefulWidget {
  const ExerciseLibraryView({super.key});

  @override
  ConsumerState<ExerciseLibraryView> createState() =>
      _ExerciseLibraryViewState();
}

class _ExerciseLibraryViewState extends ConsumerState<ExerciseLibraryView> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _category;
  Timer? _debounce;

  static const _debounceDelay = Duration(milliseconds: 180);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final text = _searchCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _query = '');
      return;
    }
    _debounce = Timer(_debounceDelay, () {
      if (mounted) setState(() => _query = text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    // When "Custom" is selected, we query without a facet category and filter in-memory.
    final effectiveCategory = _category == 'Custom' ? null : _category;
    final exercisesAsync = ref.watch(
      exerciseSearchProvider(
        ExerciseCatalogFilter(query: _query, category: effectiveCategory),
      ),
    );

    final usageCounts =
        ref.watch(exerciseUsageCountsProvider).asData?.value ??
        const <int, int>{};

    return HxScreenShell(
      title: 'Exercise Library',
      titleIcon: Icons.fitness_center,
      actions: [
        IconButton(
          tooltip: 'Add Custom Exercise',
          icon: Icon(Icons.add_rounded, color: hx.primary),
          onPressed: () async {
            final created = await CustomExerciseBuilderView.show(context);
            if (created != null && context.mounted) {
              context.push(AppPaths.exercise(created.id));
            }
          },
        ),
      ],
      children: [
        // ── Search field ──────────────────────────────────────────────────
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Search exercises by name, muscle, equipment…',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Category / Filter Chips ──────────────────────────────────────
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _exerciseLibraryFilterChips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final c = _exerciseLibraryFilterChips[index];
              final isSelected =
                  (c == 'All' && _category == null) || _category == c;
              return FilterChip(
                label: Text(
                  c,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.secondary,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                selected: isSelected,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceContainer,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                onSelected: (_) {
                  setState(() {
                    _category = c == 'All' ? null : c;
                  });
                },
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // ── Exercise List ─────────────────────────────────────────────────
        exercisesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Failed to load exercises: $err')),
          ),
          data: (list) {
            var filtered = [...list];
            if (_category == 'Custom') {
              filtered = filtered.where((e) => e.isCustom).toList();
            }

            if (_query.isEmpty) {
              filtered.sort((a, b) {
                final countA = usageCounts[a.id] ?? 0;
                final countB = usageCounts[b.id] ?? 0;
                if (countA != countB) {
                  return countB.compareTo(countA);
                }
                final tierA = _exercisePopularityTier(a);
                final tierB = _exercisePopularityTier(b);
                if (tierA != tierB) {
                  return tierA.compareTo(tierB);
                }
                return a.name.compareTo(b.name);
              });
            }

            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fitness_center_rounded,
                        size: 48,
                        color: hx.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _category == 'Custom'
                            ? 'No custom exercises yet'
                            : 'No exercises found',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: hx.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _category == 'Custom'
                            ? 'Tap the + button to create your own custom exercise.'
                            : 'Try adjusting your search query or filter chips.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hx.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 4),
                  child: Text(
                    '${filtered.length} ${filtered.length == 1 ? 'exercise' : 'exercises'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hx.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final exercise = filtered[index];
                    return _ExerciseLibraryTile(
                      exercise: exercise,
                      onTap: () => context.push(AppPaths.exercise(exercise.id)),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ExerciseLibraryTile extends ConsumerWidget {
  final ExerciseCatalogData exercise;
  final VoidCallback onTap;

  const _ExerciseLibraryTile({required this.exercise, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final affinity =
        ref.watch(exerciseAffinityProvider(exercise.id)).asData?.value ??
        ExerciseAffinity.okay;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                ExerciseArtwork(exercise: exercise, size: 48, radius: 12),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${exercise.primaryMuscle} • ${exercise.equipment}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.secondary,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          _AffinityBadge(affinity: affinity),
                          if (exercise.isCustom)
                            const _SmallBadge(label: 'Custom'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: hx.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AffinityBadge extends StatelessWidget {
  const _AffinityBadge({required this.affinity});

  final ExerciseAffinity affinity;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (affinity) {
      ExerciseAffinity.never => (Colors.redAccent, Icons.block_rounded),
      ExerciseAffinity.okay => (AppColors.secondary, Icons.check_rounded),
      ExerciseAffinity.liked => (Colors.pinkAccent, Icons.favorite_rounded),
      ExerciseAffinity.core => (Colors.amber.shade800, Icons.star_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            affinity.label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.hx.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Assigns a popularity tier for catalog browse sorting.
///
/// Tier 1: Universal core staples (Big 3 lifts, pull-ups, rows, curls, dips...)
/// Tier 2: Highly popular gym movements (dumbbell presses, extensions, cable work...)
/// Tier 3: Compound exercises
/// Tier 4: Other / niche variations
int _exercisePopularityTier(ExerciseCatalogData e) {
  final nameLower = e.name.toLowerCase();

  const tier1Names = {
    'barbell bench press',
    'bench press',
    'back squat',
    'squat',
    'deadlift',
    'barbell deadlift',
    'overhead press',
    'barbell overhead press',
    'pull-up',
    'pull up',
    'lat pulldown',
    'barbell row',
    'incline dumbbell press',
    'romanian deadlift',
    'leg press',
    'dumbbell curl',
    'lateral raise',
    'dumbbell lateral raise',
    'cable triceps pushdown',
    'triceps pushdown',
    'dips',
  };

  const tier2Names = {
    'dumbbell bench press',
    'incline barbell press',
    'machine chest press',
    'cable fly',
    'push-up',
    'front squat',
    'bulgarian split squat',
    'leg extension',
    'lying leg curl',
    'seated leg curl',
    'hip thrust',
    'walking lunge',
    'seated cable row',
    'dumbbell row',
    'face pull',
    'seated dumbbell press',
    'cable lateral raise',
    'rear delt fly',
    'barbell curl',
    'hammer curl',
    'overhead triceps extension',
    'skullcrusher',
    'plank',
    'hanging leg raise',
    'cable crunch',
    'standing calf raise',
    'preacher curl',
    'incline curl',
    't-bar row',
    'hack squat',
  };

  if (tier1Names.contains(nameLower)) return 1;
  if (tier2Names.contains(nameLower)) return 2;
  if (e.mechanics == 'compound') return 3;
  return 4;
}
