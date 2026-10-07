import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_biomechanics.dart';
import 'package:herculex/data/local/seed_data.dart';

/// Imports the enriched exercise catalog (`assets/data/exercises.json`) into
/// the database. Idempotent: upserts by [ExerciseCatalog.slug] (falling back
/// to [ExerciseCatalog.name] for pre-v17 and custom rows), preserving row ids
/// so logged sets keep their FK, and replacing each exercise's muscle/alias
/// rows. Safe to re-run on every app upgrade.
class ExerciseImporter {
  static const assetPath = 'assets/data/exercises.json';
  static const movementsAssetPath = 'assets/data/movements.json';
  static const programmingMetadataAssetPath =
      'assets/data/exercise_programming_metadata.json';

  /// Loads the bundled assets and imports them. Falls back to the legacy seed
  /// list when the asset bundle is unavailable (e.g. unit tests with an
  /// in-memory DB).
  static Future<void> runFromAsset(AppDatabase db) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      String? movements;
      try {
        movements = await rootBundle.loadString(movementsAssetPath);
      } catch (_) {
        // Movement layer is optional: without it exercises simply stay
        // ungrouped and offer no equipment swap.
        movements = null;
      }
      String? programmingMetadata;
      try {
        programmingMetadata = await rootBundle.loadString(
          programmingMetadataAssetPath,
        );
      } catch (_) {
        // Metadata is intentionally additive.  If an older app bundle does
        // not contain it, the table defaults keep every exercise manual-only.
        programmingMetadata = null;
      }
      await runFromJson(
        db,
        raw,
        movementsJson: movements,
        programmingMetadataJson: programmingMetadata,
      );
    } catch (_) {
      await _seedFallback(db);
    }
  }

  /// Imports exercises from a JSON array string. Used directly by tests.
  static Future<void> runFromJson(
    AppDatabase db,
    String jsonStr, {
    String? movementsJson,
    String? programmingMetadataJson,
  }) async {
    final list = (jsonDecode(jsonStr) as List).cast<Map<String, dynamic>>();
    final movements = _parseMovements(movementsJson);
    final programmingMetadata = _parseProgrammingMetadata(
      programmingMetadataJson,
    );
    await db.transaction(() async {
      for (final e in list) {
        await _upsert(db, e, movements, programmingMetadata);
      }
    });
  }

  /// Movement slug → its definition.
  static Map<String, Map<String, dynamic>> _parseMovements(String? json) {
    if (json == null || json.trim().isEmpty) return const {};
    final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    return {for (final m in list) m['slug'] as String: m};
  }

  /// Parses the small, hand-curated overlay used by program generation.  It
  /// intentionally does not infer a profile from an exercise name, category,
  /// or modality: that would silently bless unusual movements in the large
  /// legacy catalogue.  Invalid/missing entries simply receive the conservative
  /// table defaults instead.
  static Map<String, Map<String, dynamic>> _parseProgrammingMetadata(
    String? json,
  ) {
    if (json == null || json.trim().isEmpty) return const {};
    final root = jsonDecode(json);
    if (root is! Map<String, dynamic>) return const {};
    final entries = root['exercises'];
    if (entries is! Map) return const {};
    return {
      for (final entry in entries.entries)
        if (entry.key is String && entry.value is Map)
          entry.key as String: Map<String, dynamic>.from(entry.value as Map),
    };
  }

  static Future<void> _upsert(
    AppDatabase db,
    Map<String, dynamic> e,
    Map<String, Map<String, dynamic>> movements,
    Map<String, Map<String, dynamic>> programmingMetadata,
  ) async {
    final name = (e['name'] as String).trim();
    final pattern = e['movementPattern'] as String?;
    final category = (e['category'] as String?) ?? 'strength';
    final primaryMuscle = (e['primaryMuscle'] as String?) ?? 'Core';
    final modality = (e['modality'] as String?) ?? 'barbell';
    final mechanics = ExerciseBiomechanics.mechanics(pattern, category);
    final cnsScore = (e['cnsScore'] as int?) ?? 3;
    final loggingMetric = (e['loggingMetric'] as String?) ?? 'weight_reps';
    final aka = (e['aka'] as List?)?.cast<String>() ?? const [];
    final attachments = (e['attachments'] as List?)?.cast<String>();

    final slug = (e['slug'] as String?)?.trim();
    final programming = _programmingProfile(
      e['programming'],
      slug == null ? null : programmingMetadata[slug],
    );
    final movementSlug = (e['movementSlug'] as String?)?.trim();
    final movement = movementSlug == null ? null : movements[movementSlug];
    // Equipment options come from the movement's members, so an exercise that
    // exists on exactly one piece of equipment offers no swap at all.
    final allowed = (movement?['allowedEquipment'] as List?)?.cast<String>();
    final requiredEquipment =
        (e['requiredEquipmentKeys'] as List?)?.cast<String>() ??
        _requiredEquipmentKeys(name, modality);
    final maxEffortEligibility =
        e['maxEffortEligibility'] as String? ??
        _maxEffortEligibility(
          mechanics: mechanics,
          modality: modality,
          cnsScore: cnsScore,
          loggingMetric: loggingMetric,
        );

    // The canonical member of a movement also answers to the bare movement
    // name, so searching "push up" reaches "Standard Push-Up" rather than
    // tying with every other push-up variant.
    final aliases = <String>[...aka];
    if (movement != null &&
        movement['canonicalExerciseSlug'] == slug &&
        movement['label'] is String) {
      final label = movement['label'] as String;
      if (!aliases.any((a) => a.toLowerCase() == label.toLowerCase())) {
        aliases.add(label);
      }
    }

    final companion = ExerciseCatalogCompanion(
      slug: Value(slug),
      movementSlug: Value(movementSlug),
      allowedEquipment: Value(allowed == null ? null : jsonEncode(allowed)),
      requiredEquipmentKeys: Value(jsonEncode(requiredEquipment)),
      maxEffortEligibility: Value(maxEffortEligibility),
      programmingDifficulty: Value(programming.difficulty),
      programmingCommonness: Value(programming.commonness),
      allowedTrainingStyles: Value(jsonEncode(programming.allowedStyles)),
      technicalEligibility: Value(programming.technicalEligibility),
      disciplines: Value(jsonEncode(programming.disciplines)),
      prerequisiteSlugs: Value(jsonEncode(programming.prerequisiteSlugs)),
      scalingGroup: Value(programming.scalingGroup),
      scalingOrder: Value(programming.scalingOrder),
      competitionAnchor: Value(programming.competitionAnchor),
      specializationTags: Value(jsonEncode(programming.specializationTags)),
      name: Value(name),
      primaryMuscle: Value(primaryMuscle),
      equipment: Value((e['equipment'] as String?) ?? 'Other'),
      mechanics: Value(mechanics),
      force: Value(ExerciseBiomechanics.force(pattern, primaryMuscle)),
      plane: Value(ExerciseBiomechanics.plane(pattern)),
      defaultRestSeconds: Value((e['defaultRestSeconds'] as int?) ?? 120),
      aka: Value(aliases.isEmpty ? null : aliases.join(', ')),
      category: Value(category),
      movementPattern: Value(pattern),
      movementPatternRaw: Value(e['movementPatternRaw'] as String?),
      modality: Value(modality),
      cnsScore: Value(cnsScore),
      recoveryImpact: Value((e['recoveryImpact'] as int?) ?? 3),
      loggingMetric: Value(loggingMetric),
      supportsWeightedBodyweight: Value(
        (e['supportsWeightedBodyweight'] as bool?) ?? false,
      ),
      attachments: Value(attachments == null ? null : jsonEncode(attachments)),
      isReviewed: Value((e['derived'] as bool?) == true ? false : true),
      movementFamily: Value(_movementFamily(name, pattern, primaryMuscle)),
    );

    // Slug first: that is what makes a rename update the row in place instead
    // of inserting a duplicate. Name lookup remains as the fallback so rows
    // written before v17 (and custom rows, which have no slug) still resolve.
    var existing = slug == null
        ? null
        : await (db.select(
            db.exerciseCatalog,
          )..where((t) => t.slug.equals(slug))).getSingleOrNull();
    existing ??= await (db.select(
      db.exerciseCatalog,
    )..where((t) => t.name.equals(name))).getSingleOrNull();

    final int id;
    if (existing == null) {
      id = await db.into(db.exerciseCatalog).insert(companion);
    } else {
      id = existing.id;
      // Preserve id + isCustom; refresh everything else.
      await (db.update(
        db.exerciseCatalog,
      )..where((t) => t.id.equals(id))).write(companion);
      await (db.delete(
        db.exerciseMuscles,
      )..where((t) => t.exerciseId.equals(id))).go();
      await (db.delete(
        db.exerciseAliases,
      )..where((t) => t.exerciseId.equals(id))).go();
    }

    await _writeMuscles(db, id, e['primaryMuscles'], 'primary');
    await _writeMuscles(db, id, e['secondaryMuscles'], 'secondary');
    await _writeMuscles(db, id, e['stabilizers'], 'stabilizer');

    for (final alias in aliases) {
      await db
          .into(db.exerciseAliases)
          .insert(
            ExerciseAliasesCompanion.insert(exerciseId: id, alias: alias),
          );
    }
  }

  /// The profile is resolved from an optional exercise-local source first and
  /// then from the curated overlay.  Keeping the overlay separate lets catalog
  /// maintenance remain independent of programming policy, while a future
  /// upstream catalogue can carry the exact same `programming` object inline.
  static _ProgrammingProfile _programmingProfile(
    dynamic inline,
    Map<String, dynamic>? overlay,
  ) {
    final raw = inline is Map
        ? Map<String, dynamic>.from(inline)
        : overlay ?? const <String, dynamic>{};
    const difficulties = {'novice', 'intermediate', 'advanced'};
    const commonnesses = {'basic', 'common', 'specialty', 'manualOnly'};
    const technicalEligibility = {
      'automatic',
      'technical_review',
      'manual_only',
    };
    const styles = {
      'weightlifting',
      'calisthenics',
      'basic',
      'crossfit',
      'powerlifting',
      'hypertrophy',
    };
    const canonicalDisciplines = {
      'weights',
      'calisthenics',
      'crossfit',
      'olympic',
      'gpp',
    };

    final difficulty = raw['difficulty'] as String?;
    final commonness = raw['commonness'] as String?;
    final eligibility = raw['technicalEligibility'] as String?;
    final rawStyles = raw['allowedTrainingStyles'];
    final allowedStyles = rawStyles is List
        ? rawStyles.whereType<String>().where(styles.contains).toSet().toList()
        : const <String>[];

    final rawDisciplines = raw['disciplines'];
    final disciplines = rawDisciplines is List
        ? rawDisciplines
              .whereType<String>()
              .where(canonicalDisciplines.contains)
              .toSet()
              .toList()
        : const <String>[];

    final rawPrereqs = raw['prerequisiteSlugs'];
    final prerequisiteSlugs = rawPrereqs is List
        ? rawPrereqs.whereType<String>().toSet().toList()
        : const <String>[];

    final rawTags = raw['specializationTags'];
    final specializationTags = rawTags is List
        ? rawTags.whereType<String>().toSet().toList()
        : const <String>[];

    final scalingGroup = (raw['scalingGroup'] as String?)?.trim();
    final scalingOrder = raw['scalingOrder'] as int?;
    final competitionAnchor = (raw['competitionAnchor'] as String?)?.trim();

    return _ProgrammingProfile(
      difficulty: difficulties.contains(difficulty) ? difficulty! : 'advanced',
      commonness: commonnesses.contains(commonness)
          ? commonness!
          : 'manualOnly',
      allowedStyles: allowedStyles,
      technicalEligibility: technicalEligibility.contains(eligibility)
          ? eligibility!
          : 'manual_only',
      disciplines: disciplines,
      prerequisiteSlugs: prerequisiteSlugs,
      scalingGroup: (scalingGroup != null && scalingGroup.isNotEmpty)
          ? scalingGroup
          : null,
      scalingOrder: scalingOrder,
      competitionAnchor:
          (competitionAnchor != null && competitionAnchor.isNotEmpty)
          ? competitionAnchor
          : null,
      specializationTags: specializationTags,
    );
  }

  static List<String> _requiredEquipmentKeys(String name, String modality) {
    final lower = name.toLowerCase();
    final keys = <String>[];
    if (lower.contains('safety squat')) {
      keys.add('safety_squat_bar');
    } else if (lower.contains('cambered')) {
      keys.add('cambered_bar');
    } else if (lower.contains('swiss bar') || lower.contains('football bar')) {
      keys.add('swiss_bar');
    } else if (lower.contains('duffalo')) {
      keys.add('duffalo_bar');
    } else if (lower.contains('axle')) {
      keys.add('axle_bar');
    } else if (lower.contains('trap bar')) {
      keys.add('trap_bar');
    } else {
      keys.add(modality);
    }
    if (lower.contains('chain')) keys.add('chains');
    if (lower.contains('banded') || lower.contains('bands')) keys.add('bands');
    if (lower.contains('reverse hyper')) keys.add('reverse_hyper');
    if (lower.contains('glute ham') || lower.contains('ghr')) keys.add('ghr');
    if (lower.contains('belt squat')) keys.add('belt_squat');
    if (lower.contains('sled')) keys.add('sled');
    if (lower.contains('yoke')) keys.add('yoke');
    if (lower.contains('ring') || lower.contains('trx')) keys.add('rings_trx');
    return keys.toSet().toList(growable: false);
  }

  static String _maxEffortEligibility({
    required String mechanics,
    required String modality,
    required int cnsScore,
    required String loggingMetric,
  }) {
    const loadable = {'barbell', 'dumbbell', 'smith', 'machine_plate'};
    if (mechanics != 'compound' || loggingMetric != 'weight_reps') {
      return 'unsuitable';
    }
    if (loadable.contains(modality) && cnsScore >= 5) return 'suitable';
    if (loadable.contains(modality) && cnsScore >= 3) {
      return 'advanced_manual';
    }
    return 'unsuitable';
  }

  /// Equipment tokens stripped from a name to find its base movement. Mirrors
  /// the equipment vocabulary in `tool/build_exercises.py`. Order matters:
  /// multi-word tokens are tried before their substrings (handled by sorting
  /// on length in [_movementFamily]).
  static const _equipmentTokens = <String>[
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

  /// Derives the movement-family key: the base movement name (equipment words
  /// removed, bench→press normalized) scoped by movement pattern + coarse
  /// muscle. Real modifiers (incline/decline/close-grip/…) survive, so
  /// "Incline Press" and "Bench Press" remain distinct families while their
  /// equipment variants collapse together. Returns null when there's no usable
  /// pattern, so such rows stay ungrouped.
  static String? _movementFamily(
    String name,
    String? pattern,
    String primaryMuscle,
  ) {
    if (pattern == null || pattern.isEmpty) return null;
    var n = ' ${name.toLowerCase()} ';
    for (final t in _equipmentTokens) {
      n = n.replaceAll(' $t ', ' ');
    }
    n = n.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Press/bench synonyms collapse onto "press".
    n = n.replaceAll('bench press', 'press').replaceAll('bench', 'press');
    n = n.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (n.isEmpty) return null;
    return '$n|$pattern|$primaryMuscle';
  }

  static Future<void> _writeMuscles(
    AppDatabase db,
    int id,
    dynamic raw,
    String role,
  ) async {
    final muscles = (raw as List?)?.cast<String>() ?? const [];
    for (final m in muscles) {
      await db
          .into(db.exerciseMuscles)
          .insertOnConflictUpdate(
            ExerciseMusclesCompanion.insert(
              exerciseId: id,
              muscle: m,
              role: role,
            ),
          );
    }
  }

  /// Used when the JSON asset is unavailable; seeds the legacy starter catalog
  /// enriched with safe defaults so the app remains usable.
  static Future<void> _seedFallback(AppDatabase db) async {
    final already = await db.select(db.exerciseCatalog).get();
    if (already.isNotEmpty) return;
    await db.batch((b) {
      b.insertAll(
        db.exerciseCatalog,
        kSeedExercises.map(
          (e) => ExerciseCatalogCompanion.insert(
            name: e.name,
            primaryMuscle: e.primaryMuscle,
            equipment: e.equipment,
            mechanics: e.mechanics,
            force: e.force,
            plane: e.plane,
            defaultRestSeconds: Value(e.defaultRestSeconds),
          ),
        ),
      );
    });
  }
}

class _ProgrammingProfile {
  const _ProgrammingProfile({
    required this.difficulty,
    required this.commonness,
    required this.allowedStyles,
    required this.technicalEligibility,
    required this.disciplines,
    required this.prerequisiteSlugs,
    this.scalingGroup,
    this.scalingOrder,
    this.competitionAnchor,
    required this.specializationTags,
  });

  final String difficulty;
  final String commonness;
  final List<String> allowedStyles;
  final String technicalEligibility;
  final List<String> disciplines;
  final List<String> prerequisiteSlugs;
  final String? scalingGroup;
  final int? scalingOrder;
  final String? competitionAnchor;
  final List<String> specializationTags;
}
