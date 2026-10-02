import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_assessment_repository.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/data/physique_roadmap_repository.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/domain/roadmap_exit_criteria.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_clock.dart';
import '../../support/fake_face_detector.dart';
import '../../support/test_database.dart';

Profile _profile({int? age}) => Profile(
  goal: FitnessGoal.maintenance,
  activityLevel: ActivityLevel.active,
  ageYears: age,
  weightKg: 80,
);

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late PhysiqueGoalRepository goals;
  late PhysiqueRoadmapRepository roadmaps;
  late PhysiqueAssessmentRepository assessments;
  late Directory tmp;

  final t0 = DateTime(2026, 10, 1, 9);

  setUp(() async {
    db = await openTestDatabase();
    clock = FakeClock(t0);
    goals = PhysiqueGoalRepository(db, clock);
    roadmaps = PhysiqueRoadmapRepository(db, clock);
    assessments = PhysiqueAssessmentRepository(db, clock);
    tmp = await Directory.systemTemp.createTemp('phys_providers_');
  });
  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<ProviderContainer> make({
    Profile? stored,
    Override? profileOverride,
    List<Override> extra = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      if (stored != null) 'herculex.profile': stored.encode(),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
        sharedPreferencesProvider.overrideWithValue(prefs),
        physiquePhotoStoreProvider.overrideWithValue(
          PhysiquePhotoStore(documentsDirectory: () async => tmp),
        ),
        physiquePhotoSanitizerProvider.overrideWithValue(
          PhysiquePhotoSanitizer(
            faceDetector: FakeFaceDetector(),
            stagingDirectory: () async => tmp,
          ),
        ),
        ?profileOverride,
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Override profileData(Profile? p) =>
      profileProvider.overrideWith((ref) => Stream.value(p));

  Future<int> seedGoal({
    AssessmentConfidence confidence = AssessmentConfidence.medium,
    double? bf = 20,
    List<RoadmapPhaseDraft>? roadmap,
    bool accept = true,
    bool archiveExisting = true,
  }) async {
    final id = await goals.startGoal(
      StartGoalInput(
        targetAestheticStyle: 'lean',
        timeframeRange: '6-9 months',
        estimatedMonths: 8,
        targetBfPercent: 12,
        startWeightKg: 80,
        archiveExisting: archiveExisting,
        analyses: [
          AnalysisInput(
            analyzedAt: t0,
            currentBfPercent: bf,
            confidence: confidence,
          ),
        ],
      ),
    );
    if (roadmap != null) {
      await roadmaps.replaceRoadmap(id, roadmap, accept: accept);
    }
    return id;
  }

  const threePhase = [
    RoadmapPhaseDraft(
      phase: DietPhase.cut,
      plannedWeeks: 12,
      targetWeightKg: 75,
      targetBfPercent: 12,
    ),
    RoadmapPhaseDraft(phase: DietPhase.maintain, plannedWeeks: 2),
    RoadmapPhaseDraft(
      phase: DietPhase.maingain,
      plannedWeeks: 8,
      targetWeightKg: 76,
    ),
  ];

  Future<void> logMetric(String dateIso, String metric, double value) => db
      .into(db.bodyMeasurements)
      .insert(
        BodyMeasurementsCompanion.insert(
          dateIso: dateIso,
          metric: metric,
          value: value,
        ),
      );

  Future<PhysiquePhaseStatus> status(ProviderContainer c, int id) async {
    await c.read(physiqueGoalProvider(id).future);
    await c.read(physiqueRoadmapPhasesProvider(id).future);
    await c.read(physiqueWeightLogsProvider.future);
    await c.read(physiqueMeasuredBodyFatProvider.future);
    await c.read(physiqueLatestAnalysisProvider(id).future);
    return c.read(physiquePhaseStatusProvider(id))!;
  }

  group('eligibility', () {
    test('age 17 is restricted (under18)', () async {
      final c = await make(profileOverride: profileData(_profile(age: 17)));
      await c.read(profileProvider.future);
      final e = c.read(physiqueEditorEligibilityProvider);
      expect(e.allows(DietPhase.cut), isFalse);
      expect(e.reasons, contains(PhaseRestrictionReason.under18));
    });

    test('null age is restricted (ageMissing)', () async {
      final c = await make(profileOverride: profileData(_profile()));
      await c.read(profileProvider.future);
      final e = c.read(physiqueEditorEligibilityProvider);
      expect(e.allows(DietPhase.bulk), isFalse);
      expect(e.reasons, contains(PhaseRestrictionReason.ageMissing));
    });

    test('no profile is restricted', () async {
      final c = await make(profileOverride: profileData(null));
      await c.read(profileProvider.future);
      expect(
        c.read(physiqueEditorEligibilityProvider).allows(DietPhase.cut),
        isFalse,
      );
    });

    test('loading falls back to the stored profile (no flash)', () async {
      final never = StreamController<Profile?>();
      addTearDown(never.close);
      final c = await make(
        stored: _profile(age: 30),
        profileOverride: profileProvider.overrideWith((ref) => never.stream),
      );
      expect(c.read(profileProvider).isLoading, isTrue);
      expect(
        c.read(physiqueEditorEligibilityProvider).allows(DietPhase.cut),
        isTrue,
      );

      final c2 = await make(
        stored: _profile(age: 15),
        profileOverride: profileProvider.overrideWith((ref) => never.stream),
      );
      expect(
        c2.read(physiqueEditorEligibilityProvider).allows(DietPhase.cut),
        isFalse,
      );
    });

    test('loading with no stored profile is restricted', () async {
      final never = StreamController<Profile?>();
      addTearDown(never.close);
      final c = await make(
        profileOverride: profileProvider.overrideWith((ref) => never.stream),
      );
      expect(
        c.read(physiqueEditorEligibilityProvider).allows(DietPhase.cut),
        isFalse,
      );
    });

    test('stream error is restricted, never unrestricted', () async {
      final c = await make(
        stored: _profile(age: 30),
        profileOverride: profileProvider.overrideWith(
          (ref) => Stream<Profile?>.error(StateError('boom')),
        ),
      );
      await c.read(profileProvider.future).then((_) {}, onError: (_) {});
      expect(
        c.read(physiqueEditorEligibilityProvider).allows(DietPhase.cut),
        isFalse,
      );
    });

    test('age 30 is unrestricted for the editor', () async {
      final c = await make(profileOverride: profileData(_profile(age: 30)));
      await c.read(profileProvider.future);
      expect(
        c.read(physiqueEditorEligibilityProvider).allows(DietPhase.cut),
        isTrue,
      );
    });

    test('roadmap eligibility adds the analysis confidence', () async {
      final low = await seedGoal(confidence: AssessmentConfidence.low);
      final c = await make(profileOverride: profileData(_profile(age: 30)));
      await c.read(profileProvider.future);
      await c.read(physiqueLatestAnalysisProvider(low).future);
      final e = c.read(physiqueRoadmapEligibilityProvider(low));
      expect(e.allows(DietPhase.cut), isFalse);
      expect(e.reasons, contains(PhaseRestrictionReason.lowConfidence));
      // The manual editor ignores confidence.
      expect(
        c.read(physiqueEditorEligibilityProvider).allows(DietPhase.cut),
        isTrue,
      );

      final med = await seedGoal(confidence: AssessmentConfidence.medium);
      await c.read(physiqueLatestAnalysisProvider(med).future);
      expect(
        c.read(physiqueRoadmapEligibilityProvider(med)).allows(DietPhase.cut),
        isTrue,
      );
    });
  });

  group('next check-in', () {
    test('visible inside the window, null once it opens', () async {
      final id = await seedGoal(roadmap: threePhase);
      await assessments.recordCheckIn(
        CheckInRecord(
          goalId: id,
          pose: 'front',
          relativePath: 'physique/a.jpg',
        ),
      );
      var c = await make();
      await c.read(physiqueLastCheckInAtProvider(id).future);
      expect(c.read(physiqueNextCheckInProvider(id)), DateTime(2026, 10, 8));

      clock.set(DateTime(2026, 10, 8, 8));
      c = await make();
      await c.read(physiqueLastCheckInAtProvider(id).future);
      expect(c.read(physiqueNextCheckInProvider(id)), isNull);
    });

    test('null when there is no check-in', () async {
      final id = await seedGoal(roadmap: threePhase);
      final c = await make();
      await c.read(physiqueLastCheckInAtProvider(id).future);
      expect(c.read(physiqueNextCheckInProvider(id)), isNull);
    });
  });

  group('phase status', () {
    test('week one of a three phase accepted roadmap', () async {
      final id = await seedGoal(roadmap: threePhase);
      final s = await status(await make(), id);
      expect(s.position, 1);
      expect(s.total, 3);
      expect(s.current!.phaseType, 'cut');
      expect(s.next!.phaseType, 'maintain');
      expect(s.evaluation!.weekInPhase, 1);
      expect(s.offerAdvance, isFalse);
      expect(s.proposalPending, isFalse);
    });

    test('duration elapsed offers advance; a snooze hides it', () async {
      final id = await seedGoal(roadmap: threePhase);
      clock.set(t0.add(const Duration(days: 84)));
      expect((await status(await make(), id)).offerAdvance, isTrue);

      await roadmaps.postponeAdvance(id);
      expect((await status(await make(), id)).offerAdvance, isFalse);

      clock.set(t0.add(const Duration(days: 91)));
      expect((await status(await make(), id)).offerAdvance, isTrue);
    });

    test('criteria met by weight offers advance early', () async {
      final id = await seedGoal(roadmap: threePhase);
      await logMetric('2026-10-02', 'bodyweight', 74.5);
      clock.set(DateTime(2026, 10, 3, 9));
      final s = await status(await make(), id);
      final weight = s.evaluation!.criteria.firstWhere(
        (k) => k.kind == ExitCriterionKind.weight,
      );
      expect(weight.met, isTrue);
      expect(s.offerAdvance, isTrue);
    });

    test('pending proposal never offers advance', () async {
      final id = await seedGoal(roadmap: threePhase, accept: false);
      clock.set(t0.add(const Duration(days: 200)));
      final s = await status(await make(), id);
      expect(s.proposalPending, isTrue);
      expect(s.current, isNull);
      expect(s.position, 0);
      expect(s.evaluation, isNull);
      expect(s.offerAdvance, isFalse);
    });

    test('last phase has no next and no offer', () async {
      final id = await seedGoal(
        roadmap: const [
          RoadmapPhaseDraft(phase: DietPhase.maintain, plannedWeeks: 2),
        ],
      );
      clock.set(t0.add(const Duration(days: 60)));
      final s = await status(await make(), id);
      expect(s.next, isNull);
      expect(s.total, 1);
      expect(s.evaluation!.criteriaMet, isTrue);
      expect(s.offerAdvance, isFalse);
    });

    test('unknown phase type falls back to maintain', () async {
      final id = await seedGoal(roadmap: threePhase);
      await (db.update(db.physiqueRoadmapPhases)
            ..where((p) => p.goalId.equals(id) & p.orderIndex.equals(0)))
          .write(const PhysiqueRoadmapPhasesCompanion(phaseType: Value('xyz')));
      final s = await status(await make(), id);
      expect(s.evaluation, isNotNull);
    });
  });

  group('body fat reading', () {
    test('a measurement wins over the analysis estimate', () async {
      final id = await seedGoal(roadmap: threePhase);
      await logMetric('2026-10-03', 'body_fat', 18);
      final c = await make();
      await status(c, id);
      final r = c.read(physiqueBodyFatReadingProvider(id));
      expect(r.source, PhysiqueBfSource.measured);
      expect(r.percent, 18);
      expect(r.reliable, isTrue);
    });

    test('the latest measurement wins', () async {
      final id = await seedGoal(roadmap: threePhase);
      await logMetric('2026-10-03', 'body_fat', 18);
      await logMetric('2026-10-09', 'body_fat', 17);
      final c = await make();
      await status(c, id);
      expect(c.read(physiqueBodyFatReadingProvider(id)).percent, 17);
    });

    test('an entry dated before the goal start is ignored', () async {
      final id = await seedGoal(roadmap: threePhase);
      await logMetric('2026-09-20', 'body_fat', 15);
      final c = await make();
      await status(c, id);
      final r = c.read(physiqueBodyFatReadingProvider(id));
      expect(r.source, PhysiqueBfSource.estimate);
      expect(r.percent, 20);
      expect(r.reliable, isTrue);
    });

    test('a low-confidence estimate is not reliable', () async {
      final id = await seedGoal(
        roadmap: threePhase,
        confidence: AssessmentConfidence.low,
      );
      final c = await make();
      await status(c, id);
      final r = c.read(physiqueBodyFatReadingProvider(id));
      expect(r.source, PhysiqueBfSource.estimate);
      expect(r.reliable, isFalse);
    });

    test('no measurement and no estimate is none', () async {
      final id = await seedGoal(roadmap: threePhase, bf: null);
      final c = await make();
      await status(c, id);
      final r = c.read(physiqueBodyFatReadingProvider(id));
      expect(r.source, PhysiqueBfSource.none);
      expect(r.percent, isNull);
      expect(r.reliable, isFalse);
    });

    test('hint follows the rule and clears with a measurement', () async {
      final none = await seedGoal(roadmap: threePhase, bf: null);
      var c = await make();
      expect((await status(c, none)).logMeasurementsHint, isTrue);

      final low = await seedGoal(
        roadmap: threePhase,
        confidence: AssessmentConfidence.low,
      );
      c = await make();
      expect((await status(c, low)).logMeasurementsHint, isTrue);

      final medium = await seedGoal(roadmap: threePhase);
      c = await make();
      expect((await status(c, medium)).logMeasurementsHint, isFalse);

      final lowAgain = await seedGoal(
        roadmap: threePhase,
        confidence: AssessmentConfidence.low,
      );
      await logMetric('2026-10-02', 'body_fat', 19);
      c = await make();
      expect((await status(c, lowAgain)).logMeasurementsHint, isFalse);
    });

    test('a BF target is met by a measurement, not a low-confidence '
        'estimate', () async {
      final id = await seedGoal(
        roadmap: threePhase,
        confidence: AssessmentConfidence.low,
        bf: 11,
      );
      var s = await status(await make(), id);
      var bfCriterion = s.evaluation!.criteria.firstWhere(
        (k) => k.kind == ExitCriterionKind.bodyFat,
      );
      expect(bfCriterion.met, isFalse);

      await logMetric('2026-10-04', 'body_fat', 11.5);
      s = await status(await make(), id);
      bfCriterion = s.evaluation!.criteria.firstWhere(
        (k) => k.kind == ExitCriterionKind.bodyFat,
      );
      expect(bfCriterion.met, isTrue);
    });
  });

  group('legacy migration provider', () {
    Future<int> activeCount() async => (await (db.select(
      db.physiqueGoals,
    )..where((g) => g.status.equals('active'))).get()).length;

    test('reconciles a duplicate active goal at startup', () async {
      await seedGoal(archiveExisting: false);
      await seedGoal(archiveExisting: false);
      expect(await activeCount(), 2);

      final c = await make();
      await c.read(physiqueLegacyMigrationProvider.future);
      expect(await activeCount(), 1);
    });

    test('a failing migration returns null yet still reconciles', () async {
      await seedGoal(archiveExisting: false);
      await seedGoal(archiveExisting: false);

      final c = await make(
        extra: [
          physiquePhotoStoreProvider.overrideWith(
            (ref) => throw StateError('no documents dir'),
          ),
        ],
      );
      final result = await c.read(physiqueLegacyMigrationProvider.future);
      expect(result, isNull);
      expect(await activeCount(), 1);
    });
  });

  test('Clock override is the one the providers read', () async {
    final c = await make();
    expect(c.read(clockProvider), same(clock));
  });
}
