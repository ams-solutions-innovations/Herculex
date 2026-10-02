import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/physique/data/physique_assessment_repository.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late PhysiqueGoalRepository goals;
  late PhysiqueAssessmentRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    clock = FakeClock(DateTime(2026, 10, 1, 9));
    goals = PhysiqueGoalRepository(db, clock);
    repo = PhysiqueAssessmentRepository(db, clock);
  });
  tearDown(() => db.close());

  Future<int> newGoal({bool archiveExisting = true}) => goals.startGoal(
    StartGoalInput(
      targetAestheticStyle: 'lean',
      timeframeRange: '6-9 months',
      estimatedMonths: 8,
      targetBfPercent: 12,
      archiveExisting: archiveExisting,
      analyses: [
        AnalysisInput(
          analyzedAt: DateTime(2026, 9, 30),
          currentBfPercent: 20,
          confidence: AssessmentConfidence.medium,
        ),
      ],
    ),
  );

  CheckInRecord record(int goalId, {String path = 'physique/c.jpg'}) =>
      CheckInRecord(
        goalId: goalId,
        pose: 'front',
        relativePath: path,
        weightKg: 80,
        verdict: CheckInVerdict.onTrack,
        band: CheckInBand.clamped(0.2, 0.6),
        confidence: AssessmentConfidence.medium,
        reason: 'visible progress',
        limitations: const ['lighting'],
        source: 'ai',
        modelVersion: 'm1',
        knowledgeVersion: 'k1',
      );

  NewPhotoRow base(String pose) => NewPhotoRow(
    pose: pose,
    relativePath: 'physique/b-$pose.jpg',
    takenAt: DateTime(2026, 10, 1),
  );

  test(
    'first check-in persists assessment and photo with provenance',
    () async {
      final g = await newGoal();
      final id = await repo.recordCheckIn(record(g));
      final a = await (db.select(
        db.physiqueAssessments,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(a.kind, 'checkin');
      expect(a.assessedAt, clock.now());
      expect(a.dateIso, '2026-10-01');
      expect(a.verdict, 'on_track');
      expect(a.directionBandLow, closeTo(0.2, 1e-9));
      expect(a.directionBandHigh, closeTo(0.6, 1e-9));
      expect(a.confidence, 'medium');
      expect(a.reason, 'visible progress');
      expect(a.limitationsJson, '["lighting"]');
      expect(a.source, 'ai');
      expect(a.modelVersion, 'm1');
      expect(a.knowledgeVersion, 'k1');
      final photos = await (db.select(
        db.physiquePhotos,
      )..where((p) => p.role.equals('checkin'))).get();
      expect(photos, hasLength(1));
      expect(photos.single.assessmentId, id);
      expect(photos.single.pose, 'front');
    },
  );

  test('same day and days 1-6 are refused, day 7 is allowed', () async {
    final g = await newGoal();
    await repo.recordCheckIn(record(g));
    clock.set(DateTime(2026, 10, 1, 20));
    await expectLater(
      repo.recordCheckIn(record(g)),
      throwsA(
        isA<CheckInTooSoonException>().having(
          (e) => e.nextEligibleDate,
          'next',
          DateTime(2026, 10, 8),
        ),
      ),
    );
    clock.set(DateTime(2026, 10, 7, 23, 59));
    await expectLater(
      repo.recordCheckIn(record(g)),
      throwsA(isA<CheckInTooSoonException>()),
    );
    clock.set(DateTime(2026, 10, 8));
    await repo.recordCheckIn(record(g));
    expect(await db.select(db.physiqueAssessments).get(), hasLength(3));
  });

  test('cap is per goal', () async {
    final a = await newGoal(archiveExisting: false);
    final b = await newGoal(archiveExisting: false);
    await repo.recordCheckIn(record(a));
    await repo.recordCheckIn(record(b));
  });

  test('archived goal rejects check-ins', () async {
    final g = await newGoal();
    await goals.archiveGoal(g);
    await expectLater(
      repo.recordCheckIn(record(g)),
      throwsA(isA<GoalNotActiveException>()),
    );
    expect(
      await (db.select(
        db.physiquePhotos,
      )..where((p) => p.role.equals('checkin'))).get(),
      isEmpty,
    );
  });

  test('soft-deleted check-in still blocks the window', () async {
    final g = await newGoal();
    final id = await repo.recordCheckIn(record(g));
    await repo.deleteCheckIn(id);
    clock.set(DateTime(2026, 10, 3));
    await expectLater(
      repo.recordCheckIn(record(g)),
      throwsA(isA<CheckInTooSoonException>()),
    );
    expect(await repo.lastCheckInAt(g), DateTime(2026, 10, 1, 9));
    expect(await repo.watchLastCheckInAt(g).first, DateTime(2026, 10, 1, 9));
  });

  test('DST: day 7 allowed, 23:59 on day 6 refused', () async {
    clock.set(DateTime(2026, 3, 25, 12));
    final g = await newGoal();
    await repo.recordCheckIn(record(g));
    clock.set(DateTime(2026, 3, 31, 23, 59));
    await expectLater(
      repo.recordCheckIn(record(g)),
      throwsA(isA<CheckInTooSoonException>()),
    );
    clock.set(DateTime(2026, 4, 1));
    await repo.recordCheckIn(record(g));
  });

  test('concurrent submissions yield exactly one check-in', () async {
    final g = await newGoal();
    Future<Object?> attempt(String path) async {
      try {
        return await repo.recordCheckIn(record(g, path: path));
      } on Object catch (e) {
        return e;
      }
    }

    final results = await Future.wait([attempt('a.jpg'), attempt('b.jpg')]);
    expect(results.whereType<int>(), hasLength(1));
    expect(results.whereType<CheckInTooSoonException>(), hasLength(1));
    expect(
      await (db.select(
        db.physiqueAssessments,
      )..where((a) => a.kind.equals('checkin'))).get(),
      hasLength(1),
    );
    expect(
      await (db.select(
        db.physiquePhotos,
      )..where((p) => p.role.equals('checkin'))).get(),
      hasLength(1),
    );
  });

  test('photo insert failure rolls the assessment back', () async {
    final g = await newGoal();
    await db.customStatement('''
      CREATE TRIGGER block_checkin_photo BEFORE INSERT ON physique_photos
      WHEN NEW.role = 'checkin'
      BEGIN SELECT RAISE(ABORT, 'boom'); END;
    ''');
    await expectLater(repo.recordCheckIn(record(g)), throwsA(anything));
    expect(
      await (db.select(
        db.physiqueAssessments,
      )..where((a) => a.kind.equals('checkin'))).get(),
      isEmpty,
    );
    await db.customStatement('DROP TRIGGER block_checkin_photo');
    await repo.recordCheckIn(record(g));
  });

  test('baseline photos: no cap, no assessment, limit of three', () async {
    final g = await newGoal();
    await repo.addBaselinePhoto(goalId: g, photo: base('front'));
    await repo.addBaselinePhoto(goalId: g, photo: base('side'));
    await repo.addBaselinePhoto(goalId: g, photo: base('back'));
    await expectLater(
      repo.addBaselinePhoto(goalId: g, photo: base('front')),
      throwsA(isA<BaselineLimitException>()),
    );
    final rows = await repo.baselinePhotos(g);
    expect(rows.map((p) => p.pose), ['front', 'side', 'back']);
    expect(rows.every((p) => p.assessmentId == null), isTrue);
    // Baselines do not consume the weekly slot.
    await repo.recordCheckIn(record(g));
  });

  test('deleteCheckIn soft-deletes rows and returns paths', () async {
    final g = await newGoal();
    final id = await repo.recordCheckIn(record(g, path: 'physique/del.jpg'));
    expect(await repo.watchCheckIns(g).first, hasLength(1));
    final paths = await repo.deleteCheckIn(id);
    expect(paths, ['physique/del.jpg']);
    expect(await repo.watchCheckIns(g).first, isEmpty);
    final photo = await db.select(db.physiquePhotos).get();
    expect(photo.single.deletedAt, isNotNull);
    expect(await repo.watchPhotos(g).first, isEmpty);
  });

  test('deleteCheckIn rejects unknown and non-checkin ids', () async {
    final g = await newGoal();
    final analysis = await (db.select(
      db.physiqueAssessments,
    )..where((a) => a.goalId.equals(g))).getSingle();
    await expectLater(repo.deleteCheckIn(9999), throwsArgumentError);
    await expectLater(repo.deleteCheckIn(analysis.id), throwsArgumentError);
  });

  test(
    'watchCheckIns orders newest first; latest analysis is exposed',
    () async {
      final g = await newGoal();
      final first = await repo.recordCheckIn(record(g));
      clock.set(DateTime(2026, 10, 9));
      final second = await repo.recordCheckIn(record(g));
      final list = await repo.watchCheckIns(g).first;
      expect(list.map((a) => a.id), [second, first]);
      final analysis = await repo.watchLatestAnalysis(g).first;
      expect(analysis, isNotNull);
      expect(analysis!.kind, 'analysis');
    },
  );
}
