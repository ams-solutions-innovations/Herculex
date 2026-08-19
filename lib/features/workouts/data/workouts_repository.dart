import 'package:drift/drift.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../../core/clock.dart';
import '../../../data/local/database.dart';
import '../../../data/local/exercise_biomechanics.dart';
import '../../programs/domain/schedule_status.dart';
import '../domain/active_workout_notification_target.dart';
import '../domain/exercise_search.dart';

class LastPerformanceSnapshot {
  final String? equipmentVariant;
  final List<SetEntryData> sets;

  const LastPerformanceSnapshot({
    required this.equipmentVariant,
    required this.sets,
  });
}

/// Resolves a picker filter chip against an exercise. Chips match the wider
/// attribute set (mechanics, force, plane, muscle role) that free-text search
/// deliberately ignores — see [ExerciseSearchIndex] for the query path.
class _ExerciseFacetMatcher {
  final String _facet;

  _ExerciseFacetMatcher(String? category)
    : _facet = WorkoutsRepository._normalizeExerciseSearchText(category);

  bool matches(ExerciseCatalogData exercise, List<ExerciseMuscleData> muscles) {
    if (_facet.isEmpty || _facet == 'all' || _facet == 'recent') return true;
    final exactValues = <String?>[
      exercise.category,
      exercise.primaryMuscle,
      exercise.mechanics,
      exercise.force,
      exercise.plane,
      exercise.movementPattern,
      exercise.movementPatternRaw,
      exercise.modality,
      exercise.equipment,
      for (final muscle in muscles) muscle.muscle,
      for (final muscle in muscles) muscle.role,
    ].map(WorkoutsRepository._normalizeExerciseSearchText).toSet();
    if (exactValues.contains(_facet)) return true;

    final document = WorkoutsRepository._searchDocument(exercise, muscles);
    final group = _facetGroups[_facet];
    if (group != null) {
      return group.any(
        (value) => exactValues.contains(value) || document.contains(value),
      );
    }
    return WorkoutsRepository._searchTokenGroups(
      _facet,
    ).every((group) => group.any(document.contains));
  }

  static const _facetGroups = <String, Set<String>>{
    'leg': {
      'quad',
      'hamstring',
      'glute',
      'calve',
      'tibiali',
      'adductor',
      'abductor',
    },
    'back': {'back', 'lat', 'rhomboid', 'trap', 'erector'},
    'shoulder': {'shoulder', 'front delt', 'side delt', 'rear delt'},
    'arm': {'bicep', 'brachiali', 'tricep', 'forearm'},
    'core': {'core', 'ab', 'oblique', 'hip flexor'},
  };
}

/// The whole exercise catalog with its muscle rows and a prebuilt search
/// index, loaded once and shared.
///
/// Previously every keystroke opened a fresh Drift subscription and re-read
/// the entire `exercise_muscles` table. Now the catalog streams once and
/// queries are answered in memory — 398 rows ranks in well under a frame.
class ExerciseCatalogSnapshot {
  final List<ExerciseCatalogData> exercises;
  final Map<int, List<ExerciseMuscleData>> musclesByExercise;

  final Map<int, ExerciseCatalogData> _byId;
  final ExerciseSearchIndex _index;

  ExerciseCatalogSnapshot._(
    this.exercises,
    this.musclesByExercise,
    this._byId,
    this._index,
  );

  factory ExerciseCatalogSnapshot.from(
    List<ExerciseCatalogData> exercises,
    List<ExerciseMuscleData> muscles,
  ) {
    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final muscle in muscles) {
      musclesByExercise.putIfAbsent(muscle.exerciseId, () => []).add(muscle);
    }
    final byId = {for (final e in exercises) e.id: e};
    final index = ExerciseSearchIndex.build([
      for (final e in exercises)
        SearchableExercise(
          id: e.id,
          name: e.name,
          aliases: WorkoutsRepository.splitAka(e.aka),
          equipment: e.equipment,
          modality: e.modality,
          primaryMuscle: e.primaryMuscle,
          secondaryMuscles: [
            for (final m in musclesByExercise[e.id] ?? const [])
              if (m.role != 'stabilizer') m.muscle,
          ],
        ),
    ]);
    return ExerciseCatalogSnapshot._(exercises, musclesByExercise, byId, index);
  }

  /// Facet chip filter, then relevance ranking. With no query the list stays
  /// in the catalog's alphabetical order so the browse experience is stable.
  List<ExerciseCatalogData> select({
    String? query,
    String? category,
    Set<int> recentIds = const {},
  }) {
    final facet = _ExerciseFacetMatcher(category);
    final pool = exercises
        .where((e) => facet.matches(e, musclesByExercise[e.id] ?? const []))
        .toList();

    final trimmed = query?.trim() ?? '';
    if (trimmed.isEmpty) return pool;

    final allowed = {for (final e in pool) e.id};
    final hits = _index.rank(trimmed, recentIds: recentIds);
    return [
      for (final hit in hits)
        if (allowed.contains(hit.id)) _byId[hit.id]!,
    ];
  }
}

