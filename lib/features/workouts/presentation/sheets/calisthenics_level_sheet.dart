import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/application/calisthenics_providers.dart';
import 'package:herculex/features/workouts/domain/calisthenics_progression.dart';

class CalisthenicsPick {
  const CalisthenicsPick(this.exercise, this.level, this.value, this.load);
  final ExerciseCatalogData exercise;
  final CalisthenicsLevel level;
  final int value;
  final double load;
}

class CalisthenicsLevelSheet extends ConsumerWidget {
  const CalisthenicsLevelSheet({
    super.key,
    required this.path,
    required this.catalog,
  });
  final CalisthenicsPath path;
  final List<ExerciseCatalogData> catalog;

  static Future<CalisthenicsPick?> show(
    BuildContext context,
    CalisthenicsPath path,
    List<ExerciseCatalogData> catalog,
  ) => showModalBottomSheet<CalisthenicsPick>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CalisthenicsLevelSheet(path: path, catalog: catalog),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calisthenicsRecommendationsProvider);
    final recommendation = state.valueOrNull?[path.id];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text(path.label, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            if (state.isLoading) const LinearProgressIndicator(),
            Text(
              recommendation?.reason ??
                  'Choose a comfortable variation. History is unavailable; levels remain selectable.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Levels are movement-specific. Count controlled full-range reps; for unilateral movements, meet the target on each side.',
            ),
            for (final level in path.levels)
              if (catalog.any(
                (e) =>
                    e.slug == level.slug &&
                    (level.variant != 'weighted' ||
                        e.supportsWeightedBodyweight),
              ))
                ListTile(
                  title: Text(level.label),
                  subtitle: Text(
                    '${level.prescription}${recommendation?.target.key == level.key ? ' · Recommended' : ''}',
                  ),
                  trailing: recommendation?.target.key == level.key
                      ? const Icon(Icons.recommend_outlined)
                      : const Icon(Icons.add),
                  onTap: () async {
                    if (recommendation?.ready == true &&
                        recommendation!.target.key == level.key) {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Try the next level?'),
                          content: const Text(
                            'Were your qualifying sets controlled, pain-free and through full range? Start with the low end of the new range. You can return to an easier level at any time.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Keep current level'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Yes, try it'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true || !context.mounted) return;
                    }
                    final suggested = recommendation?.target.key == level.key;
                    Navigator.pop(
                      context,
                      CalisthenicsPick(
                        catalog.firstWhere((e) => e.slug == level.slug),
                        level,
                        suggested ? recommendation!.value : level.min,
                        suggested
                            ? recommendation!.load
                            : level.variant == 'weighted'
                            ? path.weightedStartingLoadKg
                            : 0,
                      ),
                    );
                  },
                ),
            for (final slug in path.parallelSlugs)
              for (final exercise in catalog.where((e) => e.slug == slug))
                ListTile(
                  title: Text(exercise.name),
                  subtitle: const Text(
                    'Technique branch · does not unlock strict strength levels',
                  ),
                  onTap: () => Navigator.pop(
                    context,
                    CalisthenicsPick(
                      exercise,
                      CalisthenicsLevel(
                        slug,
                        'bodyweight',
                        'Technique',
                        min: 2,
                        max: 5,
                      ),
                      2,
                      0,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
