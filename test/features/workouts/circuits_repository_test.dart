import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/circuits_repository.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import '../../support/test_database.dart';

void main() {
  late AppDatabase db;
  late CircuitsRepository circuitsRepo;
  late WorkoutsRepository workoutsRepo;
  late TemplatesRepository templatesRepo;

  setUp(() async {
    db = await openTestDatabase();
    circuitsRepo = CircuitsRepository(db);
    workoutsRepo = WorkoutsRepository(db, SystemClock());
    templatesRepo = TemplatesRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CircuitsRepository CRUD', () {
    test('createCircuit and getCircuit', () async {
      final circuit = await circuitsRepo.createCircuit(
        name: 'Upper Body Blast',
        rounds: 4,
        restSeconds: 120,
        notes: 'Keep rest tight',
        exercises: const [
          CircuitExerciseInput(exerciseId: 1, targetReps: 10, targetWeightKg: 80.0),
          CircuitExerciseInput(exerciseId: 2, targetReps: 12),
          CircuitExerciseInput(exerciseId: 3, targetReps: 15),
        ],
      );

      final fetched = await circuitsRepo.getCircuitById(circuit.id);
      expect(fetched, isNotNull);
      expect(fetched!.name, 'Upper Body Blast');
      expect(fetched.rounds, 4);
      expect(fetched.restSeconds, 120);

      final exercises = await circuitsRepo.getCircuitExercises(circuit.id);
      expect(exercises.length, 3);
      expect(exercises[0].exerciseId, 1);
      expect(exercises[0].targetReps, 10);
      expect(exercises[0].targetWeightKg, 80.0);
      expect(exercises[1].exerciseId, 2);
      expect(exercises[2].exerciseId, 3);
    });

    test('updateCircuit replaces exercises and metadata', () async {
      final circuit = await circuitsRepo.createCircuit(
        name: 'Initial Name',
        rounds: 3,
        restSeconds: 90,
        exercises: const [
          CircuitExerciseInput(exerciseId: 1, targetReps: 8, targetWeightKg: 60.0),
        ],
      );

      await circuitsRepo.updateCircuit(
        circuit.id,
        name: 'Updated Name',
        rounds: 5,
        restSeconds: 150,
        exercises: const [
          CircuitExerciseInput(exerciseId: 2, targetReps: 10),
          CircuitExerciseInput(exerciseId: 3, targetReps: 12),
        ],
      );

      final updated = await circuitsRepo.getCircuitById(circuit.id);
      expect(updated!.name, 'Updated Name');
      expect(updated.rounds, 5);
      expect(updated.restSeconds, 150);

      final exercises = await circuitsRepo.getCircuitExercises(circuit.id);
      expect(exercises.length, 2);
      expect(exercises[0].exerciseId, 2);
      expect(exercises[1].exerciseId, 3);
    });

    test('deleteCircuit removes circuit and its exercises', () async {
      final circuit = await circuitsRepo.createCircuit(
        name: 'To Delete',
        rounds: 3,
        restSeconds: 60,
        exercises: const [
          CircuitExerciseInput(exerciseId: 1, targetReps: 10),
        ],
      );

      await circuitsRepo.deleteCircuit(circuit.id);
      final fetched = await circuitsRepo.getCircuitById(circuit.id);
      expect(fetched, isNull);

      final exercises = await circuitsRepo.getCircuitExercises(circuit.id);
      expect(exercises, isEmpty);
    });
  });

  group('Circuit integration with Sessions and Templates', () {
    test('addCircuitToSession creates linked superset group with planned sets', () async {
      final circuit = await circuitsRepo.createCircuit(
        name: 'Core Circuit',
        rounds: 3,
        restSeconds: 90,
        exercises: const [
          CircuitExerciseInput(exerciseId: 1, targetReps: 10, targetWeightKg: 50.0),
          CircuitExerciseInput(exerciseId: 2, targetReps: 12),
        ],
      );

      final sessionId = await workoutsRepo.startSession();
      final exerciseIds = await circuitsRepo.addCircuitToSession(
        sessionId: sessionId,
        circuitId: circuit.id,
      );

      expect(exerciseIds.length, 2);

      final sessionExercises = await workoutsRepo.watchSessionExercises(sessionId).first;
      expect(sessionExercises.length, 2);
      expect(sessionExercises[0].supersetGroup, isNotNull);
      expect(sessionExercises[0].supersetGroup, sessionExercises[1].supersetGroup);
      expect(sessionExercises[0].targetRestSeconds, 90);

      // Verify each exercise has 3 sets planned
      final sets1 = await workoutsRepo.watchSetsForWorkoutExercise(sessionExercises[0].id).first;
      expect(sets1.length, 3);
      expect(sets1[0].reps, 10);
      expect(sets1[0].weightKg, 50.0);

      final sets2 = await workoutsRepo.watchSetsForWorkoutExercise(sessionExercises[1].id).first;
      expect(sets2.length, 3);
      expect(sets2[0].reps, 12);
    });

    test('addCircuitToTemplate creates linked template exercises with planned sets', () async {
      final circuit = await circuitsRepo.createCircuit(
        name: 'Arms Circuit',
        rounds: 4,
        restSeconds: 75,
        exercises: const [
          CircuitExerciseInput(exerciseId: 1, targetReps: 8, targetWeightKg: 40.0),
          CircuitExerciseInput(exerciseId: 3, targetReps: 12, targetWeightKg: 20.0),
        ],
      );

      final template = await templatesRepo.createTemplate(name: 'Upper Body Routine');
      final teIds = await circuitsRepo.addCircuitToTemplate(
        templateId: template.id,
        circuitId: circuit.id,
      );

      expect(teIds.length, 2);

      final templateExercises = await templatesRepo.watchTemplateExercises(template.id).first;
      expect(templateExercises.length, 2);
      expect(templateExercises[0].supersetGroup, isNotNull);
      expect(templateExercises[0].supersetGroup, templateExercises[1].supersetGroup);
      expect(templateExercises[0].targetRestSeconds, 75);
      expect(templateExercises[0].targetSets, 4);

      final sets1 = await templatesRepo.getTemplateSets(templateExercises[0].id);
      expect(sets1.length, 4);
      expect(sets1[0].targetReps, 8);
      expect(sets1[0].targetWeightKg, 40.0);
    });

    test('startSessionFromCircuit launches workout with the circuit', () async {
      final circuit = await circuitsRepo.createCircuit(
        name: 'Full Body Circuit',
        rounds: 3,
        restSeconds: 100,
        exercises: const [
          CircuitExerciseInput(exerciseId: 1, targetReps: 10, targetWeightKg: 60.0),
          CircuitExerciseInput(exerciseId: 2, targetReps: 10),
          CircuitExerciseInput(exerciseId: 3, targetReps: 15),
        ],
      );

      final sessionId = await circuitsRepo.startSessionFromCircuit(circuit.id);
      final session = await workoutsRepo.watchActiveSession().first;
      expect(session, isNotNull);
      expect(session!.id, sessionId);
      expect(session.name, 'Full Body Circuit');

      final sessionExercises = await workoutsRepo.watchSessionExercises(sessionId).first;
      expect(sessionExercises.length, 3);
      expect(sessionExercises[0].supersetGroup, isNotNull);
      expect(sessionExercises[0].supersetGroup, sessionExercises[1].supersetGroup);
      expect(sessionExercises[1].supersetGroup, sessionExercises[2].supersetGroup);
    });
  });
}
