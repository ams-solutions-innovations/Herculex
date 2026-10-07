import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/data/physique_date_keys.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late PhysiqueGoalRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    clock = FakeClock(DateTime(2026, 10, 1, 9));
    repo = PhysiqueGoalRepository(db, clock);
  });
  tearDown(() => db.close());

  AnalysisInput analysis(DateTime at, {double bf = 20}) => AnalysisInput(
    analyzedAt: at,
    currentBfPercent: bf,
    confidence: AssessmentConfidence.medium,
    weightKg: 80,
  );

  NewPhotoRow photo(String pose, {String? ref, String source = 'capture'}) =>
      NewPhotoRow(
        pose: pose,
        relativePath: 'physique/x/$pose.jpg',
        takenAt: DateTime(2026, 10, 1),
        source: source,
        legacyRef: ref,
      );

  StartGoalInput live({
    DateTime? startedAt,
    String? uuid,
    List<NewPhotoRow> photos = const [],
    List<AnalysisInput>? analyses,
  }) => StartGoalInput(
    goalSyncUuid: uuid,
    targetAestheticStyle: 'lean',
    timeframeRange: '6-9 months',
    estimatedMonths: 8,
    targetBfPercent: 12,
    startedAt: startedAt,
    analyses: analyses ?? [analysis(DateTime(2026, 9, 30))],
    roadmap: const [
      RoadmapPhaseDraft(phase: DietPhase.cut, plannedWeeks: 12),
      RoadmapPhaseDraft(phase: DietPhase.maintain, plannedWeeks: 4),
    ],
    baselinePhotos: photos,
  );

  StartGoalInput legacy({
    DateTime? startedAt,
    String status = 'active',
    List<NewPhotoRow> photos = const [],
  }) => StartGoalInput(
    source: 'legacy_import',
    startedAt: startedAt,
    status: status,
    archiveExisting: false,
    baselinePhotos: photos,
  );

  test('physiqueDayKey zero-pads', () {
    expect(physiqueDayKey(DateTime(2026, 3, 5)), '2026-03-05');
  });

  test('startGoal writes goal, analyses, phases and photos', () async {
    final id = await repo.startGoal(
      live(
        photos: [photo('front'), photo('side')],
        analyses: [
          analysis(DateTime(2026, 9, 30), bf: 22),
          analysis(DateTime(2026, 9, 1), bf: 24),
        ],
      ),
    );
    final goal = (await repo.getGoal(id))!;
    expect(goal.status, 'active');
    expect(goal.targetAestheticStyle, 'lean');
    expect(goal.timeframeRange, '6-9 months');
    expect(goal.estimatedMonths, 8);
    expect(goal.targetBfPercent, 12);
    expect(goal.roadmapAcceptedAt, isNull);
    expect(goal.startedAt, clock.now());

    final assessments = await db.select(db.physiqueAssessments).get();
    expect(assessments.map((a) => a.kind).toSet(), {'analysis'});
    expect(assessments.map((a) => a.currentBfPercent), [24, 22]);
    expect(assessments.first.dateIso, '2026-09-01');
    expect(assessments.first.confidence, 'medium');

    final phases = await db.select(db.physiqueRoadmapPhases).get();
    expect(phases.map((p) => p.orderIndex), [0, 1]);
    expect(phases.map((p) => p.phaseType), ['cut', 'maintain']);
    expect(phases.every((p) => p.status == 'upcoming'), isTrue);
    expect(phases.every((p) => p.startedAt == null), isTrue);

    final photos = await db.select(db.physiquePhotos).get();
    expect(photos, hasLength(2));
    expect(photos.every((p) => p.role == 'baseline'), isTrue);
    expect(photos.every((p) => p.assessmentId == assessments.last.id), isTrue);

    final ops = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM pending_sync_ops "
          "WHERE entity_type = 'physique_goals'",
        )
        .getSingle();
    expect(ops.read<int>('c'), greaterThan(0));
  });

  test('second goal archives the first and keeps its rows', () async {
    final first = await repo.startGoal(live(photos: [photo('front')]));
    clock.advance(const Duration(days: 30));
    final second = await repo.startGoal(live());

    final a = (await repo.getGoal(first))!;
    expect(a.status, 'archived');
    expect(a.archivedAt, clock.now());
    expect((await repo.getActiveGoal())!.id, second);
    expect(await db.select(db.physiquePhotos).get(), hasLength(1));
    expect(await db.select(db.physiqueRoadmapPhases).get(), hasLength(4));
    final archived = await repo.watchArchivedGoals().first;
    expect(archived.map((g) => g.id), [first]);
  });

  test('failure inside the transaction leaves no partial rows', () async {
    final id = await repo.startGoal(live(uuid: 'dup-uuid'));
    final goalsBefore = (await db.select(db.physiqueGoals).get()).length;
    final assessBefore = (await db.select(db.physiqueAssessments).get()).length;
    clock.advance(const Duration(days: 1));
    await expectLater(
      repo.startGoal(live(uuid: 'dup-uuid')),
      throwsA(anything),
    );
    expect((await db.select(db.physiqueGoals).get()).length, goalsBefore);
    expect(
      (await db.select(db.physiqueAssessments).get()).length,
      assessBefore,
    );
    // The earlier goal must still be active (archive rolled back).
    expect((await repo.getGoal(id))!.status, 'active');
  });

  test('goalSyncUuid is stored', () async {
    final id = await repo.startGoal(live(uuid: 'abc-123'));
    expect((await repo.getGoal(id))!.syncUuid, 'abc-123');
  });

  test(
    'watchActiveGoal picks greatest startedAt, ignores archived/deleted',
    () async {
      expect(await repo.watchActiveGoal().first, isNull);
      final a = await repo.startGoal(live(startedAt: DateTime(2026, 9, 1)));
      final b = await repo.startGoal(
        live(startedAt: DateTime(2026, 9, 10)).copyArchiveOff(),
      );
      expect((await repo.watchActiveGoal().first)!.id, b);
      await (db.update(db.physiqueGoals)..where((g) => g.id.equals(b))).write(
        PhysiqueGoalsCompanion(deletedAt: Value(clock.now())),
      );
      expect((await repo.watchActiveGoal().first)!.id, a);
    },
  );

  test('tie on startedAt breaks by greatest id', () async {
    final t = DateTime(2026, 9, 1);
    await repo.startGoal(live(startedAt: t).copyArchiveOff());
    final b = await repo.startGoal(live(startedAt: t).copyArchiveOff());
    expect((await repo.getActiveGoal())!.id, b);
  });

  test('reconcileSingleActive archives losers and is idempotent', () async {
    final a = await repo.startGoal(live(startedAt: DateTime(2026, 9, 1)));
    final b = await repo.startGoal(
      live(startedAt: DateTime(2026, 9, 5)).copyArchiveOff(),
    );
    expect(await repo.reconcileSingleActive(), 1);
    expect((await repo.getGoal(a))!.status, 'archived');
    expect((await repo.getGoal(b))!.status, 'active');
    expect(await repo.reconcileSingleActive(), 0);
  });

  test('legacy_import never displaces a live goal (D-03)', () async {
    final liveId = await repo.startGoal(live(startedAt: DateTime(2026, 10, 1)));
    final legacyId = await repo.startGoal(
      legacy(startedAt: DateTime(2026, 10, 5)),
    );
    expect((await repo.getActiveGoal())!.id, liveId);
    expect((await repo.watchActiveGoal().first)!.id, liveId);
    expect(await repo.reconcileSingleActive(), 1);
    expect((await repo.getGoal(liveId))!.status, 'active');
    expect((await repo.getGoal(legacyId))!.status, 'archived');
  });

  test('legacy goal wins only when no live goal exists', () async {
    final legacyId = await repo.startGoal(legacy());
    expect((await repo.getActiveGoal())!.id, legacyId);
  });

  test(
    'archived legacy goal is inserted archived, live stays active',
    () async {
      final liveId = await repo.startGoal(live());
      final legacyId = await repo.startGoal(
        legacy(
          status: 'archived',
          photos: [photo('front', ref: 'pp:1')],
        ),
      );
      final g = (await repo.getGoal(legacyId))!;
      expect(g.status, 'archived');
      expect(g.archivedAt, clock.now());
      expect((await repo.getGoal(liveId))!.status, 'active');
    },
  );

  test('invalid status/source combinations throw ArgumentError', () async {
    expect(
      () => repo.startGoal(
        const StartGoalInput(
          source: 'legacy_import',
          status: 'paused',
          archiveExisting: false,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.startGoal(
        StartGoalInput(
          estimatedMonths: 6,
          targetBfPercent: 12,
          status: 'archived',
          analyses: [analysis(DateTime(2026, 9, 1))],
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.startGoal(
        const StartGoalInput(estimatedMonths: 6, targetBfPercent: 12),
      ),
      throwsArgumentError,
    );
    expect(
      () => repo.startGoal(
        StartGoalInput(analyses: [analysis(DateTime(2026, 9, 1))]),
      ),
      throwsArgumentError,
    );
    expect(await db.select(db.physiqueGoals).get(), isEmpty);
  });

  test(
    'photos-only legacy goal stores null targets and no assessments',
    () async {
      final id = await repo.startGoal(
        legacy(photos: [photo('front', ref: 'pp:1')]),
      );
      final g = (await repo.getGoal(id))!;
      expect(g.targetBfPercent, isNull);
      expect(g.estimatedMonths, isNull);
      expect(await db.select(db.physiqueAssessments).get(), isEmpty);
      final photos = await db.select(db.physiquePhotos).get();
      expect(photos.single.assessmentId, isNull);
    },
  );

  test('legacy lookups', () async {
    expect(await repo.hasLegacyImportGoal(), isFalse);
    expect(await repo.getLegacyImportGoal(), isNull);
    await repo.startGoal(live());
    expect(await repo.hasLegacyImportGoal(), isFalse);
    final l1 = await repo.startGoal(legacy());
    await repo.startGoal(legacy());
    expect(await repo.hasLegacyImportGoal(), isTrue);
    expect((await repo.getLegacyImportGoal())!.id, l1);
  });

  test('appendLegacyPhotos is idempotent and works on archived goal', () async {
    final id = await repo.startGoal(
      legacy(
        status: 'archived',
        photos: [photo('front', ref: 'pp:1')],
      ),
    );
    final rows = [
      photo('front', ref: 'pp:1'),
      photo('side', ref: 'pp:2'),
      photo('back', ref: 'pp:3'),
    ];
    expect(await repo.appendLegacyPhotos(id, rows), 2);
    expect(await repo.appendLegacyPhotos(id, rows), 0);
    expect(await repo.legacyPhotoRefs(), {'pp:1', 'pp:2', 'pp:3'});
    final all = await db.select(db.physiquePhotos).get();
    expect(all, hasLength(3));
    expect(
      all
          .where((p) => p.legacyRef != 'pp:1')
          .every((p) => p.source == 'legacy_import'),
      isTrue,
    );
    expect(all.every((p) => p.assessmentId == null), isTrue);
  });

  test('legacyPhotoRefs includes soft-deleted rows', () async {
    final id = await repo.startGoal(
      legacy(photos: [photo('front', ref: 'pp:9')]),
    );
    await (db.update(
      db.physiquePhotos,
    )).write(PhysiquePhotosCompanion(deletedAt: Value(clock.now())));
    expect(await repo.legacyPhotoRefs(), {'pp:9'});
    expect(await repo.appendLegacyPhotos(id, [photo('front', ref: 'pp:9')]), 0);
  });

  test(
    'appendLegacyPhotos throws StateError for missing/deleted goal',
    () async {
      await expectLater(
        repo.appendLegacyPhotos(999, [photo('front', ref: 'a')]),
        throwsStateError,
      );
      final id = await repo.startGoal(legacy());
      await (db.update(db.physiqueGoals)..where((g) => g.id.equals(id))).write(
        PhysiqueGoalsCompanion(deletedAt: Value(clock.now())),
      );
      await expectLater(
        repo.appendLegacyPhotos(id, [photo('front', ref: 'a')]),
        throwsStateError,
      );
    },
  );
}

extension on StartGoalInput {
  StartGoalInput copyArchiveOff() => StartGoalInput(
    goalSyncUuid: goalSyncUuid,
    source: source,
    targetAestheticStyle: targetAestheticStyle,
    timeframeRange: timeframeRange,
    estimatedMonths: estimatedMonths,
    targetBfPercent: targetBfPercent,
    startWeightKg: startWeightKg,
    startBfPercent: startBfPercent,
    startedAt: startedAt,
    analyses: analyses,
    roadmap: roadmap,
    baselinePhotos: baselinePhotos,
    archiveExisting: false,
    status: status,
  );
}
