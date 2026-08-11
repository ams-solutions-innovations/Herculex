import 'package:drift/drift.dart';

import '../../../data/local/database.dart';
import '../domain/exercise_rotation.dart';

/// Exercise rotation pools (V2 §12). CRUD plus week-resolution: given a
/// program week, which pool member is the active exercise.
class RotationsRepository {
  final AppDatabase _db;
  RotationsRepository(this._db);

  Stream<List<ExerciseRotationData>> watchRotations() {
    return (_db.select(_db.exerciseRotations)
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Stream<List<RotationMemberData>> watchMembers(int rotationId) {
    return (_db.select(_db.rotationMembers)
          ..where((t) => t.rotationId.equals(rotationId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .watch();
  }

  Future<int> createRotation({
    required String name,
    String? movementPattern,
    int rotateEveryWeeks = 2,
    required List<int> exerciseIds,
  }) async {
    return _db.transaction(() async {
      final id = await _db.into(_db.exerciseRotations).insert(
            ExerciseRotationsCompanion.insert(
              name: name,
              movementPattern: Value(movementPattern),
              rotateEveryWeeks: Value(rotateEveryWeeks.clamp(1, 4)),
            ),
          );
      for (final (i, exId) in exerciseIds.indexed) {
        await _db.into(_db.rotationMembers).insert(
              RotationMembersCompanion.insert(
                  rotationId: id, exerciseId: exId, orderIndex: i),
            );
      }
      return id;
    });
  }

  Future<void> updateRotation(
    int id, {
    required String name,
    String? movementPattern,
    required int rotateEveryWeeks,
  }) async {
    await (_db.update(_db.exerciseRotations)..where((t) => t.id.equals(id)))
        .write(ExerciseRotationsCompanion(
      name: Value(name),
      movementPattern: Value(movementPattern),
      rotateEveryWeeks: Value(rotateEveryWeeks.clamp(1, 4)),
    ));
  }

  Future<void> addMember(int rotationId, int exerciseId) async {
    final existing = await (_db.select(_db.rotationMembers)
          ..where((t) => t.rotationId.equals(rotationId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    final nextIndex = existing == null ? 0 : existing.orderIndex + 1;
    await _db.into(_db.rotationMembers).insert(
          RotationMembersCompanion.insert(
            rotationId: rotationId,
            exerciseId: exerciseId,
            orderIndex: nextIndex,
          ),
        );
  }

  Future<void> removeMember(int memberId) async {
    await (_db.delete(_db.rotationMembers)
          ..where((t) => t.id.equals(memberId)))
        .go();
  }

  Future<void> deleteRotation(int id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.rotationMembers)
            ..where((t) => t.rotationId.equals(id)))
          .go();
      await (_db.update(_db.programDayExercises)
            ..where((t) => t.rotationId.equals(id)))
          .write(const ProgramDayExercisesCompanion(rotationId: Value(null)));
      await (_db.delete(_db.exerciseRotations)..where((t) => t.id.equals(id)))
          .go();
    });
  }

  /// The exercise that should be performed for [rotationId] in program week
  /// [weekIndex] (0-based). Falls back to null when the pool is empty.
  Future<ExerciseCatalogData?> activeExerciseFor({
    required int rotationId,
    required int weekIndex,
  }) async {
    final rotation = await (_db.select(_db.exerciseRotations)
          ..where((t) => t.id.equals(rotationId)))
        .getSingleOrNull();
    if (rotation == null) return null;
    final members = await (_db.select(_db.rotationMembers)
          ..where((t) => t.rotationId.equals(rotationId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
    if (members.isEmpty) return null;
    final idx = ExerciseRotation.activeMemberIndex(
      weekIndex: weekIndex,
      memberCount: members.length,
      rotateEveryWeeks: rotation.rotateEveryWeeks,
    );
    return (_db.select(_db.exerciseCatalog)
          ..where((t) => t.id.equals(members[idx].exerciseId)))
        .getSingleOrNull();
  }
}
