import 'package:flutter/material.dart';

import '../../../data/local/database.dart';

/// Maps catalog exercises to the artwork shipped with the exercise library.
///
/// Keep this deliberately small and explicit. Until an exercise receives its
/// own illustration, its tile deliberately reserves blank image space rather
/// than suggesting a misleading substitute.
String? exerciseArtworkAsset(ExerciseCatalogData exercise) {
  final slug = exercise.slug?.toLowerCase();
  if (slug == 'barbell-back-squat') {
    return 'assets/images/exercises/barbell_back_squat_anatomical.png';
  }
  if (slug == 'barbell-bench-press') {
    return 'assets/images/exercises/barbell_bench_press_anatomical.png';
  }
  return null;
}

/// Picks the first available artwork in a movement family.
String? exerciseArtworkAssetFor(Iterable<ExerciseCatalogData> exercises) {
  for (final exercise in exercises) {
    final asset = exerciseArtworkAsset(exercise);
    if (asset != null) return asset;
  }
  return null;
}

class ExerciseArtwork extends StatelessWidget {
  final ExerciseCatalogData exercise;
  final double size;
  final double radius;
  final Color? fallbackColor;

  const ExerciseArtwork({
    super.key,
    required this.exercise,
    this.size = 48,
    this.radius = 12,
    this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    final asset = exerciseArtworkAsset(exercise);
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fallbackColor ?? Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    if (asset == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}
