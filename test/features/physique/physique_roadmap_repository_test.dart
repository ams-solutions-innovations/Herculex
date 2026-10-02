import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_roadmap_repository.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late PhysiqueGoalRepository goals;
  late PhysiqueRoadmapRepository repo;

  const cut = RoadmapPhaseDraft(phase: DietPhase.cut, plannedWeeks: 12);
  const maintain = RoadmapPhaseDraft(
    phase: DietPhase.maintain,
    plannedWeeks: 4,
  );
  const bulk = RoadmapPhaseDraft(phase: DietPhase.bulk, plannedWeeks: 16);

  setUp(() async {
    db = await openTestDatabase();
    clock = FakeClock(DateTime(2026, 10, 1, 9));
    goals = PhysiqueGoalRepository(db, clock);
    repo = PhysiqueRoadmapRepository(db, clock);
  });
  tearDown(() => db.close());

  Future<int> newGoal([
    List<RoadmapPhaseDraft> roadmap = const [cut, maintain],
  ]) => goals.startGoal(
    StartGoalInput(
      estimatedMonths: 6,
      targetBfPercent: 12,
      analyses: [AnalysisInput(analyzedAt: DateTime(2026, 9, 30))],
      roadmap: roadmap,
    ),
  );

  Future<List<PhysiqueRoadmapPhaseData>> phases(int id) =>
      repo.watchPhases(id).first;

  test('watchPhases orders by orderIndex and hides soft-deleted', () async {
    final id = await newGoal();
    final rows = await phases(id);
    expect(rows.map((p) => p.phaseType), ['cut', 'maintain']);
    await (db.update(db.physiqueRoadmapPhases)
          ..where((t) => t.id.equals(rows.last.id)))
        .write(PhysiqueRoadmapPhasesCompanion(deletedAt: Value(clock.now())));
    expect(await phases(id), hasLength(1));
  });

  test('accepting a proposal makes the first phase current', () async {
    final id = await newGoal();
    await repo.replaceRoadmap(id, [bulk, cut, maintain], accept: true);
    final rows = await phases(id);
    expect(rows.map((p) => p.orderIndex), [0, 1, 2]);
    expect(rows.map((p) => p.status), ['current', 'upcoming', 'upcoming']);
    expect(rows.first.startedAt, clock.now());
    expect(rows[1].startedAt, isNull);
    expect((await goals.getGoal(id))!.roadmapAcceptedAt, clock.now());
  });

  test('replace without accept rewrites the proposal', () async {
    final id = await newGoal();
    await repo.replaceRoadmap(id, [bulk]);
    final rows = await phases(id);
    expect(rows.single.phaseType, 'bulk');
    expect(rows.single.status, 'upcoming');
    expect(rows.single.startedAt, isNull);
    expect((await goals.getGoal(id))!.roadmapAcceptedAt, isNull);
  });

  test('replace on accepted goal keeps done phases', () async {
    final id = await newGoal();
    await repo.replaceRoadmap(id, [cut, maintain, bulk], accept: true);
    clock.advance(const Duration(days: 84));
    await repo.advancePhase(id); // cut done, maintain current
    clock.advance(const Duration(days: 10));
    await repo.replaceRoadmap(id, [bulk, cut]);
    final rows = await phases(id);
    expect(rows.map((p) => p.phaseType), ['cut', 'bulk', 'cut']);
    expect(rows.map((p) => p.orderIndex), [0, 1, 2]);
    expect(rows.map((p) => p.status), ['done', 'current', 'upcoming']);
    expect(rows[1].startedAt, clock.now());
  });

  test('replace keeps startedAt when current type unchanged', () async {
    final id = await newGoal();
    await repo.replaceRoadmap(id, [cut, maintain], accept: true);
    final started = clock.now();
    clock.advance(const Duration(days: 20));
    await repo.replaceRoadmap(id, [cut, bulk]);
    final rows = await phases(id);
    expect(rows.first.startedAt, started);
    expect(rows.first.status, 'current');
  });

  test('empty drafts throw and change nothing', () async {
    final id = await newGoal();
    await expectLater(repo.replaceRoadmap(id, []), throwsArgumentError);
    expect(await phases(id), hasLength(2));
  });

  test('advancePhase moves current to done and next to current', () async {
    final id = await newGoal();
    await repo.replaceRoadmap(id, [cut, maintain], accept: true);
    await repo.postponeAdvance(id);
    clock.advance(const Duration(days: 84));
    expect(await repo.advancePhase(id), isTrue);
    final rows = await phases(id);
    expect(rows.map((p) => p.status), ['done', 'current']);
    expect(rows.first.completedAt, clock.now());
    expect(rows.last.startedAt, clock.now());
    expect((await goals.getGoal(id))!.advanceSnoozedUntil, isNull);
  });

  test('advancePhase with no next phase returns false', () async {
    final id = await newGoal([cut]);
    await repo.replaceRoadmap(id, [cut], accept: true);
    expect(await repo.advancePhase(id), isFalse);
    expect((await phases(id)).single.status, 'current');
  });

  test('advancePhase never touches nutrition_targets', () async {
    final id = await newGoal();
    await repo.replaceRoadmap(id, [cut, maintain], accept: true);
    Future<int> count() async =>
        (await db
                .customSelect('SELECT COUNT(*) AS c FROM nutrition_targets')
                .getSingle())
            .read<int>('c');
    final before = await count();
    await repo.advancePhase(id);
    expect(await count(), before);
  });

  test('postponeAdvance snoozes to midnight 7 days out', () async {
    final id = await newGoal();
    await repo.postponeAdvance(id);
    expect(
      (await goals.getGoal(id))!.advanceSnoozedUntil,
      DateTime(2026, 10, 8),
    );
  });

  test('archived goal roadmap cannot be modified', () async {
    final id = await newGoal();
    await repo.replaceRoadmap(id, [cut, maintain], accept: true);
    await goals.archiveGoal(id);
    await expectLater(repo.replaceRoadmap(id, [bulk]), throwsStateError);
    await expectLater(repo.advancePhase(id), throwsStateError);
    await expectLater(repo.postponeAdvance(id), throwsStateError);
    expect(await phases(id), hasLength(2));
  });
}