/// Single facade over the workout tables. UI never touches Drift directly —
/// it goes through this. Keeps queries co-located and swappable later.
class WorkoutsRepository {
  final AppDatabase _db;
  final Clock _clock;

  WorkoutsRepository(this._db, this._clock);

  // ── Exercise catalog ───────────────────────────────────────────────────

  /// Alias-aware and attribute-aware search. The picker keeps the canonical
  /// [name] for display, but matching sees aliases, equipment, movement
  /// pattern, and the primary/secondary muscle rows.
  ///
  /// Normalizes common name variants so "push-up", "push up", "pushup", and
  /// simple plural forms all resolve to the same exercise.
  ///
  /// [category] carries the picker's facet chips, which match on the wider
  /// attribute set (mechanics, force, plane, muscle role) that plain search
  /// deliberately ignores.
  Stream<List<ExerciseCatalogData>> watchExercises({
    String? query,
    String? category,
    Set<int> recentIds = const {},
  }) {
    return watchExerciseCatalog().map(
      (snapshot) => snapshot.select(
        query: query,
        category: category,
        recentIds: recentIds,
      ),
    );
  }

  /// The whole catalog, alphabetical, with muscle rows and a prebuilt search
  /// index. Subscribe to this once per app rather than once per query.
  Stream<ExerciseCatalogSnapshot> watchExerciseCatalog() {
    final catalogQuery = _db.select(_db.exerciseCatalog)
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);

