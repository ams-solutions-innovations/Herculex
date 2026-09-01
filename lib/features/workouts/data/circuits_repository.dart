import 'package:drift/drift.dart';

import 'package:herculex/data/local/database.dart';

class CircuitExerciseInput {
  final int exerciseId;
  final int? targetReps;
  final double? targetWeightKg;

  const CircuitExerciseInput({
    required this.exerciseId,
    this.targetReps,
    this.targetWeightKg,
  });
}

class CircuitsRepository {
  final AppDatabase _db;
  CircuitsRepository(this._db);

  Stream<List<WorkoutCircuitData>> watchCircuits() {
    return (_db.select(_db.workoutCircuits)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<List<WorkoutCircuitData>> getCircuits() {
    return (_db.select(_db.workoutCircuits)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  Future<WorkoutCircuitData?> getCircuitById(int id) {
    return (_db.select(
      _db.workoutCircuits,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
  }

  Stream<List<CircuitExerciseData>> watchCircuitExercises(int circuitId) {
    return (_db.select(_db.circuitExercises)
          ..where((t) => t.circuitId.equals(circuitId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .watch();
  }

  Future<List<CircuitExerciseData>> getCircuitExercises(int circuitId) {
    return (_db.select(_db.circuitExercises)
          ..where((t) => t.circuitId.equals(circuitId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
        .get();
  }

  Future<WorkoutCircuitData> createCircuit({
    required String name,
    String? notes,
    int rounds = 3,
    int restSeconds = 90,
    required List<CircuitExerciseInput> exercises,
  }) async {
    return _db.transaction(() async {
      final circuitId = await _db
          .into(_db.workoutCircuits)
          .insert(
            WorkoutCircuitsCompanion.insert(
              name: name,
              notes: Value(notes),
              rounds: Value(rounds),
              restSeconds: Value(restSeconds),
              createdAt: Value(DateTime.now()),
            ),
          );

      for (var i = 0; i < exercises.length; i++) {
        final item = exercises[i];
        await _db
            .into(_db.circuitExercises)
            .insert(
              CircuitExercisesCompanion.insert(
                circuitId: circuitId,
                exerciseId: item.exerciseId,
                orderIndex: i,
                targetReps: Value(item.targetReps),
                targetWeightKg: Value(item.targetWeightKg),
              ),
            );
      }

      return (_db.select(
        _db.workoutCircuits,
      )..where((t) => t.id.equals(circuitId))).getSingle();
    });
  }

  Future<void> updateCircuit(
    int circuitId, {
    String? name,
    String? notes,
    int? rounds,
    int? restSeconds,
    List<CircuitExerciseInput>? exercises,
  }) async {
    await _db.transaction(() async {
      await (_db.update(
        _db.workoutCircuits,
      )..where((t) => t.id.equals(circuitId))).write(
        WorkoutCircuitsCompanion(
          name: name != null ? Value(name) : const Value.absent(),
          notes: notes != null ? Value(notes) : const Value.absent(),
          rounds: rounds != null ? Value(rounds) : const Value.absent(),
          restSeconds: restSeconds != null
              ? Value(restSeconds)
              : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (exercises != null) {
        await (_db.delete(
          _db.circuitExercises,
        )..where((t) => t.circuitId.equals(circuitId))).go();
        for (var i = 0; i < exercises.length; i++) {
          final item = exercises[i];
          await _db
              .into(_db.circuitExercises)
              .insert(
                CircuitExercisesCompanion.insert(
                  circuitId: circuitId,
                  exerciseId: item.exerciseId,
                  orderIndex: i,
                  targetReps: Value(item.targetReps),
                  targetWeightKg: Value(item.targetWeightKg),
                ),
              );
        }
      }
    });
  }

  Future<void> deleteCircuit(int circuitId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.circuitExercises,
      )..where((t) => t.circuitId.equals(circuitId))).go();
      await (_db.delete(
        _db.workoutCircuits,
      )..where((t) => t.id.equals(circuitId))).go();
    });
  }

  /// Adds all exercises in a circuit to an active workout session as a linked superset group.
  Future<List<int>> addCircuitToSession({
    required int sessionId,
    required int circuitId,
  }) async {
    final circuit = await getCircuitById(circuitId);
    if (circuit == null) return [];
    final exercises = await getCircuitExercises(circuitId);
    if (exercises.isEmpty) return [];

    final existingSessionExercises = await (_db.select(
      _db.workoutExercises,
    )..where((t) => t.sessionId.equals(sessionId))).get();

    final maxGroup = existingSessionExercises
        .map((r) => r.supersetGroup ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final group = maxGroup + 1;

    final createdIds = <int>[];

    await _db.transaction(() async {
      var nextOrder = existingSessionExercises.length;
      for (final ce in exercises) {
        final weId = await _db
            .into(_db.workoutExercises)
            .insert(
              WorkoutExercisesCompanion.insert(
                sessionId: sessionId,
                exerciseId: ce.exerciseId,
                orderIndex: nextOrder++,
                supersetGroup: Value(group),
                targetRestSeconds: Value(circuit.restSeconds),
              ),
            );
        createdIds.add(weId);

        final targetReps = ce.targetReps ?? 0;
        final targetWeight = ce.targetWeightKg ?? 0.0;
        final roundsCount = circuit.rounds > 0 ? circuit.rounds : 3;

        for (var r = 1; r <= roundsCount; r++) {
          await _db
              .into(_db.setEntries)
              .insert(
                SetEntriesCompanion.insert(
                  workoutExerciseId: weId,
                  setIndex: r,
                  reps: targetReps,
                  weightKg: targetWeight,
                  isCompleted: const Value(false),
                ),
              );
        }
      }
    });

    return createdIds;
  }

  /// Adds all exercises in a circuit to a template as a linked superset group.
  Future<List<int>> addCircuitToTemplate({
    required int templateId,
    required int circuitId,
  }) async {
    final circuit = await getCircuitById(circuitId);
    if (circuit == null) return [];
    final exercises = await getCircuitExercises(circuitId);
    if (exercises.isEmpty) return [];

    final existingTemplateExercises = await (_db.select(
      _db.templateExercises,
    )..where((t) => t.templateId.equals(templateId))).get();

    final maxGroup = existingTemplateExercises
        .map((r) => r.supersetGroup ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final group = maxGroup + 1;

    final createdIds = <int>[];

    await _db.transaction(() async {
      var nextOrder = existingTemplateExercises.length;
      final roundsCount = circuit.rounds > 0 ? circuit.rounds : 3;

      for (final ce in exercises) {
        final teId = await _db
            .into(_db.templateExercises)
            .insert(
              TemplateExercisesCompanion.insert(
                templateId: templateId,
                exerciseId: ce.exerciseId,
                orderIndex: nextOrder++,
                targetSets: Value(roundsCount),
                targetRepsMin: Value(ce.targetReps),
                targetRestSeconds: Value(circuit.restSeconds),
                supersetGroup: Value(group),
              ),
            );
        createdIds.add(teId);

        for (var r = 1; r <= roundsCount; r++) {
          await _db
              .into(_db.templateSets)
              .insert(
                TemplateSetsCompanion.insert(
                  templateExerciseId: teId,
                  setOrder: r,
                  setType: const Value('standard'),
                  targetReps: Value(ce.targetReps),
                  targetWeightKg: Value(ce.targetWeightKg),
                  isWarmup: const Value(false),
                ),
              );
        }
      }
    });

    return createdIds;
  }

  /// Starts a live workout session pre-populated with this circuit.
  Future<int> startSessionFromCircuit(
    int circuitId, {
    DateTime? startedAt,
    int? gymId,
    String? notes,
  }) async {
    final circuit = await getCircuitById(circuitId);
    if (circuit == null) throw StateError('Circuit not found');

    return _db.transaction(() async {
      final sessionId = await _db
          .into(_db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              name: Value(circuit.name),
              startedAt: startedAt ?? DateTime.now(),
              gymId: Value(gymId),
              notes: Value(notes ?? circuit.notes),
            ),
          );

      await addCircuitToSession(sessionId: sessionId, circuitId: circuitId);
      return sessionId;
    });
  }
}
