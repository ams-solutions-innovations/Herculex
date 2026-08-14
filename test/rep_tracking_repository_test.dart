import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/reps/data/rep_tracking_repository.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;
  late RepTrackingRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = RepTrackingRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertObservation({
    String slug = 'pull-up',
    String source = 'wrist',
    String? placement,
    String sensorType = 'linear_acceleration',
    required DateTime recordedAt,
    int confirmedReps = 8,
  }) {
    return repo.recordObservation(
      exerciseSlug: slug,
      sessionId: 1,
      recordedAt: recordedAt,
      source: source,
      placement: placement,
      sensorType: sensorType,
      detectedReps: confirmedReps,
      confirmedReps: confirmedReps,
      confidence: 0.9,
      featuresJson: '{"meanRepPeriod":1.4}',
    );
  }

  group('consent gating (T-10-03)', () {
    test('isEnabledFor is false with no settings row at all', () async {
      expect(await repo.settings(), isNull);
      expect(await repo.isEnabledFor('pull-up'), isFalse);
    });

    test(
      'isEnabledFor is false when consent is null even though the pref row '
      'says enabled',
      () async {
        // Write the pref row directly: setExerciseEnabled would work too, but
        // this proves the gate holds against *any* enabled row, including one
        // written by a future bug or left over from an older build.
        await db
            .into(db.repTrackingExercisePrefs)
            .insert(
              RepTrackingExercisePrefsCompanion.insert(
                exerciseSlug: 'pull-up',
                enabled: const Value(true),
                updatedAt: DateTime(2026, 8, 14),
              ),
            );

        final pref = await repo.prefFor('pull-up');
        expect(pref!.enabled, isTrue);
        expect(await repo.isEnabledFor('pull-up'), isFalse);
      },
    );

    test('isEnabledFor is true only once consent and the pref agree', () async {
      await repo.grantConsent(version: 1);
      expect(await repo.isEnabledFor('pull-up'), isFalse);

      await repo.setExerciseEnabled('pull-up', true);
      expect(await repo.isEnabledFor('pull-up'), isTrue);

      await repo.setExerciseEnabled('pull-up', false);
      expect(await repo.isEnabledFor('pull-up'), isFalse);
    });

    test('grantConsent updates the single row rather than adding one', () async {
      await repo.grantConsent(version: 1);
      await repo.grantConsent(version: 2);

      final rows = await db.select(db.repTrackingSettings).get();
      expect(rows, hasLength(1));
      expect(rows.single.consentVersion, 2);
      expect(rows.single.consentGrantedAt, isNotNull);
    });
  });

  group('setExerciseEnabled eligibility guard', () {
    test('throws for an excluded slug', () async {
      await repo.grantConsent(version: 1);
      expect(
        () => repo.setExerciseEnabled('bench-dip', true),
        throwsArgumentError,
      );
      expect(
        () => repo.setExerciseEnabled('band-assisted-dip', true),
        throwsArgumentError,
      );
      expect(await db.select(db.repTrackingExercisePrefs).get(), isEmpty);
    });

    test('is idempotent for an eligible slug', () async {
      await repo.setExerciseEnabled('ring-dips', true);
      await repo.setExerciseEnabled('ring-dips', false);
      final rows = await db.select(db.repTrackingExercisePrefs).get();
      expect(rows, hasLength(1));
      expect(rows.single.enabled, isFalse);
    });
  });

  group('revokeConsent (T-10-04)', () {
    test('leaves zero prefs, zero observations and a null consent', () async {
      await repo.grantConsent(version: 1);
      await repo.setExerciseEnabled('pull-up', true);
      await repo.setExerciseEnabled('chest-dips', true);
      await insertObservation(recordedAt: DateTime(2026, 8, 1));
      await insertObservation(recordedAt: DateTime(2026, 8, 2));
      await insertObservation(
        slug: 'chest-dips',
        recordedAt: DateTime(2026, 8, 3),
      );

      expect(await db.select(db.repTrackingExercisePrefs).get(), hasLength(2));
      expect(await db.select(db.repSetObservations).get(), hasLength(3));

      await repo.revokeConsent();

      expect(await db.select(db.repTrackingExercisePrefs).get(), isEmpty);
      expect(await db.select(db.repSetObservations).get(), isEmpty);
      expect((await repo.settings())!.consentGrantedAt, isNull);
      expect(await repo.isEnabledFor('pull-up'), isFalse);
    });
  });

  group('observationsFor', () {
    test('a null placement matches only null-placement rows', () async {
      await insertObservation(
        placement: null,
        recordedAt: DateTime(2026, 8, 1),
        confirmedReps: 5,
      );
      await insertObservation(
        placement: null,
        recordedAt: DateTime(2026, 8, 2),
        confirmedReps: 6,
      );
      // Identical on every other key component — only the placement differs.
      await insertObservation(
        placement: 'pocket_front',
        recordedAt: DateTime(2026, 8, 3),
        confirmedReps: 7,
      );

      final rows = await repo.observationsFor(
        slug: 'pull-up',
        source: 'wrist',
        placement: null,
        sensorType: 'linear_acceleration',
      );

      expect(rows, hasLength(2));
      expect(rows.map((r) => r.confirmedReps), [5, 6]);
      expect(rows.every((r) => r.placement == null), isTrue);
    });

    test('a non-null placement excludes the null-placement rows', () async {
      await insertObservation(placement: null, recordedAt: DateTime(2026, 8, 1));
      await insertObservation(
        placement: 'pocket_front',
        recordedAt: DateTime(2026, 8, 2),
        confirmedReps: 9,
      );

      final rows = await repo.observationsFor(
        slug: 'pull-up',
        source: 'wrist',
        placement: 'pocket_front',
        sensorType: 'linear_acceleration',
      );
      expect(rows, hasLength(1));
      expect(rows.single.confirmedReps, 9);
    });

    test('filters on source and sensorType exactly', () async {
      await insertObservation(recordedAt: DateTime(2026, 8, 1));
      await insertObservation(source: 'phone', recordedAt: DateTime(2026, 8, 2));
      await insertObservation(
        sensorType: 'accelerometer',
        recordedAt: DateTime(2026, 8, 3),
      );

      final wrist = await repo.observationsFor(
        slug: 'pull-up',
        source: 'wrist',
        sensorType: 'linear_acceleration',
      );
      expect(wrist, hasLength(1));

      final phone = await repo.observationsFor(
        slug: 'pull-up',
        source: 'phone',
        sensorType: 'linear_acceleration',
      );
      expect(phone, hasLength(1));

      final rawAccel = await repo.observationsFor(
        slug: 'pull-up',
        source: 'wrist',
        sensorType: 'accelerometer',
      );
      expect(rawAccel, hasLength(1));
    });

    test('orders by recordedAt ascending', () async {
      await insertObservation(
        recordedAt: DateTime(2026, 8, 5),
        confirmedReps: 3,
      );
      await insertObservation(
        recordedAt: DateTime(2026, 8, 1),
        confirmedReps: 1,
      );
      await insertObservation(
        recordedAt: DateTime(2026, 8, 3),
        confirmedReps: 2,
      );

      final rows = await repo.observationsFor(
        slug: 'pull-up',
        source: 'wrist',
        sensorType: 'linear_acceleration',
      );
      expect(rows.map((r) => r.confirmedReps), [1, 2, 3]);
    });
  });

  group('recordObservation', () {
    test('survives its set entry being deleted (no FK edge)', () async {
      // setEntryId is a plain nullable int by design: calibration history
      // must outlive a discarded set.
      await repo.recordObservation(
        exerciseSlug: 'pull-up',
        sessionId: 1,
        setEntryId: 424242, // no such set_entries row
        recordedAt: DateTime(2026, 8, 1),
        source: 'wrist',
        sensorType: 'linear_acceleration',
        detectedReps: 8,
        confirmedReps: 8,
        confidence: 0.87,
        featuresJson: '{}',
      );

      final rows = await db.select(db.repSetObservations).get();
      expect(rows, hasLength(1));
      expect(rows.single.setEntryId, 424242);
      expectNoForeignKeyViolations(await foreignKeyViolations(db));
    });
  });
}