    return catalogQuery.watch().asyncMap((catalog) async {
      final muscles = await _db.select(_db.exerciseMuscles).get();
      return ExerciseCatalogSnapshot.from(catalog, muscles);
    });
  }

  /// Splits the denormalized `aka` blob the importer writes as ", "-joined
  /// text back into individual aliases.
  static List<String> splitAka(String? aka) {
    if (aka == null || aka.trim().isEmpty) return const [];
    return [
      for (final part in aka.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  static String _normalizeExerciseSearchText(String? value) {
    final lower = (value ?? '')
        .toLowerCase()
        .replaceAll('š', 's')
        .replaceAll('č', 'c')
        .replaceAll('ć', 'c')
        .replaceAll('ž', 'z')
        .replaceAll('đ', 'd');
    final spaced = lower
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (spaced.isEmpty) return '';
    return spaced
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map(_singularSearchToken)
        .join(' ');
  }

  static String _singularSearchToken(String token) {
    if (token == 'abs') return token;
    if (token.length <= 2) return token;
    if (token.endsWith('ies')) {
      return '${token.substring(0, token.length - 3)}y';
    }
    if (token.endsWith('es') &&
        (token.endsWith('ches') ||
            token.endsWith('shes') ||
            token.endsWith('xes') ||
            token.endsWith('ses'))) {
      return token.substring(0, token.length - 2);
    }
    if (token.endsWith('s') && !token.endsWith('ss')) {
      return token.substring(0, token.length - 1);
    }
    return token;
  }

  static List<Set<String>> _searchTokenGroups(String? value) {
    final normalized = _normalizeExerciseSearchText(value);
    if (normalized.isEmpty) return const [];
    final words = normalized.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];

    final groups = words.map(_searchAlternates).toList();
    final compact = normalized.replaceAll(' ', '');
    if (words.length == 1 && compact != words.single) {
      groups.single.add(compact);
    }
    return groups;
  }

  static Set<String> _searchAlternates(String token) {
    return {token, ...?_synonyms[token]};
  }

  static const _synonyms = <String, Set<String>>{
    'machine': {
      'machine',
      'selectorized',
      'plate loaded',
      'plateloaded',
      'iso lateral',
      'isolateral',
      'smith',
    },
    'maschine': {'machine'},
    'masina': {'machine'},
    'masine': {'machine'},
    'chest': {'chest', 'pec', 'pectoral'},
    'pec': {'chest', 'pec'},
    // Deliberately NOT expanded to bicep/biceps: combined with the muscle
    // fields in the search document that matched every exercise using the
    // biceps at all, which was 30% of the catalog.
    'curl': {'curl'},
    'curls': {'curl'},
    'pull': {'pull', 'row', 'pulldown'},
    'push': {'push', 'press'},
  };

  static String _searchDocument(
    ExerciseCatalogData exercise,
    List<ExerciseMuscleData> muscles,
  ) {
    // Only fields a user would plausibly type. Biomechanics (mechanics/force/
    // plane), loggingMetric and the muscle *role* strings are searchable via
    // the filter chips instead; including them here made "curl" match anything
    // with the biceps as a stabilizer, and "reps" match half the catalog.
    final parts = <String?>[
      exercise.name,
      exercise.aka,
      exercise.primaryMuscle,
      exercise.equipment,
      exercise.category,
      exercise.movementPattern,
      exercise.movementPatternRaw,
      exercise.modality,
      for (final muscle in muscles)
        if (muscle.role != 'stabilizer') muscle.muscle,
    ];
    final normalizedParts = parts
        .map(_normalizeExerciseSearchText)
        .where((part) => part.isNotEmpty)
        .toList();
    return [
      ...normalizedParts,
      for (final part in normalizedParts)
        if (part.contains(' ')) part.replaceAll(' ', ''),
    ].join(' ');
  }

  /// Granular muscle involvement for an exercise (drives the recovery engine
  /// and the exercise detail UI).
  Stream<List<ExerciseMuscleData>> watchExerciseMuscles(int exerciseId) {
    return (_db.select(
      _db.exerciseMuscles,
    )..where((t) => t.exerciseId.equals(exerciseId))).watch();
  }

  /// Creates a fully-attributed custom exercise. Legacy biomechanics columns
  /// (`mechanics`/`force`/`plane`/coarse `primaryMuscle`) are derived from the
  /// rich inputs so custom exercises behave like seeded ones everywhere.
  Future<ExerciseCatalogData> createCustomExercise({
    required String name,
    required List<String> primaryMuscles,
    List<String> secondaryMuscles = const [],
    List<String> stabilizers = const [],
    String category = 'strength',
    String? movementPattern,
    String modality = 'barbell',
    required String equipment,
    int cnsScore = 3,
    int recoveryImpact = 3,
    String loggingMetric = 'weight_reps',
    bool supportsWeightedBodyweight = false,
    List<String> attachments = const [],
    List<String> aliases = const [],
    int defaultRestSeconds = 120,
  }) async {
    final coarse = primaryMuscles.isEmpty
        ? 'Core'
        : ExerciseBiomechanics.coarseMuscle(primaryMuscles.first);
    return _db.transaction(() async {
      final id = await _db
          .into(_db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: name,
              primaryMuscle: coarse,
              equipment: equipment,
              mechanics: ExerciseBiomechanics.mechanics(
                movementPattern,
                category,
              ),
              force: ExerciseBiomechanics.force(movementPattern, coarse),
              plane: ExerciseBiomechanics.plane(movementPattern),
              defaultRestSeconds: Value(defaultRestSeconds),
              isCustom: const Value(true),
              aka: Value(aliases.isEmpty ? null : aliases.join(', ')),
              category: Value(category),
              movementPattern: Value(movementPattern),
              modality: Value(modality),
              cnsScore: Value(cnsScore),
              recoveryImpact: Value(recoveryImpact),
              loggingMetric: Value(loggingMetric),
              supportsWeightedBodyweight: Value(supportsWeightedBodyweight),
              attachments: Value(
                attachments.isEmpty ? null : attachments.join(', '),
              ),
              // Hand-authored ⇒ treated as reviewed.
              isReviewed: const Value(true),
            ),
          );
      Future<void> writeMuscles(List<String> ms, String role) async {
        for (final m in ms) {
          await _db
              .into(_db.exerciseMuscles)
              .insert(
                ExerciseMusclesCompanion.insert(
                  exerciseId: id,
                  muscle: m,
                  role: role,
                ),
              );
        }
      }

      await writeMuscles(primaryMuscles, 'primary');
      await writeMuscles(secondaryMuscles, 'secondary');
      await writeMuscles(stabilizers, 'stabilizer');
      for (final a in aliases) {
        await _db
            .into(_db.exerciseAliases)
            .insert(ExerciseAliasesCompanion.insert(exerciseId: id, alias: a));
      }
      return (_db.select(
        _db.exerciseCatalog,
      )..where((t) => t.id.equals(id))).getSingle();
    });
  }

  // ── Sessions ───────────────────────────────────────────────────────────

  /// Returns the session id of the in-progress workout, if any.
  Stream<WorkoutSessionData?> watchActiveSession() {
    return (_db.select(_db.workoutSessions)
          ..where((t) => t.endedAt.isNull())
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .watchSingleOrNull();
  }

  /// [sessionUuid] identifies this session across the phone<->watch wire
  /// protocol (Phase 1 of wear-sync remediation). Pass the watch's own UUID
  /// when adopting a session it already started, so future updates about it
  /// keep matching; omit it to mint a fresh one for a phone-started session.
  Future<int> startSession({
    String? notes,
    int? gymId,
    String? sessionUuid,
  }) async {
    return _db
        .into(_db.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(
            startedAt: _clock.now(),
            notes: Value(notes),
            gymId: Value(gymId),
            sessionUuid: Value(sessionUuid ?? const Uuid().v4()),
          ),
        );
  }

  Future<void> setSessionGym(int sessionId, int? gymId) async {
    await (_db.update(_db.workoutSessions)
          ..where((t) => t.id.equals(sessionId)))
        .write(WorkoutSessionsCompanion(gymId: Value(gymId)));
  }

  Future<void> endSession(
    int sessionId, {
    int? sessionRpe,
    DateTime? endedAt,
  }) async {
    await (_db.update(
      _db.workoutSessions,
    )..where((t) => t.id.equals(sessionId))).write(
      WorkoutSessionsCompanion(
        endedAt: Value(endedAt ?? _clock.now()),
        sessionRpe: Value(sessionRpe),
      ),
    );

    // A session started from a scheduled workout only becomes 'done' here.
    // Starting one leaves the schedule 'in_progress'.
    await (_db.update(_db.scheduledWorkouts)
          ..where((t) => t.completedSessionId.equals(sessionId)))
        .write(const ScheduledWorkoutsCompanion(status: Value('done')));
  }

  Future<void> deleteSession(int sessionId) async {
    await _db.transaction(() async {
      final exerciseIds = (await (_db.select(
        _db.workoutExercises,
      )..where((t) => t.sessionId.equals(sessionId))).get())
          .map((e) => e.id)
          .toList();

      if (exerciseIds.isNotEmpty) {
        final setIds = (await (_db.select(
          _db.setEntries,
        )..where((t) => t.workoutExerciseId.isIn(exerciseIds))).get())
            .map((s) => s.id)
            .toList();

        if (setIds.isNotEmpty) {
          await (_db.delete(
            _db.setAccessories,
          )..where((t) => t.setEntryId.isIn(setIds))).go();
          await (_db.delete(
            _db.setBands,
          )..where((t) => t.setEntryId.isIn(setIds))).go();
        }
        await (_db.delete(
          _db.setEntries,
        )..where((t) => t.workoutExerciseId.isIn(exerciseIds))).go();
        await (_db.delete(
          _db.workoutExercises,
        )..where((t) => t.sessionId.equals(sessionId))).go();
      }

      // Not something the FK would do on its own: a schedule pointing at this
      // session also loses the 'done' status it only gets from ending it.
      await (_db.update(_db.scheduledWorkouts)
            ..where((t) => t.completedSessionId.equals(sessionId)))
          .write(
            const ScheduledWorkoutsCompanion(
              completedSessionId: Value(null),
              status: Value(ScheduleStatus.planned),
            ),
          );

      await (_db.delete(
        _db.workoutSessions,
      )..where((t) => t.id.equals(sessionId))).go();
    });
  }

  Stream<List<WorkoutSessionData>> watchRecentSessions({int limit = 25}) {
    return (_db.select(_db.workoutSessions)
          ..where((t) => t.endedAt.isNotNull())
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
  }

  Stream<WorkoutSessionData> watchSession(int sessionId) {
    return (_db.select(
      _db.workoutSessions,
    )..where((t) => t.id.equals(sessionId))).watchSingle();
  }

  Future<void> updateSessionName(int sessionId, String name) async {
    await (_db.update(_db.workoutSessions)
          ..where((t) => t.id.equals(sessionId)))
        .write(WorkoutSessionsCompanion(name: Value(name)));
  }

  // ── Session exercises + sets ───────────────────────────────────────────

  Stream<List<WorkoutExerciseData>> watchSessionExercises(int sessionId) {
    return (_db.select(_db.workoutExercises)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .watch();
  }

  Stream<List<SetEntryData>> watchSetsForWorkoutExercise(
    int workoutExerciseId,
  ) {
    return (_db.select(_db.setEntries)
          ..where((t) => t.workoutExerciseId.equals(workoutExerciseId))
          ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
        .watch();
  }

  Future<ActiveWorkoutNotificationTarget?> activeNotificationTargetForSession(
    int sessionId,
  ) async {
    // Reads run inside a transaction so a concurrent write landing between the
    // exercises/catalog/sets queries below can't be observed as a transient
    // "exercise with no sets yet" state, which previously fell back to a
    // generic "Workout in progress" notification title mid-workout.
    return _db.transaction(() async {
      final exercises =
          await (_db.select(_db.workoutExercises)
                ..where((t) => t.sessionId.equals(sessionId))
                ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
              .get();
      if (exercises.isEmpty) return null;

      final catalog = await _db.select(_db.exerciseCatalog).get();
      final setsByWorkoutExerciseId = <int, List<SetEntryData>>{};
      for (final exercise in exercises) {
        setsByWorkoutExerciseId[exercise.id] =
            await (_db.select(_db.setEntries)
                  ..where((t) => t.workoutExerciseId.equals(exercise.id))
                  ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
                .get();
      }

      return selectActiveWorkoutNotificationTarget(
        exercises: exercises,
        setsByWorkoutExerciseId: setsByWorkoutExerciseId,
        catalog: catalog,
      );
    });
  }

  Future<int> addExerciseToSession({
    required int sessionId,
    required int exerciseId,
    String? equipmentVariant,
    String? machineConfigJson,
  }) async {
    final existing = await (_db.select(
      _db.workoutExercises,
    )..where((t) => t.sessionId.equals(sessionId))).get();
    final nextIndex = existing.length;

    final exercise = await (_db.select(
      _db.exerciseCatalog,
    )..where((t) => t.id.equals(exerciseId))).getSingle();

    final workoutExerciseId = await _db
        .into(_db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: exerciseId,
            orderIndex: nextIndex,
            targetRestSeconds: Value(exercise.defaultRestSeconds),
            equipmentVariant: Value(equipmentVariant),
            machineConfigJson: Value(machineConfigJson),
          ),
        );

    await _db
        .into(_db.setEntries)
        .insert(
          SetEntriesCompanion.insert(
            workoutExerciseId: workoutExerciseId,
            setIndex: 0,
            weightKg: 0,
            reps: 0,
          ),
        );

    return workoutExerciseId;
  }

  /// Variant chosen at log time; null falls back to the catalog modality.
  Future<void> setEquipmentVariant({
    required int workoutExerciseId,
    String? equipmentVariant,
  }) async {
    await (_db.update(
      _db.workoutExercises,
    )..where((t) => t.id.equals(workoutExerciseId))).write(
      WorkoutExercisesCompanion(equipmentVariant: Value(equipmentVariant)),
    );
  }

  /// Stores the per-log machine settings and upserts the recallable saved
  /// config for this exercise×gym (V2 §11).
  Future<void> setMachineConfig({
    required int workoutExerciseId,
    required String settingsJson,
    int? gymId,
  }) async {
    final we = await (_db.select(
      _db.workoutExercises,
    )..where((t) => t.id.equals(workoutExerciseId))).getSingle();
    await _db.transaction(() async {
      await (_db.update(
        _db.workoutExercises,
      )..where((t) => t.id.equals(workoutExerciseId))).write(
        WorkoutExercisesCompanion(machineConfigJson: Value(settingsJson)),
      );
      final saved =
          await (_db.select(_db.machineSettings)..where(
                (t) =>
                    t.exerciseId.equals(we.exerciseId) &
                    (gymId == null ? t.gymId.isNull() : t.gymId.equals(gymId)),
              ))
              .getSingleOrNull();
      if (saved == null) {
        await _db
            .into(_db.machineSettings)
            .insert(
              MachineSettingsCompanion.insert(
                exerciseId: we.exerciseId,
                gymId: Value(gymId),
                settingsJson: settingsJson,
                updatedAt: Value(_clock.now()),
              ),
            );
      } else {
        await (_db.update(
          _db.machineSettings,
        )..where((t) => t.id.equals(saved.id))).write(
          MachineSettingsCompanion(
            settingsJson: Value(settingsJson),
            updatedAt: Value(_clock.now()),
          ),
        );
      }
    });
  }

  /// Last saved machine config for this exercise at this gym (falling back to
  /// the gym-agnostic config) — pre-fills the machine settings sheet.
  Future<MachineSettingData?> recallMachineConfig({
    required int exerciseId,
    int? gymId,
  }) async {
    if (gymId != null) {
      final atGym =
          await (_db.select(_db.machineSettings)..where(
                (t) => t.exerciseId.equals(exerciseId) & t.gymId.equals(gymId),
              ))
              .getSingleOrNull();
      if (atGym != null) return atGym;
    }
    return (_db.select(_db.machineSettings)
          ..where((t) => t.exerciseId.equals(exerciseId) & t.gymId.isNull()))
        .getSingleOrNull();
  }

  Future<void> removeWorkoutExercise(int workoutExerciseId) async {
    await _db.transaction(() async {
      final setIds = (await (_db.select(
        _db.setEntries,
      )..where((t) => t.workoutExerciseId.equals(workoutExerciseId))).get())
          .map((s) => s.id)
          .toList();

      if (setIds.isNotEmpty) {
        await (_db.delete(
          _db.setAccessories,
        )..where((t) => t.setEntryId.isIn(setIds))).go();
        await (_db.delete(
          _db.setBands,
        )..where((t) => t.setEntryId.isIn(setIds))).go();
      }
      await (_db.delete(
        _db.setEntries,
      )..where((t) => t.workoutExerciseId.equals(workoutExerciseId))).go();
      await (_db.delete(
        _db.workoutExercises,
      )..where((t) => t.id.equals(workoutExerciseId))).go();
    });
  }

  Future<void> reorderWorkoutExercises({
    required int sessionId,
    required int oldIndex,
    required int newIndex,
  }) async {
    final rows =
        await (_db.select(_db.workoutExercises)
              ..where((t) => t.sessionId.equals(sessionId))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex -= 1;
    targetIndex = targetIndex.clamp(0, rows.length - 1);
    if (targetIndex == oldIndex) return;

    final reordered = List<WorkoutExerciseData>.from(rows);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, moved);

    await _db.transaction(() async {
      for (var i = 0; i < reordered.length; i++) {
        await (_db.update(_db.workoutExercises)
              ..where((t) => t.id.equals(reordered[i].id)))
            .write(WorkoutExercisesCompanion(orderIndex: Value(i)));
      }
    });
  }

  Future<void> linkWorkoutExercises({
    required int sessionId,
    required int sourceWorkoutExerciseId,
    required int targetWorkoutExerciseId,
  }) async {
    final rows =
        await (_db.select(_db.workoutExercises)
              ..where((t) => t.sessionId.equals(sessionId))
              ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
            .get();
    final source = rows
        .where((r) => r.id == sourceWorkoutExerciseId)
        .firstOrNull;
    final target = rows
        .where((r) => r.id == targetWorkoutExerciseId)
        .firstOrNull;
    if (source == null || target == null || source.id == target.id) return;

    final maxGroup = rows
        .map((r) => r.supersetGroup ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final group = source.supersetGroup ?? target.supersetGroup ?? maxGroup + 1;

    // Hard cap of 5 linked exercises per group (item 9).
    final existingGroupMembers = rows
        .where((r) => r.supersetGroup == group)
        .map((r) => r.id)
        .toSet();
    final resultingMembers = {...existingGroupMembers, source.id, target.id};
    if (resultingMembers.length > 5) return;

    await _db.transaction(() async {
      await (_db.update(_db.workoutExercises)
            ..where((t) => t.id.equals(source.id) | t.id.equals(target.id)))
          .write(WorkoutExercisesCompanion(supersetGroup: Value(group)));
    });
  }

  Future<void> unlinkWorkoutExercise(int workoutExerciseId) async {
    await (_db.update(_db.workoutExercises)
          ..where((t) => t.id.equals(workoutExerciseId)))
        .write(const WorkoutExercisesCompanion(supersetGroup: Value(null)));
  }

  Future<void> substituteExercise({
    required int workoutExerciseId,
    required int newExerciseId,
  }) async {
    await (_db.update(_db.workoutExercises)
          ..where((t) => t.id.equals(workoutExerciseId)))
        .write(WorkoutExercisesCompanion(exerciseId: Value(newExerciseId)));
  }

  // ── Sets ───────────────────────────────────────────────────────────────

  Future<int> addSet({
    required int workoutExerciseId,
    required double weightKg,
    required int reps,
    int? rpeX10,
    bool isWarmup = false,
    bool isCompleted = false,
    String setType = 'standard',
    String? setTypeMetaJson,
    double? bodyweightKg,
    double? chainsKg,
    DateTime? completedAt,
    // Non-rep logging metrics (EXR-05). Null means "this movement is not
    // measured that way" — see the column comments on SetEntries.
    int? durationSeconds,
    double? distanceM,
    int? calories,
  }) async {
    final existing = await (_db.select(
      _db.setEntries,
    )..where((t) => t.workoutExerciseId.equals(workoutExerciseId))).get();
    final nextIndex = existing.length;
    return _db
        .into(_db.setEntries)
        .insert(
          SetEntriesCompanion.insert(
            workoutExerciseId: workoutExerciseId,
            setIndex: nextIndex,
            weightKg: weightKg,
            reps: reps,
            rpeX10: Value(rpeX10),
            isWarmup: Value(isWarmup),
            isCompleted: Value(isCompleted),
            completedAt: isCompleted
                ? Value(completedAt ?? _clock.now())
                : const Value.absent(),
            setType: Value(setType),
            setTypeMetaJson: Value(setTypeMetaJson),
            bodyweightKg: Value(bodyweightKg),
            chainsKg: Value(chainsKg),
            durationSeconds: Value(durationSeconds),
            distanceM: Value(distanceM),
            calories: Value(calories),
          ),
        );
  }

  Future<void> updateSet({
    required int setId,
    double? weightKg,
    int? reps,
    int? rpeX10,
    bool clearRpe = false,
    bool? isWarmup,
    bool? isCompleted,
    String? setType,
    String? setTypeMetaJson,
    bool clearSetTypeMetaJson = false,
    double? bodyweightKg,
    bool clearBodyweightKg = false,
    double? chainsKg,
    bool clearChainsKg = false,
    DateTime? completedAt,
    // Non-rep logging metrics (EXR-05). Same absent/null/clear idiom as
    // bodyweightKg and chainsKg above: passing null leaves the stored value
    // alone, the clear flag writes SQL NULL. 0013 made these nullable so
    // "not measured this way" stays distinguishable from "measured, and zero".
    int? durationSeconds,
    bool clearDurationSeconds = false,
    double? distanceM,
    bool clearDistanceM = false,
    int? calories,
    bool clearCalories = false,
  }) async {
    await (_db.update(_db.setEntries)..where((t) => t.id.equals(setId))).write(
      SetEntriesCompanion(
        weightKg: weightKg == null ? const Value.absent() : Value(weightKg),
        reps: reps == null ? const Value.absent() : Value(reps),
        rpeX10: clearRpe
            ? const Value(null)
            : rpeX10 == null
            ? const Value.absent()
            : Value(rpeX10),
        isWarmup: isWarmup == null ? const Value.absent() : Value(isWarmup),
        isCompleted: isCompleted == null
            ? const Value.absent()
            : Value(isCompleted),
        completedAt: isCompleted == true
            ? Value(completedAt ?? _clock.now())
            : const Value.absent(),
        setType: setType == null ? const Value.absent() : Value(setType),
        setTypeMetaJson: clearSetTypeMetaJson
            ? const Value(null)
            : setTypeMetaJson == null
            ? const Value.absent()
            : Value(setTypeMetaJson),
        bodyweightKg: clearBodyweightKg
            ? const Value(null)
            : bodyweightKg == null
            ? const Value.absent()
            : Value(bodyweightKg),
        chainsKg: clearChainsKg
            ? const Value(null)
            : chainsKg == null
            ? const Value.absent()
            : Value(chainsKg),
        durationSeconds: clearDurationSeconds
            ? const Value(null)
            : durationSeconds == null
            ? const Value.absent()
            : Value(durationSeconds),
        distanceM: clearDistanceM
            ? const Value(null)
            : distanceM == null
            ? const Value.absent()
            : Value(distanceM),
        calories: clearCalories
            ? const Value(null)
            : calories == null
            ? const Value.absent()
            : Value(calories),
      ),
    );
  }

  Future<void> deleteSet(int setId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.setAccessories,
      )..where((t) => t.setEntryId.equals(setId))).go();
      await (_db.delete(
        _db.setBands,
      )..where((t) => t.setEntryId.equals(setId))).go();
      await (_db.delete(
        _db.setEntries,
      )..where((t) => t.id.equals(setId))).go();
    });
  }

  // ── Performance lookups ────────────────────────────────────────────────

  /// All sets from the most recent *completed* session that included this exercise.
  /// Used for the "last time" hint shown under the active exercise card.
  Future<LastPerformanceSnapshot?> lastPerformanceSnapshotFor(
    int exerciseId,
  ) async {
    final priorSessions =
        await (_db.selectOnly(_db.workoutExercises, distinct: true)
              ..addColumns([_db.workoutExercises.sessionId])
              ..join([
                innerJoin(
                  _db.workoutSessions,
                  _db.workoutSessions.id.equalsExp(
                    _db.workoutExercises.sessionId,
                  ),
                ),
              ])
              ..where(
                _db.workoutExercises.exerciseId.equals(exerciseId) &
                    _db.workoutSessions.endedAt.isNotNull(),
              )
              ..orderBy([
                OrderingTerm(
                  expression: _db.workoutSessions.startedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .get();

    if (priorSessions.isEmpty) return null;
    final sessionId = priorSessions.first.read(_db.workoutExercises.sessionId)!;

    final priorWorkoutExercises =
        await (_db.select(_db.workoutExercises)..where(
              (t) =>
                  t.sessionId.equals(sessionId) &
                  t.exerciseId.equals(exerciseId),
            ))
            .get();
    if (priorWorkoutExercises.isEmpty) return null;

    final priorWorkoutExercise = priorWorkoutExercises.first;
    final sets =
        await (_db.select(_db.setEntries)
              ..where(
                (t) =>
                    t.workoutExerciseId.equals(priorWorkoutExercise.id) &
                    t.isCompleted.equals(true),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
            .get();
    return LastPerformanceSnapshot(
      equipmentVariant: priorWorkoutExercise.equipmentVariant,
      sets: sets,
    );
  }

  Future<List<SetEntryData>> lastPerformanceFor(int exerciseId) async {
    return (await lastPerformanceSnapshotFor(exerciseId))?.sets ?? const [];
  }

  Future<Set<int>> getRecentExerciseIds() async {
    final recent =
        await (_db.selectOnly(_db.workoutExercises, distinct: true)
              ..addColumns([_db.workoutExercises.exerciseId])
              ..join([
                innerJoin(
                  _db.workoutSessions,
                  _db.workoutSessions.id.equalsExp(
                    _db.workoutExercises.sessionId,
                  ),
                ),
              ])
              ..where(_db.workoutSessions.endedAt.isNotNull())
              ..orderBy([
                OrderingTerm(
                  expression: _db.workoutSessions.startedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(50))
            .get();
    return recent
        .map((row) => row.read(_db.workoutExercises.exerciseId)!)
        .toSet();
  }
}
