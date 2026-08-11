import 'package:drift/drift.dart';

import '../../../data/local/database.dart';

class TemplatesRepository {
  final AppDatabase _db;
  TemplatesRepository(this._db);

  // ── Folders ────────────────────────────────────────────────────────────

  Stream<List<WorkoutFolderData>> watchFolders() =>
      (_db.select(_db.workoutFolders)
            ..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .watch();

  Future<WorkoutFolderData> createFolder({required String name, String emoji = '💪'}) async {
    final id = await _db.into(_db.workoutFolders).insert(
          WorkoutFoldersCompanion.insert(name: name, emoji: Value(emoji)),
        );
    return (_db.select(_db.workoutFolders)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> renameFolder(int id, {required String name, required String emoji}) =>
      (_db.update(_db.workoutFolders)..where((t) => t.id.equals(id)))
          .write(WorkoutFoldersCompanion(name: Value(name), emoji: Value(emoji)));

  Future<void> deleteFolder(int id) => _db.transaction(() async {
        await (_db.update(_db.workoutTemplates)
              ..where((t) => t.folderId.equals(id)))
            .write(const WorkoutTemplatesCompanion(folderId: Value(null)));
        await (_db.delete(_db.workoutFolders)..where((t) => t.id.equals(id)))
            .go();
      });

  // ── Templates ──────────────────────────────────────────────────────────

  /// All templates, optionally filtered by folder. Pass null to get unfiled ones,
  /// pass -1 to get all.
  Stream<List<WorkoutTemplateData>> watchTemplates({int? folderId}) {
    final q = _db.select(_db.workoutTemplates)
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (folderId == null) {
      q.where((t) => t.folderId.isNull());
    } else if (folderId != -1) {
      q.where((t) => t.folderId.equals(folderId));
    }
    return q.watch();
  }

  Future<WorkoutTemplateData> createTemplate({
    required String name,
    String? notes,
    int? folderId,
  }) async {
    final id = await _db.into(_db.workoutTemplates).insert(
          WorkoutTemplatesCompanion.insert(
            name: name,
            notes: Value(notes),
            folderId: Value(folderId),
          ),
        );
    return (_db.select(_db.workoutTemplates)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> updateTemplate(int id, {String? name, String? notes, int? folderId, bool clearFolder = false}) =>
      (_db.update(_db.workoutTemplates)..where((t) => t.id.equals(id))).write(
        WorkoutTemplatesCompanion(
          name: name != null ? Value(name) : const Value.absent(),
          notes: notes != null ? Value(notes) : const Value.absent(),
          folderId: clearFolder ? const Value(null) : (folderId != null ? Value(folderId) : const Value.absent()),
        ),
      );

  Future<void> deleteTemplate(int id) => _db.transaction(() async {
        final exerciseIds = (await (_db.select(_db.templateExercises)
                  ..where((t) => t.templateId.equals(id)))
                .get())
            .map((e) => e.id)
            .toList();

        if (exerciseIds.isNotEmpty) {
          await (_db.delete(_db.templateSets)
                ..where((t) => t.templateExerciseId.isIn(exerciseIds)))
              .go();
        }
        await (_db.delete(_db.templateExercises)
              ..where((t) => t.templateId.equals(id)))
            .go();
        await (_db.update(_db.programDays)
              ..where((t) => t.templateId.equals(id)))
            .write(const ProgramDaysCompanion(templateId: Value(null)));
        await (_db.update(_db.scheduledWorkouts)
              ..where((t) => t.templateIdOverride.equals(id)))
            .write(
              const ScheduledWorkoutsCompanion(
                templateIdOverride: Value(null),
              ),
            );
        await (_db.delete(_db.workoutTemplates)..where((t) => t.id.equals(id)))
            .go();
      });

  Future<void> markUsed(int templateId) =>
      (_db.update(_db.workoutTemplates)..where((t) => t.id.equals(templateId)))
          .write(WorkoutTemplatesCompanion(lastUsedAt: Value(DateTime.now())));

  // ── Template exercises & sets ──────────────────────────────────────────

  Stream<List<TemplateExerciseData>> watchTemplateExercises(int templateId) =>
      (_db.select(_db.templateExercises)
            ..where((t) => t.templateId.equals(templateId))
            ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
          .watch();

  Stream<List<TemplateSetData>> watchTemplateSets(int templateExerciseId) =>
      (_db.select(_db.templateSets)
            ..where((t) => t.templateExerciseId.equals(templateExerciseId))
            ..orderBy([(t) => OrderingTerm(expression: t.setOrder)]))
          .watch();

  Future<List<TemplateSetData>> getTemplateSets(int templateExerciseId) async {
    final sets = await (_db.select(_db.templateSets)
          ..where((t) => t.templateExerciseId.equals(templateExerciseId))
          ..orderBy([(t) => OrderingTerm(expression: t.setOrder)]))
        .get();
    if (sets.isNotEmpty) return sets;

    // Auto-initialize default set rows if none exist
    final te = await (_db.select(_db.templateExercises)
          ..where((t) => t.id.equals(templateExerciseId)))
        .getSingleOrNull();
    if (te == null) return [];

    final count = te.targetSets > 0 ? te.targetSets : 3;
    final defaultReps = te.targetRepsMin ?? 8;
    for (var i = 0; i < count; i++) {
      await _db.into(_db.templateSets).insert(
            TemplateSetsCompanion.insert(
              templateExerciseId: templateExerciseId,
              setOrder: i + 1,
              setType: const Value('standard'),
              targetReps: Value(defaultReps),
              isWarmup: const Value(false),
            ),
          );
    }

    return (_db.select(_db.templateSets)
          ..where((t) => t.templateExerciseId.equals(templateExerciseId))
          ..orderBy([(t) => OrderingTerm(expression: t.setOrder)]))
        .get();
  }

  Future<int> addExerciseToTemplate({
    required int templateId,
    required int exerciseId,
    int targetSets = 3,
    int? targetRepsMin = 8,
    int? targetRepsMax = 12,
    int? targetRestSeconds,
  }) async {
    final existing = await (_db.select(_db.templateExercises)
          ..where((t) => t.templateId.equals(templateId)))
        .get();
    final id = await _db.into(_db.templateExercises).insert(
          TemplateExercisesCompanion.insert(
            templateId: templateId,
            exerciseId: exerciseId,
            orderIndex: existing.length,
            targetSets: Value(targetSets),
            targetRepsMin: Value(targetRepsMin),
            targetRepsMax: Value(targetRepsMax),
            targetRestSeconds: Value(targetRestSeconds),
          ),
        );

    final reps = targetRepsMin ?? 8;
    for (var i = 0; i < targetSets; i++) {
      await _db.into(_db.templateSets).insert(
            TemplateSetsCompanion.insert(
              templateExerciseId: id,
              setOrder: i + 1,
              setType: const Value('standard'),
              targetReps: Value(reps),
              isWarmup: const Value(false),
            ),
          );
    }
    return id;
  }

  Future<void> addTemplateSet({
    required int templateExerciseId,
    String setType = 'standard',
    String? setTypeMetaJson,
    int? targetReps = 8,
    double? targetWeightKg,
    bool isWarmup = false,
  }) async {
    final existing = await getTemplateSets(templateExerciseId);
    final nextOrder = existing.length + 1;
    final lastReps = existing.isNotEmpty ? (existing.last.targetReps ?? targetReps) : targetReps;
    final lastWeight = existing.isNotEmpty ? (existing.last.targetWeightKg ?? targetWeightKg) : targetWeightKg;

    await _db.into(_db.templateSets).insert(
          TemplateSetsCompanion.insert(
            templateExerciseId: templateExerciseId,
            setOrder: nextOrder,
            setType: Value(setType),
            setTypeMetaJson: Value(setTypeMetaJson),
            targetReps: Value(lastReps),
            targetWeightKg: Value(lastWeight),
            isWarmup: Value(isWarmup),
          ),
        );

    // Keep targetSets in sync
    await (_db.update(_db.templateExercises)..where((t) => t.id.equals(templateExerciseId)))
        .write(TemplateExercisesCompanion(targetSets: Value(nextOrder)));
  }

  Future<void> updateTemplateSet(
    int setId, {
    String? setType,
    String? setTypeMetaJson,
    int? targetReps,
    double? targetWeightKg,
    bool? isWarmup,
    bool clearMetaJson = false,
  }) =>
      (_db.update(_db.templateSets)..where((t) => t.id.equals(setId))).write(
        TemplateSetsCompanion(
          setType: setType != null ? Value(setType) : const Value.absent(),
          setTypeMetaJson: clearMetaJson ? const Value(null) : (setTypeMetaJson != null ? Value(setTypeMetaJson) : const Value.absent()),
          targetReps: targetReps != null ? Value(targetReps) : const Value.absent(),
          targetWeightKg: targetWeightKg != null ? Value(targetWeightKg) : const Value.absent(),
          isWarmup: isWarmup != null ? Value(isWarmup) : const Value.absent(),
        ),
      );

  Future<void> deleteTemplateSet(int setId) async {
    final setRow = await (_db.select(_db.templateSets)..where((t) => t.id.equals(setId))).getSingleOrNull();
    if (setRow == null) return;

    final teId = setRow.templateExerciseId;
    await (_db.delete(_db.templateSets)..where((t) => t.id.equals(setId))).go();

    // Re-index remaining sets
    final remaining = await (_db.select(_db.templateSets)
          ..where((t) => t.templateExerciseId.equals(teId))
          ..orderBy([(t) => OrderingTerm(expression: t.setOrder)]))
        .get();

    for (var i = 0; i < remaining.length; i++) {
      if (remaining[i].setOrder != i + 1) {
        await (_db.update(_db.templateSets)..where((t) => t.id.equals(remaining[i].id)))
            .write(TemplateSetsCompanion(setOrder: Value(i + 1)));
      }
    }

    await (_db.update(_db.templateExercises)..where((t) => t.id.equals(teId)))
        .write(TemplateExercisesCompanion(targetSets: Value(remaining.length)));
  }

  Future<void> removeExerciseFromTemplate(int templateExerciseId) =>
      _db.transaction(() async {
        await (_db.delete(_db.templateSets)
              ..where((t) => t.templateExerciseId.equals(templateExerciseId)))
            .go();
        await (_db.delete(_db.templateExercises)
              ..where((t) => t.id.equals(templateExerciseId)))
            .go();
      });

  /// Updates a template exercise's targets. When [targetSets] changes, the
  /// actual [TemplateSetData] rows are reconciled to match (via
  /// [addTemplateSet]/[deleteTemplateSet], which keep ordering consistent)
  /// instead of just rewriting the counter column (item 6).
  Future<void> updateTemplateExercise(
    int id, {
    int? targetSets,
    int? targetRepsMin,
    int? targetRepsMax,
    int? targetRestSeconds,
  }) async {
    if (targetSets != null) {
      final current = await getTemplateSets(id);
      final diff = targetSets - current.length;
      if (diff > 0) {
        for (var i = 0; i < diff; i++) {
          await addTemplateSet(templateExerciseId: id);
        }
      } else if (diff < 0) {
        final toRemove = current.sublist(current.length + diff);
        for (final set in toRemove) {
          await deleteTemplateSet(set.id);
        }
      }
    }
    await (_db.update(_db.templateExercises)..where((t) => t.id.equals(id))).write(
      TemplateExercisesCompanion(
        targetSets: targetSets != null ? Value(targetSets) : const Value.absent(),
        targetRepsMin: targetRepsMin != null ? Value(targetRepsMin) : const Value.absent(),
        targetRepsMax: targetRepsMax != null ? Value(targetRepsMax) : const Value.absent(),
        targetRestSeconds: targetRestSeconds != null ? Value(targetRestSeconds) : const Value.absent(),
      ),
    );
  }

  /// Starts a live workout session pre-populated from a template.
  /// Returns the new session id.
  ///
  /// Copying the template's exercises and sets into the session here is what
  /// makes the program-day template link a *live reference*: editing the
  /// template afterwards changes future sessions but can no longer reach one
  /// that has already been started.
  Future<int> startSessionFromTemplate(
    int templateId, {
    DateTime? startedAt,
    int? gymId,
    String? notes,
  }) async {
    final exercises = await (_db.select(_db.templateExercises)
          ..where((t) => t.templateId.equals(templateId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();

    return _db.transaction(() async {
      final sessionId = await _db.into(_db.workoutSessions).insert(
            WorkoutSessionsCompanion.insert(
              startedAt: startedAt ?? DateTime.now(),
              gymId: Value(gymId),
              notes: Value(notes),
            ),
          );
      for (final te in exercises) {
        final workoutExerciseId = await _db.into(_db.workoutExercises).insert(
              WorkoutExercisesCompanion.insert(
                sessionId: sessionId,
                exerciseId: te.exerciseId,
                orderIndex: te.orderIndex,
                targetRestSeconds: Value(te.targetRestSeconds),
              ),
            );

        final templateSets = await getTemplateSets(te.id);
        if (templateSets.isNotEmpty) {
          for (final ts in templateSets) {
            await _db.into(_db.setEntries).insert(
                  SetEntriesCompanion.insert(
                    workoutExerciseId: workoutExerciseId,
                    setIndex: ts.setOrder,
                    reps: ts.targetReps ?? te.targetRepsMin ?? 0,
                    weightKg: ts.targetWeightKg ?? 0.0,
                    setType: Value(ts.setType),
                    setTypeMetaJson: Value(ts.setTypeMetaJson),
                    isWarmup: Value(ts.isWarmup),
                    isCompleted: const Value(false),
                  ),
                );
          }
        } else {
          // Fallback if no sets
          final defaultReps = te.targetRepsMin ?? 8;
          for (var i = 0; i < te.targetSets; i++) {
            await _db.into(_db.setEntries).insert(
                  SetEntriesCompanion.insert(
                    workoutExerciseId: workoutExerciseId,
                    setIndex: i + 1,
                    reps: defaultReps,
                    weightKg: 0.0,
                    isCompleted: const Value(false),
                  ),
                );
          }
        }
      }
      await markUsed(templateId);
      return sessionId;
    });
  }
}
