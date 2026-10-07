import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';

import '../support/test_database.dart';

/// BUD-02's analytics half: "buddy sessions never double-count in
/// analytics". `TrainingSnapshot.load` (the single data path every
/// analytics/volume view has built on since the Phase 9 consolidation) reads
/// every local `workout_sessions`/`set_entries` row with no filter beyond
/// `deletedAt.isNull()` — no `buddySessionId` clause anywhere in it. That is
/// what makes the guarantee true by construction rather than by a check
/// somewhere: a buddy-linked session is not a different *kind* of session to
/// analytics, it is the same row with one extra column that nothing here
/// reads. This suite pins that fact down, so a future "let's special-case
/// buddy sessions in volume" change fails loudly here first.
///
/// Each participant's sets already live only in their own local database —
/// `test/buddy/buddy_two_device_test.dart` proves that at the choreography
/// level (separate `WorkoutSessions` rows, separate ids). There is no
/// multi-tenant local database and no merged cross-user query in this app,
/// so there is no code path left that could plausibly sum two participants'
/// sets together — this file cannot construct that scenario, because
/// nothing in the app can either.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<int> insertBenchPress(AppDatabase db) => db
      .into(db.exerciseCatalog)
      .insert(
        ExerciseCatalogCompanion.insert(
          name: 'Test Bench Press',
          primaryMuscle: 'Chest',
          equipment: 'barbell',
          mechanics: 'compound',
          force: 'push',
          plane: 'horizontal',
        ),
      );

  Future<int> insertSession(
    AppDatabase db,
    DateTime startedAt, {
    String? buddySessionId,
  }) => db
      .into(db.workoutSessions)
      .insert(
        WorkoutSessionsCompanion.insert(
          startedAt: startedAt,
          buddySessionId: Value(buddySessionId),
        ),
      );

  Future<void> insertSet(
    AppDatabase db, {
    required int sessionId,
    required int exerciseId,
    required double weightKg,
    required int reps,
  }) async {
    final weId = await db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: exerciseId,
            orderIndex: 0,
          ),
        );
    await db
        .into(db.setEntries)
        .insert(
          SetEntriesCompanion.insert(
            workoutExerciseId: weId,
            setIndex: 0,
            weightKg: weightKg,
            reps: reps,
            isCompleted: const Value(true),
          ),
        );
  }

  double totalTonnage(TrainingSnapshot snapshot, {required int sessionId}) =>
      snapshot.sets
          .where((s) => s.session.id == sessionId)
          .fold(0.0, (sum, s) => sum + s.tonnageKg);

  test('a buddy-linked session contributes identical tonnage to an otherwise '
      'identical solo session', () async {
    final db = await openTestDatabase();
    addTearDown(db.close);

    final exerciseId = await insertBenchPress(db);
    final soloId = await insertSession(db, DateTime(2026, 8, 24));
    final buddyId = await insertSession(
      db,
      DateTime(2026, 8, 24),
      buddySessionId: 'bud-session-analytics-1',
    );

    for (final sessionId in [soloId, buddyId]) {
      await insertSet(
        db,
        sessionId: sessionId,
        exerciseId: exerciseId,
        weightKg: 80,
        reps: 5,
      );
      await insertSet(
        db,
        sessionId: sessionId,
        exerciseId: exerciseId,
        weightKg: 82.5,
        reps: 5,
      );
    }

    final snapshot = await TrainingSnapshot.load(db);

    final soloTonnage = totalTonnage(snapshot, sessionId: soloId);
    final buddyTonnage = totalTonnage(snapshot, sessionId: buddyId);

    expect(soloTonnage, greaterThan(0));
    expect(
      buddyTonnage,
      soloTonnage,
      reason:
          'buddySessionId must be inert to volume — a linked session is '
          "not weighted, scaled or otherwise treated as the partner's "
          'contribution too',
    );
  });

  test('two local sessions that happen to share a buddySessionId are summed '
      'plainly, once each, never doubled', () async {
    // Not a realistic device state — each participant's sessions live on
    // separate devices, so one local database never actually holds two
    // rows for the same buddy session. Included anyway as a defence in
    // depth: if a future bug (a mishandled rejoin, a replayed local-only
    // insert) ever did produce two same-buddySessionId rows on one
    // device, this pins that analytics still just adds them — it must
    // never key off buddySessionId to dedupe, collapse or multiply.
    final db = await openTestDatabase();
    addTearDown(db.close);

    final exerciseId = await insertBenchPress(db);
    const sharedBuddyId = 'bud-session-analytics-2';
    final sessionA = await insertSession(
      db,
      DateTime(2026, 8, 24),
      buddySessionId: sharedBuddyId,
    );
    final sessionB = await insertSession(
      db,
      DateTime(2026, 8, 25),
      buddySessionId: sharedBuddyId,
    );

    await insertSet(
      db,
      sessionId: sessionA,
      exerciseId: exerciseId,
      weightKg: 80,
      reps: 5,
    );
    await insertSet(
      db,
      sessionId: sessionB,
      exerciseId: exerciseId,
      weightKg: 80,
      reps: 5,
    );

    final snapshot = await TrainingSnapshot.load(db);
    final combined = snapshot.sets
        .where((s) => s.session.id == sessionA || s.session.id == sessionB)
        .fold(0.0, (sum, s) => sum + s.tonnageKg);

    // 80 kg x 5 reps, twice: plain addition, not 4x from some
    // buddySessionId-keyed grouping collapsing then re-inflating the pair.
    expect(combined, 800);
  });
}
