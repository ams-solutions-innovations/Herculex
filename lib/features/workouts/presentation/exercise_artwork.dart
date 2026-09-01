import 'package:flutter/material.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/workouts/presentation/equipment_icon.dart';
import 'package:herculex/features/workouts/presentation/exercise_artwork_manifest.dart';

/// Maps catalog exercises to the artwork shipped with the exercise library.
///
/// Every equipment variant is its own catalog row with its own slug, so a
/// straight slug lookup is also what makes the picture follow the equipment:
/// the family tile shows its first (barbell) variant, and picking a different
/// style hands the caller that variant's row — and with it, its illustration.
///
/// Exercises still awaiting an illustration render a clean vector equipment
/// glyph instead; [kExerciseArtworkSlugs] is generated from the files that
/// actually ship, so this never resolves to a missing asset.
String? exerciseArtworkAsset(ExerciseCatalogData exercise) {
  final slug = exercise.slug?.toLowerCase();
  if (slug == null || !kExerciseArtworkSlugs.contains(slug)) return null;
  return 'assets/images/exercises/$slug.webp';
}

/// Resolves artwork for a slug on its own, for call sites that hold a variant
/// slug rather than a full catalog row.
String? exerciseArtworkAssetForSlug(String? slug) {
  final key = slug?.toLowerCase();
  if (key == null || !kExerciseArtworkSlugs.contains(key)) return null;
  return 'assets/images/exercises/$key.webp';
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
  final Color? glyphColor;
  final String? equipmentVariant;

  const ExerciseArtwork({
    super.key,
    required this.exercise,
    this.size = 48,
    this.radius = 12,
    this.fallbackColor,
    this.glyphColor,
    this.equipmentVariant,
  });

  @override
  Widget build(BuildContext context) {
    final asset = exerciseArtworkAsset(exercise);
    final theme = Theme.of(context);
    final equipmentStr = equipmentVariant ?? exercise.equipment;
    final bg =
        fallbackColor ??
        (theme.brightness == Brightness.dark
            ? AppColors.surfaceVariant
            : AppColors.surfaceContainer);
    final iconColor =
        glyphColor ??
        (fallbackColor != null ? Colors.white : AppColors.primary);

    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      alignment: Alignment.center,
      child: EquipmentGlyph(
        variant: equipmentStr,
        size: size * 0.54,
        color: iconColor,
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
