import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

DreamPhysiqueAnalysisSummary _summary(DateTime at, double bf) =>
    DreamPhysiqueAnalysisSummary(
      schemaVersion: DreamPhysiqueAnalysisSummary.currentSchemaVersion,
      analyzedAt: at.toUtc(),
      targetAestheticStyle: 'Athletic',
      timeframeRange: '6 months',
      estimatedMonths: 6,
      targetBfPercent: 12,
      currentEstimatedBf: bf,
      weightChangeKg: -3,
      currentPhotoCount: 1,
      targetPhotoCount: 1,
    );

AnalysisInput _analysis(DateTime at, double bf) => AnalysisInput(
  analyzedAt: at,
  currentBfPercent: bf,
  summaryJson: jsonEncode(_summary(at, bf).toJson()),
);

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late PhysiqueGoalRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    final clock = FakeClock(DateTime(2026, 10, 1, 9));
    repo = PhysiqueGoalRepository(db, clock);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('current summary is null with no goal', () async {
    expect(await container.read(dreamPhysiqueSummaryProvider.future), isNull);
    expect(
      await container.read(dreamPhysiqueSummaryHistoryProvider.future),
      isEmpty,
    );
  });

  test(
    'current is the newest analysis; history lists all, newest first',
    () async {
      await repo.startGoal(
        StartGoalInput(
          targetAestheticStyle: 'Athletic',
          timeframeRange: '6 months',
          estimatedMonths: 6,
          targetBfPercent: 12,
          analyses: [
            _analysis(DateTime(2026, 9, 1), 22),
            _analysis(DateTime(2026, 9, 20), 19),
          ],
        ),
      );

      final current = await container.read(dreamPhysiqueSummaryProvider.future);
      expect(current, isNotNull);
      expect(current!.currentEstimatedBf, 19);
      expect(current.targetAestheticStyle, 'Athletic');

      final history = await container.read(
        dreamPhysiqueSummaryHistoryProvider.future,
      );
      expect(history.map((s) => s.currentEstimatedBf), [19, 22]);
    },
  );

  test('archiving the goal clears current but keeps history', () async {
    await repo.startGoal(
      StartGoalInput(
        targetAestheticStyle: 'Athletic',
        estimatedMonths: 6,
        targetBfPercent: 12,
        analyses: [_analysis(DateTime(2026, 9, 1), 22)],
      ),
    );
    await repo.startGoal(const StartGoalInput(source: 'legacy_import'));

    expect(await container.read(dreamPhysiqueSummaryProvider.future), isNull);
    final history = await container.read(
      dreamPhysiqueSummaryHistoryProvider.future,
    );
    expect(history, hasLength(1));
  });
}
