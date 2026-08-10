/// Resolves an exercise arriving from the Wear OS app onto a phone catalog row.
///
/// The watch used to be matched on display name alone, with a single
/// case-insensitive comparison and an immediate `createCustomExercise` on a
/// miss. Every name the two sides disagreed on — the watch's hardcoded
/// fallback list, and every `"Squat (Barbell)"` the watch's equipment prompt
/// synthesised — therefore minted a junk `isCustom` row with
/// `equipment: 'other'`, silently splitting a user's history across two
/// catalog entries for the same lift.
///
/// Identity now travels with the payload (`catalogExerciseId`, then `slug`),
/// and names are only a fallback for watches that predate that. Pure Dart on
/// purpose: no Drift, no Flutter, so the whole chain is unit testable.
library;

/// One catalog row flattened into the fields resolution looks at.
class ResolvableExercise {
  final int id;

  /// Stable catalog identity. Null on custom and pre-v17 rows.
  final String? slug;

  final String name;

  /// The row's `aka` list. Matched after names, before normalization.
  final List<String> aliases;

  const ResolvableExercise({
    required this.id,
    required this.name,
    this.slug,
    this.aliases = const [],
  });
}

/// How a watch exercise was matched. Recorded so the caller can log which
/// rung of the ladder is actually carrying traffic — a resolution that only
/// ever lands on [ResolutionSource.normalizedName] means identity is being
/// dropped somewhere upstream.
enum ResolutionSource { catalogId, slug, name, alias, normalizedName }

class WatchExerciseMatch {
  final int exerciseId;
  final ResolutionSource source;

  const WatchExerciseMatch(this.exerciseId, this.source);
}

/// Equipment labels the watch appends to a base exercise name, lowercased.
///
/// Only these are stripped as a trailing parenthetical, so real catalog names
/// that end in a qualifier — `Lat Pulldown (Wide Grip)`, `Cable Fly (High to
/// Low)` — are never mangled into their base movement.
const _watchEquipmentSuffixes = <String>{
  'barbell',
  'dumbbell',
  'smith machine',
  'smith',
  'cable',
  'machine (plate-loaded)',
  'machine (selectorized)',
  'machine',
  'kettlebell',
  'band',
  'bodyweight',
  'other',
};

/// Prebuilt index over the catalog. Build once per inbound sync, then resolve
/// every exercise in the payload against it.
class WatchExerciseIndex {
  final Map<int, ResolvableExercise> _byId;
  final Map<String, ResolvableExercise> _bySlug;
  final Map<String, ResolvableExercise> _byName;
  final Map<String, ResolvableExercise> _byAlias;
  final Map<String, ResolvableExercise> _byNormalized;

  const WatchExerciseIndex._(
    this._byId,
    this._bySlug,
    this._byName,
    this._byAlias,
    this._byNormalized,
  );

  factory WatchExerciseIndex.build(Iterable<ResolvableExercise> exercises) {
    final byId = <int, ResolvableExercise>{};
    final bySlug = <String, ResolvableExercise>{};
    final byName = <String, ResolvableExercise>{};
    final byAlias = <String, ResolvableExercise>{};
    final byNormalized = <String, ResolvableExercise>{};

    for (final exercise in exercises) {
      byId[exercise.id] = exercise;
      final slug = exercise.slug?.trim().toLowerCase();
      if (slug != null && slug.isNotEmpty) {
        // First row wins: a custom row that somehow shares a slug must not
        // displace the seeded one it was cloned from.
        bySlug.putIfAbsent(slug, () => exercise);
      }
      byName.putIfAbsent(exercise.name.trim().toLowerCase(), () => exercise);
      byNormalized.putIfAbsent(normalizeName(exercise.name), () => exercise);
      for (final alias in exercise.aliases) {
        final key = alias.trim().toLowerCase();
        if (key.isEmpty) continue;
        byAlias.putIfAbsent(key, () => exercise);
      }
    }

    // Normalized aliases are folded in only after every name has claimed its
    // key, so an alias can never shadow a real exercise's own name.
    for (final exercise in exercises) {
      for (final alias in exercise.aliases) {
        final key = normalizeName(alias);
        if (key.isEmpty) continue;
        byNormalized.putIfAbsent(key, () => exercise);
      }
    }

    return WatchExerciseIndex._(byId, bySlug, byName, byAlias, byNormalized);
  }

  /// Walks the resolution ladder, returning null only when nothing matches —
  /// at which point the caller may legitimately create a custom exercise.
  WatchExerciseMatch? resolve({
    int? catalogExerciseId,
    String? slug,
    String? name,
  }) {
    if (catalogExerciseId != null) {
      final hit = _byId[catalogExerciseId];
      if (hit != null) {
        return WatchExerciseMatch(hit.id, ResolutionSource.catalogId);
      }
    }

    final slugKey = slug?.trim().toLowerCase();
    if (slugKey != null && slugKey.isNotEmpty) {
      final hit = _bySlug[slugKey];
      if (hit != null) {
        return WatchExerciseMatch(hit.id, ResolutionSource.slug);
      }
    }

    if (name == null || name.trim().isEmpty) return null;

    final nameKey = name.trim().toLowerCase();
    final byName = _byName[nameKey];
    if (byName != null) {
      return WatchExerciseMatch(byName.id, ResolutionSource.name);
    }

    final byAlias = _byAlias[nameKey];
    if (byAlias != null) {
      return WatchExerciseMatch(byAlias.id, ResolutionSource.alias);
    }

    // Punctuation and the watch's synthetic equipment suffix are the last
    // things standing between "Push Up" / "Squat (Barbell)" and their rows.
    for (final candidate in [name, stripEquipmentSuffix(name)]) {
      final normalized = normalizeName(candidate);
      if (normalized.isEmpty) continue;
      final hit = _byNormalized[normalized];
      if (hit != null) {
        return WatchExerciseMatch(hit.id, ResolutionSource.normalizedName);
      }
    }

    return null;
  }
}

/// Lowercases and drops everything that isn't a letter or digit, so
/// `Push-Up`, `Push Up` and `push up` collapse onto one key.
String normalizeName(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    if (RegExp(r'[a-z0-9]').hasMatch(char)) buffer.write(char);
  }
  return buffer.toString();
}

/// Removes a trailing `" (Barbell)"`-style equipment parenthetical written by
/// older watch builds. Returns [name] unchanged when the parenthetical isn't
/// an equipment label.
String stripEquipmentSuffix(String name) {
  final trimmed = name.trim();
  if (!trimmed.endsWith(')')) return trimmed;
  final open = trimmed.lastIndexOf('(');
  if (open <= 0) return trimmed;
  final inner = trimmed.substring(open + 1, trimmed.length - 1).toLowerCase();
  if (!_watchEquipmentSuffixes.contains(inner)) return trimmed;
  return trimmed.substring(0, open).trim();
}
