import 'dart:convert';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';

/// Stored plans use catalogue natural keys and sync UUIDs, never local IDs.
class PortableWorkoutPlan {
  PortableWorkoutPlan(this.db);
  final AppDatabase db;

  Future<String> exerciseRef(int id) async {
    final e = await (db.select(
      db.exerciseCatalog,
    )..where((e) => e.id.equals(id))).getSingle();
    if (!e.isCustom && e.slug != null) return 'slug:${e.slug}';
    if (e.syncUuid == null)
      throw StateError('Exercise has no portable identity.');
    return 'uuid:${e.syncUuid}';
  }

  Future<int> exerciseId(String ref) async {
    final rows = db.select(db.exerciseCatalog);
    if (ref.startsWith('slug:')) {
      rows.where((e) => e.slug.equals(ref.substring(5)));
    } else if (ref.startsWith('uuid:')) {
      rows.where((e) => e.syncUuid.equals(ref.substring(5)));
    } else {
      throw const FormatException('Unknown exercise reference');
    }
    final e = await rows.getSingleOrNull();
    if (e == null)
      throw StateError(
        'An exercise in this plan is unavailable. Sync and reopen it.',
      );
    return e.id;
  }

  Future<String?> slotRef(int? id) async => id == null
      ? null
      : (await (db.select(
          db.programExerciseSlots,
        )..where((s) => s.id.equals(id))).getSingleOrNull())?.syncUuid;

  Future<String> encode(PlannedSessionSnapshot plan) async => jsonEncode({
    'version': 1,
    'name': plan.name,
    'exercises': [
      for (final e in plan.exercises)
        {
          'exercise': await exerciseRef(e.exerciseId),
          'slot': await slotRef(e.programExerciseSlotId),
          'rotation': e.rotationAssignmentId == null
              ? null
              : (await (db.select(db.rotationAssignments)
                          ..where((r) => r.id.equals(e.rotationAssignmentId!)))
                        .getSingleOrNull())
                    ?.syncUuid,
          'order': e.orderIndex,
          'rest': e.restSeconds,
          'role': e.slotRole,
          'method': e.trainingMethod,
          'why': e.why,
          'advanced': e.allowsAdvancedTechniques,
          'variant': e.equipmentVariant,
          'segment': e.sessionSegment,
          'superset': e.supersetGroup,
          'wave': e.waveIndex,
          'waves': e.waveCount,
          'sets': [
            for (final s in e.sets)
              {
                'index': s.index,
                'min': s.repsMin,
                'max': s.repsMax,
                'weight': s.weightKg,
                'rpe': s.rpeX10,
                'rir': s.rir,
                'percent': s.percentOf1Rm,
                'warmup': s.isWarmup,
                'type': s.setType,
                'intent': s.intent,
                'meta': s.setTypeMetaJson,
              },
          ],
        },
    ],
  });

  Future<PlannedSessionSnapshot> decode(String raw) async {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['version'] != 1)
      throw const FormatException('Unknown plan version');
    return PlannedSessionSnapshot(
      name: json['name'] as String,
      exercises: [
        for (final e in (json['exercises'] as List).cast<Map>())
          PlannedExerciseSnapshot(
            exerciseId: await exerciseId(e['exercise'] as String),
            programExerciseSlotId: e['slot'] == null
                ? null
                : (await (db.select(db.programExerciseSlots)..where(
                            (s) => s.syncUuid.equals(e['slot'] as String),
                          ))
                          .getSingleOrNull())
                      ?.id,
            rotationAssignmentId: e['rotation'] == null
                ? null
                : (await (db.select(db.rotationAssignments)..where(
                            (s) => s.syncUuid.equals(e['rotation'] as String),
                          ))
                          .getSingleOrNull())
                      ?.id,
            orderIndex: e['order'] as int,
            restSeconds: e['rest'] as int,
            slotRole: e['role'] as String,
            trainingMethod: e['method'] as String,
            why: e['why'] as String,
            allowsAdvancedTechniques: e['advanced'] as bool,
            equipmentVariant: e['variant'] as String?,
            sessionSegment: e['segment'] as String?,
            supersetGroup: e['superset'] as int?,
            waveIndex: e['wave'] as int?,
            waveCount: e['waves'] as int?,
            sets: [
              for (final s in (e['sets'] as List).cast<Map>())
                PlannedSetSnapshot(
                  index: s['index'] as int,
                  repsMin: s['min'] as int?,
                  repsMax: s['max'] as int?,
                  weightKg: (s['weight'] as num?)?.toDouble(),
                  rpeX10: s['rpe'] as int?,
                  rir: s['rir'] as int?,
                  percentOf1Rm: (s['percent'] as num?)?.toDouble(),
                  isWarmup: s['warmup'] as bool,
                  setType: s['type'] as String,
                  intent: s['intent'] as String,
                  setTypeMetaJson: s['meta'] as String?,
                ),
            ],
          ),
      ],
    );
  }
}

PlannedExerciseSnapshot copyPlannedExercise(
  PlannedExerciseSnapshot e, {
  int? exerciseId,
  int? orderIndex,
  List<PlannedSetSnapshot>? sets,
  String? equipmentVariant,
  int? supersetGroup,
}) => PlannedExerciseSnapshot(
  exerciseId: exerciseId ?? e.exerciseId,
  orderIndex: orderIndex ?? e.orderIndex,
  restSeconds: e.restSeconds,
  slotRole: e.slotRole,
  trainingMethod: e.trainingMethod,
  why: e.why,
  sets: sets ?? e.sets,
  allowsAdvancedTechniques: e.allowsAdvancedTechniques,
  programExerciseSlotId: e.programExerciseSlotId,
  rotationAssignmentId: e.rotationAssignmentId,
  equipmentVariant: equipmentVariant ?? e.equipmentVariant,
  sessionSegment: e.sessionSegment,
  supersetGroup: supersetGroup ?? e.supersetGroup,
  waveIndex: e.waveIndex,
  waveCount: e.waveCount,
);
