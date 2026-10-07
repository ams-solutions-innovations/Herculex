import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_summary_bridge.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

void main() {
  late AppDatabase db;
  late PhysiqueGoalRepository goals;
  late PhysiqueSummaryBridge bridge;

  setUp(() async {
    db = await openTestDatabase();
    goals = PhysiqueGoalRepository(db, FakeClock(DateTime(2026, 10, 1, 9)));
    bridge = PhysiqueSummaryBridge(db);
  });
  tearDown(() => db.close());

  DreamPhysiqueAnalysisSummary summary(DateTime at, {double bf = 20}) =>
      DreamPhysiqueAnalysisSummary(
        schemaVersion: 1,
        analyzedAt: at.toUtc(),
        targetAestheticStyle: 'lean',
        timeframeRange: '6-9 months',
        estimatedMonths: 8,
        targetBfPercent: 12,
        currentEstimatedBf: bf,
        weightChangeKg: -4,
        currentPhotoCount: 2,
        targetPhotoCount: 1,
      );

  AnalysisInput input(DateTime at, {String? json, double bf = 20}) =>
      AnalysisInput(analyzedAt: at, currentBfPercent: bf, summaryJson: json);

  Future<int> start(List<AnalysisInput> analyses, {bool archive = true}) =>
      goals.startGoal(
        StartGoalInput(
          targetAestheticStyle: 'lean',
          timeframeRange: '6-9 months',
          estimatedMonths: 8,
          targetBfPercent: 12,
          analyses: analyses,
          archiveExisting: archive,
        ),
      );

  test('watchCurrent is null without a goal', () async {
    expect(await bridge.watchCurrent().first, isNull);
  });

  test('watchCurrent returns the newest analysis of the active goal', () async {
    final old = DateTime.utc(2026, 8, 1);
    final newer = DateTime.utc(2026, 9, 1);
    await start([
      input(old, json: jsonEncode(summary(old, bf: 22).toJson())),
      input(newer, json: jsonEncode(summary(newer, bf: 19).toJson())),
    ]);
    final cur = await bridge.watchCurrent().first;
    expect(cur, isNotNull);
    expect(cur!.currentEstimatedBf, 19);
    expect(cur.analyzedAt, newer);
  });

  test('watchHistory spans goals, newest first, skipping bad json', () async {
    final a = DateTime.utc(2026, 7, 1);
    final b = DateTime.utc(2026, 8, 1);
    final c = DateTime.utc(2026, 9, 1);
    await start([input(a, json: jsonEncode(summary(a).toJson()))]);
    await start([
      input(b, json: 'not json'),
      input(c, json: jsonEncode(summary(c).toJson())),
    ]);
    final hist = await bridge.watchHistory().first;
    expect(hist.map((s) => s.analyzedAt), [c, a]);
  });

  test('null summaryJson falls back to goal and assessment columns', () async {
    final at = DateTime.utc(2026, 9, 1);
    await start([input(at, bf: 18.5)]);
    final cur = (await bridge.watchCurrent().first)!;
    expect(cur.targetAestheticStyle, 'lean');
    expect(cur.estimatedMonths, 8);
    expect(cur.targetBfPercent, 12);
    expect(cur.currentEstimatedBf, 18.5);
    expect(cur.weightChangeKg, 0);
    expect(cur.currentPhotoCount, 0);
  });

  test('goal without months or target yields no fallback summary', () async {
    await goals.startGoal(
      StartGoalInput(
        source: 'legacy_import',
        analyses: [input(DateTime.utc(2026, 9, 1))],
      ),
    );
    expect(await bridge.watchHistory().first, isEmpty);
  });

  test('streams re-emit when an assessment is inserted', () async {
    final at = DateTime.utc(2026, 9, 1);
    final goalId = await start([
      input(at, json: jsonEncode(summary(at).toJson())),
    ]);
    final emissions = <int>[];
    final sub = bridge.watchHistory().listen((l) => emissions.add(l.length));
    await pumpEventQueue();
    final later = DateTime.utc(2026, 9, 5);
    await db
        .into(db.physiqueAssessments)
        .insert(
          PhysiqueAssessmentsCompanion.insert(
            goalId: goalId,
            kind: 'analysis',
            dateIso: '2026-09-05',
            summaryJson: Value(jsonEncode(summary(later).toJson())),
          ),
        );
    await pumpEventQueue();
    await sub.cancel();
    expect(emissions.first, 1);
    expect(emissions.last, 2);
  });
}
