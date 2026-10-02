import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/application/physique_capture_providers.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_legacy_migrator.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';

import '../../support/fake_clock.dart';

PendingAiScanContext _ctx({
  AiScanContextType type = AiScanContextType.physiqueCheckin,
  Map<String, dynamic>? extra,
}) => PendingAiScanContext(type: type, extra: extra);

PhysiqueRoadmapPhaseData _row(
  int id,
  DietPhase phase, {
  String status = 'upcoming',
  DateTime? startedAt,
}) => PhysiqueRoadmapPhaseData(
  id: id,
  goalId: 1,
  orderIndex: id,
  phaseType: phase.name,
  plannedWeeks: 8,
  tempoCapped: false,
  status: status,
  startedAt: startedAt,
);

PhysiqueGoalData _goal() => PhysiqueGoalData(
  id: 1,
  status: 'active',
  source: 'ai_analysis',
  targetAestheticStyle: 'lean',
  timeframeRange: '6 months',
  estimatedMonths: 6,
  startedAt: DateTime(2026, 9, 1),
  roadmapAcceptedAt: DateTime(2026, 9, 2),
);

void main() {
  group('ResumedCapture.fromPending', () {
    test('valid physiqueCheckin context', () {
      final r = ResumedCapture.fromPending(
        _ctx(extra: {'goalId': 3, 'pose': 'side'}),
        '/tmp/a.jpg',
      );
      expect(r?.goalId, 3);
      expect(r?.pose, 'side');
      expect(r?.path, '/tmp/a.jpg');
    });

    test('rejects other types, bad goalId and unknown pose', () {
      expect(
        ResumedCapture.fromPending(
          _ctx(
            type: AiScanContextType.bodyFat,
            extra: {'goalId': 3, 'pose': 'front'},
          ),
          'p',
        ),
        isNull,
      );
      expect(
        ResumedCapture.fromPending(
          _ctx(extra: {'goalId': '3', 'pose': 'front'}),
          'p',
        ),
        isNull,
      );
      expect(
        ResumedCapture.fromPending(
          _ctx(extra: {'goalId': 3, 'pose': 'top'}),
          'p',
        ),
        isNull,
      );
      expect(ResumedCapture.fromPending(_ctx(), 'p'), isNull);
    });
  });

  test('physiqueResumedCaptureProvider starts null', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(physiqueResumedCaptureProvider), isNull);
  });

  group('PendingAiScanContext JSON', () {
    test('an old stored context still parses', () {
      final old = jsonEncode({
        'type': 'workoutPhoto',
        'extra': {'sessionId': 4},
        'createdAt': DateTime.now().toIso8601String(),
      });
      final ctx = PendingAiScanContext.fromJson(
        jsonDecode(old) as Map<String, dynamic>,
      );
      expect(ctx.type, AiScanContextType.workoutPhoto);
      expect(ctx.extra?['sessionId'], 4);
    });

    test('physiqueCheckin round trips', () {
      final ctx = _ctx(extra: {'goalId': 2, 'pose': 'back'});
      final back = PendingAiScanContext.fromJson(
        jsonDecode(jsonEncode(ctx.toJson())) as Map<String, dynamic>,
      );
      expect(back.type, AiScanContextType.physiqueCheckin);
      expect(back.extra, {'goalId': 2, 'pose': 'back'});
    });
  });

  group('physiqueCheckInContextProvider', () {
    final now = DateTime(2026, 10, 1, 9);

    WeightLog w(DateTime d, double kg) => WeightLog(d, kg);

    ProviderContainer make({
      List<PhysiqueRoadmapPhaseData> phases = const [],
      List<WeightLog> logs = const [],
      double? profileKg,
    }) {
      final c = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(FakeClock(now)),
          physiqueGoalProvider(1).overrideWith((ref) => Stream.value(_goal())),
          physiqueRoadmapPhasesProvider(
            1,
          ).overrideWith((ref) => Stream.value(phases)),
          physiqueWeightLogsProvider.overrideWith((ref) => Stream.value(logs)),
          physiqueMeasuredBodyFatProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          physiqueLatestAnalysisProvider(
            1,
          ).overrideWith((ref) => Stream.value(null)),
          profileProvider.overrideWith(
            (ref) => Stream.value(
              Profile(
                goal: FitnessGoal.maintenance,
                activityLevel: ActivityLevel.active,
                weightKg: profileKg,
              ),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<CheckInFlowContext> read(ProviderContainer c) async {
      await c.read(physiqueGoalProvider(1).future);
      await c.read(physiqueRoadmapPhasesProvider(1).future);
      await c.read(physiqueWeightLogsProvider.future);
      await c.read(physiqueLatestAnalysisProvider(1).future);
      await c.read(physiqueMeasuredBodyFatProvider.future);
      await c.read(profileProvider.future);
      return c.read(physiqueCheckInContextProvider(1));
    }

    test('uses the current phase and its week', () async {
      final c = make(
        phases: [
          _row(
            1,
            DietPhase.cut,
            status: 'current',
            startedAt: now.subtract(const Duration(days: 15)),
          ),
          _row(2, DietPhase.maintain),
        ],
      );
      final ctx = await read(c);
      expect(ctx.phase, DietPhase.cut);
      expect(ctx.weeksInPhase, 3);
    });

    test('falls back to the first upcoming phase, then maintain', () async {
      var ctx = await read(make(phases: [_row(1, DietPhase.bulk)]));
      expect(ctx.phase, DietPhase.bulk);
      expect(ctx.weeksInPhase, 0);
      ctx = await read(make());
      expect(ctx.phase, DietPhase.maintain);
      expect(ctx.weeksInPhase, 0);
    });

    test('weight is the latest log else the profile weight', () async {
      var ctx = await read(make(profileKg: 80));
      expect(ctx.weightKg, 80);
      expect(ctx.weeklyTrendKg, isNull);
      ctx = await read(
        make(
          profileKg: 80,
          logs: [
            for (var i = 0; i < 15; i++)
              w(now.subtract(Duration(days: 14 - i)), 90 - i * 0.1),
          ],
        ),
      );
      expect(ctx.weightKg, closeTo(88.6, 1e-9));
      expect(ctx.weeklyTrendKg, isNotNull);
      expect(ctx.weeklyTrendKg!, lessThan(0));
    });
  });

  group('LegacyMigrationNotice.messageFor', () {
    test('null when nothing to say', () {
      expect(LegacyMigrationNotice.messageFor(null), isNull);
      expect(
        LegacyMigrationNotice.messageFor(
          const LegacyMigrationResult(photosMigrated: 2),
        ),
        isNull,
      );
      expect(
        LegacyMigrationNotice.messageFor(
          const LegacyMigrationResult(ran: true),
        ),
        isNull,
      );
    });

    test('migrated, unrecoverable and both', () {
      const migrated =
          'Your progress photos now live in your private Dream Physique goal.';
      const lost = "3 older photos couldn't be recovered.";
      expect(
        LegacyMigrationNotice.messageFor(
          const LegacyMigrationResult(ran: true, photosMigrated: 2),
        ),
        migrated,
      );
      expect(
        LegacyMigrationNotice.messageFor(
          const LegacyMigrationResult(ran: true, photosUnrecoverable: 3),
        ),
        lost,
      );
      expect(
        LegacyMigrationNotice.messageFor(
          const LegacyMigrationResult(
            ran: true,
            photosMigrated: 2,
            photosUnrecoverable: 3,
          ),
        ),
        '$migrated $lost',
      );
    });
  });
}
