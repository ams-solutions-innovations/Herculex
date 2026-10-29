import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/portable_workout_plan.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';

class ExerciseHistoryEntry {
  const ExerciseHistoryEntry(this.exercise, this.session, this.setCount);
  final WorkoutExerciseData exercise;
  final WorkoutSessionData session;
  final int setCount;
}

class ExerciseHistoryPreview {
  const ExerciseHistoryPreview({
    required this.source,
    required this.target,
    required this.entries,
    required this.fingerprints,
    this.equipment,
  });
  final ExerciseCatalogData source, target;
  final List<ExerciseHistoryEntry> entries;
  final Map<String, String> fingerprints;
  final String? equipment;
  int get setCount => entries.fold(0, (n, e) => n + e.setCount);
}

/// Corrects recorded identity, without merging the catalogue or program data.
class ExerciseHistoryRepository {
  ExerciseHistoryRepository(this.db, this.clock);
  final AppDatabase db;
  final Clock clock;

  Future<List<ExerciseHistoryEntry>> entries(int exerciseId) async {
    final rows =
        await (db.select(db.workoutExercises).join([
                innerJoin(
                  db.workoutSessions,
                  db.workoutSessions.id.equalsExp(
                    db.workoutExercises.sessionId,
                  ),
                ),
              ])
              ..where(
                db.workoutExercises.exerciseId.equals(exerciseId) &
                    db.workoutExercises.deletedAt.isNull() &
                    db.workoutSessions.deletedAt.isNull() &
                    db.workoutSessions.endedAt.isNotNull(),
              )
              ..orderBy([
                OrderingTerm.desc(db.workoutSessions.startedAt),
                OrderingTerm.asc(db.workoutExercises.orderIndex),
              ]))
            .get();
    final result = <ExerciseHistoryEntry>[];
    for (final r in rows) {
      final e = r.readTable(db.workoutExercises);
      final sets =
          await (db.select(db.setEntries)..where(
                (s) =>
                    s.workoutExerciseId.equals(e.id) &
                    s.deletedAt.isNull() &
                    s.isCompleted.equals(true),
              ))
              .get();
      if (sets.isNotEmpty)
        result.add(
          ExerciseHistoryEntry(e, r.readTable(db.workoutSessions), sets.length),
        );
    }
    return result;
  }

  bool compatible(
    ExerciseCatalogData source,
    ExerciseCatalogData target, {
    String? sourceVariant,
    String? targetVariant,
  }) =>
      effectiveLoggingMetric(
            exercise: source,
            equipmentVariant: sourceVariant,
          ) ==
          effectiveLoggingMetric(
            exercise: target,
            equipmentVariant: targetVariant,
          ) &&
      source.supportsWeightedBodyweight == target.supportsWeightedBodyweight &&
      isMachineAssistedPullup(source.slug) ==
          isMachineAssistedPullup(target.slug);

  Future<ExerciseHistoryPreview> preview({
    required int sourceId,
    required int targetId,
    required Set<int> entryIds,
    String? equipment,
  }) async {
    if (sourceId == targetId || entryIds.isEmpty)
      throw StateError('Select a different exercise and at least one entry.');
    final source = await (db.select(
      db.exerciseCatalog,
    )..where((e) => e.id.equals(sourceId))).getSingle();
    final target = await (db.select(
      db.exerciseCatalog,
    )..where((e) => e.id.equals(targetId))).getSingle();
    if (equipment != null &&
        !equipmentVariantsFor(target).contains(equipment)) {
      throw StateError(
        'Select equipment supported by the destination exercise.',
      );
    }
    final selected = (await entries(
      sourceId,
    )).where((e) => entryIds.contains(e.exercise.id)).toList();
    if (selected.length != entryIds.length)
      throw StateError('The selected history changed. Reopen the preview.');
    final fingerprints = <String, String>{};
    for (final entry in selected) {
      final variant = entry.exercise.equipmentVariant ?? source.modality;
      if (equipment == null &&
          !equipmentVariantsFor(target).contains(variant)) {
        throw StateError(
          'Choose the correct destination equipment before transferring.',
        );
      }
      if (!compatible(
        source,
        target,
        sourceVariant: variant,
        targetVariant: equipment ?? variant,
      )) {
        throw StateError(
          'These exercises use incompatible measurements or load accounting. No values have been converted.',
        );
      }
      if (source.deletedAt != null || target.deletedAt != null)
        throw StateError('An exercise is no longer available.');
      fingerprints[entry.exercise.syncUuid!] = await _fingerprint(
        entry.exercise.id,
      );
    }
    return ExerciseHistoryPreview(
      source: source,
      target: target,
      entries: selected,
      fingerprints: fingerprints,
      equipment: equipment,
    );
  }

  Future<int> transfer(
    ExerciseHistoryPreview preview,
  ) => db.transaction(() async {
    final fresh = await this.preview(
      sourceId: preview.source.id,
      targetId: preview.target.id,
      entryIds: preview.entries.map((e) => e.exercise.id).toSet(),
      equipment: preview.equipment,
    );
    if (jsonEncode(fresh.fingerprints) != jsonEncode(preview.fingerprints)) {
      throw StateError('This history changed. Reopen the preview.');
    }
    final codec = PortableWorkoutPlan(db);
    final changes = <Map<String, Object?>>[];
    for (final entry in fresh.entries) {
      final old = entry.exercise;
      final variant =
          preview.equipment ?? old.equipmentVariant ?? fresh.source.modality;
      final machine = variant == (old.equipmentVariant ?? fresh.source.modality)
          ? old.machineConfigJson
          : null;
      await (db.update(
        db.workoutExercises,
      )..where((e) => e.id.equals(old.id))).write(
        WorkoutExercisesCompanion(
          exerciseId: Value(fresh.target.id),
          equipmentVariant: Value(variant),
          machineConfigJson: Value(machine),
        ),
      );
      changes.add({
        'row': old.syncUuid,
        'source': await codec.exerciseRef(old.exerciseId),
        'target': await codec.exerciseRef(fresh.target.id),
        'equipment': old.equipmentVariant,
        'machine': old.machineConfigJson,
        'after': await _fingerprint(old.id),
      });
      await db
          .into(db.workoutReportEvents)
          .insert(
            WorkoutReportEventsCompanion.insert(
              sessionId: old.sessionId,
              kind: 'history_correction',
              detailJson: jsonEncode({
                'rowId': old.id,
                'exerciseId': fresh.target.id,
                'name': fresh.target.name,
                'muscle': fresh.target.primaryMuscle,
              }),
              occurredAt: clock.now(),
            ),
          );
    }
    final snapshots = <Map<String, Object?>>[];
    for (final id in fresh.entries.map((e) => e.session.id).toSet()) {
      final s = await (db.select(
        db.workoutBehaviorSnapshots,
      )..where((s) => s.sessionId.equals(id))).getSingleOrNull();
      if (s != null) {
        final json = jsonDecode(s.snapshotJson) as Map<String, dynamic>;
        json['corrected'] = true;
        final after = jsonEncode(json);
        snapshots.add({
          'row': s.syncUuid,
          'before': s.snapshotJson,
          'after': after,
        });
        await (db.update(
          db.workoutBehaviorSnapshots,
        )..where((r) => r.id.equals(s.id))).write(
          WorkoutBehaviorSnapshotsCompanion(snapshotJson: Value(after)),
        );
      }
    }
    return db
        .into(db.exerciseHistoryTransfers)
        .insert(
          ExerciseHistoryTransfersCompanion.insert(
            payloadJson: jsonEncode({
              'version': 1,
              'changes': changes,
              'snapshots': snapshots,
            }),
            createdAt: clock.now(),
          ),
        );
  });

  Future<void> undo(int transferId) => db.transaction(() async {
    final audit = await (db.select(
      db.exerciseHistoryTransfers,
    )..where((t) => t.id.equals(transferId))).getSingle();
    if (audit.undoneAt != null) return;
    final payload = jsonDecode(audit.payloadJson) as Map;
    final changes = (payload['changes'] as List).cast<Map>();
    final rows = <String, WorkoutExerciseData>{};
    for (final change in changes) {
      final row =
          await (db.select(db.workoutExercises)
                ..where((e) => e.syncUuid.equals(change['row'] as String)))
              .getSingleOrNull();
      if (row == null || await _fingerprint(row.id) != change['after']) {
        throw StateError(
          'Transferred entries were changed. Undo is no longer available.',
        );
      }
      final session = await (db.select(
        db.workoutSessions,
      )..where((s) => s.id.equals(row.sessionId))).getSingle();
      if (session.endedAt == null || session.deletedAt != null)
        throw StateError('This workout is being edited.');
      rows[change['row'] as String] = row;
    }
    for (final change in changes) {
      final row = rows[change['row']]!;
      final originalId = await PortableWorkoutPlan(
        db,
      ).exerciseId(change['source'] as String);
      await (db.update(
        db.workoutExercises,
      )..where((e) => e.id.equals(row.id))).write(
        WorkoutExercisesCompanion(
          exerciseId: Value(originalId),
          equipmentVariant: Value(change['equipment'] as String?),
          machineConfigJson: Value(change['machine'] as String?),
        ),
      );
      final events =
          await (db.select(db.workoutReportEvents)
                ..where(
                  (e) =>
                      e.sessionId.equals(row.sessionId) &
                      e.kind.equals('history_correction'),
                )
                ..orderBy([(e) => OrderingTerm.desc(e.id)]))
              .get();
      final last = events
          .where((e) => (jsonDecode(e.detailJson) as Map)['rowId'] == row.id)
          .firstOrNull;
      if (last != null)
        await (db.delete(
          db.workoutReportEvents,
        )..where((e) => e.id.equals(last.id))).go();
    }
    for (final snapshot in (payload['snapshots'] as List).cast<Map>()) {
      final s =
          await (db.select(db.workoutBehaviorSnapshots)
                ..where((s) => s.syncUuid.equals(snapshot['row'] as String)))
              .getSingleOrNull();
      if (s != null && s.snapshotJson == snapshot['after']) {
        await (db.update(
          db.workoutBehaviorSnapshots,
        )..where((r) => r.id.equals(s.id))).write(
          WorkoutBehaviorSnapshotsCompanion(
            snapshotJson: Value(snapshot['before'] as String),
          ),
        );
      }
    }
    await (db.update(db.exerciseHistoryTransfers)
          ..where((t) => t.id.equals(transferId)))
        .write(ExerciseHistoryTransfersCompanion(undoneAt: Value(clock.now())));
  });

  Future<ExerciseHistoryTransferData?> lastTransfer(int exerciseId) async {
    final ref = await PortableWorkoutPlan(db).exerciseRef(exerciseId);
    final rows =
        await (db.select(db.exerciseHistoryTransfers)
              ..where((t) => t.undoneAt.isNull() & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    return rows
        .where(
          (r) => ((jsonDecode(r.payloadJson) as Map)['changes'] as List)
              .cast<Map>()
              .any((c) => c['source'] == ref || c['target'] == ref),
        )
        .firstOrNull;
  }

  /// Deleting a workout also erases the undo payloads that contain its data.
  Future<void> forgetSession(int sessionId) async {
    final rows = await (db.select(
      db.workoutExercises,
    )..where((e) => e.sessionId.equals(sessionId))).get();
    final refs = rows.map((e) => e.syncUuid).nonNulls.toSet();
    final audits = await db.select(db.exerciseHistoryTransfers).get();
    for (final audit in audits) {
      final changes =
          ((jsonDecode(audit.payloadJson) as Map)['changes'] as List)
              .cast<Map>();
      if (changes.any((c) => refs.contains(c['row']))) {
        await (db.delete(
          db.exerciseHistoryTransfers,
        )..where((t) => t.id.equals(audit.id))).go();
      }
    }
  }

  Future<String> _fingerprint(int rowId) async {
    final row = await (db.select(
      db.workoutExercises,
    )..where((e) => e.id.equals(rowId))).getSingle();
    final sets =
        await (db.select(db.setEntries)
              ..where((s) => s.workoutExerciseId.equals(rowId))
              ..orderBy([(s) => OrderingTerm.asc(s.syncUuid)]))
            .get();
    final ids = sets.map((s) => s.id).toList();
    final bands =
        await (db.select(db.setBands)
              ..where((b) => b.setEntryId.isIn(ids))
              ..orderBy([(b) => OrderingTerm.asc(b.syncUuid)]))
            .get();
    final accessories =
        await (db.select(db.setAccessories)
              ..where((b) => b.setEntryId.isIn(ids))
              ..orderBy([(b) => OrderingTerm.asc(b.syncUuid)]))
            .get();
    Map<String, dynamic> values(Map<String, dynamic> json) => Map.of(json)
      ..remove('updatedAt')
      ..remove('syncedAt')
      ..remove('id')
      ..remove('sessionId')
      ..remove('exerciseId')
      ..remove('workoutExerciseId')
      ..remove('setEntryId')
      ..remove('programExerciseSlotId')
      ..remove('rotationAssignmentId')
      ..remove('bandId')
      ..remove('accessoryId');
    final session = await (db.select(
      db.workoutSessions,
    )..where((s) => s.id.equals(row.sessionId))).getSingle();
    final rotation = row.rotationAssignmentId == null
        ? null
        : await (db.select(db.rotationAssignments)
                ..where((r) => r.id.equals(row.rotationAssignmentId!)))
              .getSingleOrNull();
    final bandValues = <Map<String, dynamic>>[];
    for (final entry in bands) {
      final band = await (db.select(
        db.bands,
      )..where((b) => b.id.equals(entry.bandId))).getSingle();
      bandValues.add({
        ...values(entry.toJson()),
        'band': band.isCustom
            ? band.syncUuid
            : '${band.color}|${band.tensionKg}',
        'set': sets.firstWhere((s) => s.id == entry.setEntryId).syncUuid,
      });
    }
    final accessoryValues = <Map<String, dynamic>>[];
    for (final entry in accessories) {
      final accessory = await (db.select(
        db.accessories,
      )..where((a) => a.id.equals(entry.accessoryId))).getSingle();
      accessoryValues.add({
        ...values(entry.toJson()),
        'accessory': accessory.isCustom ? accessory.syncUuid : accessory.kind,
        'set': sets.firstWhere((s) => s.id == entry.setEntryId).syncUuid,
      });
    }
    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'row': values(row.toJson()),
              'session': session.syncUuid,
              'rotation': rotation?.syncUuid,
              'exercise': await PortableWorkoutPlan(
                db,
              ).exerciseRef(row.exerciseId),
              'slot': await PortableWorkoutPlan(
                db,
              ).slotRef(row.programExerciseSlotId),
              'sets': sets.map((s) => values(s.toJson())).toList(),
              'bands': bandValues,
              'accessories': accessoryValues,
            }),
          ),
        )
        .toString();
  }
}
