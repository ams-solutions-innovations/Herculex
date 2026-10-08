import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_replan_flow.dart';
import 'package:herculex/features/physique/data/physique_assessment_repository.dart';
import 'package:herculex/features/physique/data/physique_dream_photo_repository.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/data/physique_roadmap_repository.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

import '../../support/exif_jpeg_fixture.dart';
import '../../support/fake_clock.dart';
import '../../support/fake_face_detector.dart';
import '../../support/test_database.dart';

const _uuid = 'a1b2c3d4-0000-4000-8000-000000000001';

class _NoBackend implements GeminiBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the AI: records what it was sent and answers (or fails) as
/// told.
class _FakeService extends DreamPhysiqueService {
  _FakeService(this.result) : super(_NoBackend());

  DreamPhysiqueAnalysisResult result;
  Object? failure;
  int calls = 0;
  List<File>? currentImages;
  List<File>? targetImages;
  Profile? profile;

  @override
  Future<DreamPhysiqueAnalysisResult> compareAndAnalyzePhysique({
    required List<File> currentImages,
    required List<File> targetImages,
    required bool consentGranted,
    Profile? profile,
    Map<String, double>? measurements,
    String? userNote,
  }) async {
    calls++;
    this.currentImages = currentImages;
    this.targetImages = targetImages;
    this.profile = profile;
    final f = failure;
    if (f != null) throw f;
    return result;
  }
}

DreamPhysiqueAnalysisResult _result({
  double bf = 20,
  double target = 12,
  double change = -2.5,
  double fat = 6,
  double lean = 3.5,
  int months = 12,
}) => DreamPhysiqueAnalysisResult(
  estimatedMonths: months,
  timeframeRange: '10-14 months',
  weightChangeKg: change,
  leanMuscleGainKg: lean,
  fatLossKg: fat,
  targetBfPercent: target,
  currentEstimatedBf: bf,
  musclePriorities: const [],
  nutritionStrategy: 'deficit then surplus',
  trainingAdvice: 'lift',
  overallAssessment: 'ok',
  targetAestheticStyle: 'lean',
  currentBfRangeMin: bf - 2,
  currentBfRangeMax: bf + 2,
  assessmentConfidence: AssessmentConfidence.medium,
);

const _cut = RoadmapPhaseDraft(
  phase: DietPhase.cut,
  plannedWeeks: 12,
  targetWeightKg: 74,
  targetBfPercent: 12,
  weeklyRateKg: 0.5,
);
const _hold = RoadmapPhaseDraft(
  phase: DietPhase.maintain,
  plannedWeeks: 2,
  targetWeightKg: 74,
  weeklyRateKg: 0,
);
const _build = RoadmapPhaseDraft(
  phase: DietPhase.maingain,
  plannedWeeks: 38,
  targetWeightKg: 78.2,
  weeklyRateKg: 0.11,
);

class _ThrowingGoals extends PhysiqueGoalRepository {
  _ThrowingGoals(super.db, super.clock);

  @override
  Future<int> applyReanalysis({
    required int goalId,
    required AnalysisInput analysis,
    required int estimatedMonths,
    required double targetBfPercent,
    required List<RoadmapPhaseDraft> roadmap,
    NewPhotoRow? photo,
  }) => throw StateError('write failed');
}

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late Directory docs;
  late Directory staging;
  late Directory pickerDir;
  late PhysiquePhotoSanitizer sanitizer;
  late PhysiquePhotoStore store;
  late PhysiqueDreamPhotoRepository dreamPhotos;
  late PhysiqueGoalRepository goals;
  late PhysiqueRoadmapRepository roadmap;
  late _FakeService service;

  setUp(() async {
    db = await openTestDatabase();
    clock = FakeClock(DateTime(2026, 10, 1, 9));
    docs = await Directory.systemTemp.createTemp('replan_docs_');
    staging = await Directory.systemTemp.createTemp('replan_stage_');
    pickerDir = await Directory.systemTemp.createTemp('replan_pick_');
    sanitizer = PhysiquePhotoSanitizer(
      faceDetector: FakeFaceDetector(),
      stagingDirectory: () async => staging,
    );
    store = PhysiquePhotoStore(documentsDirectory: () async => docs);
    dreamPhotos = PhysiqueDreamPhotoRepository(
      store: store,
      sanitizer: sanitizer,
    );
    goals = PhysiqueGoalRepository(db, clock);
    roadmap = PhysiqueRoadmapRepository(db, clock);
    service = _FakeService(_result());
  });
  tearDown(() async {
    await db.close();
    for (final d in [docs, staging, pickerDir]) {
      if (d.existsSync()) await d.delete(recursive: true);
    }
  });

  File pick(String name) =>
      File('${pickerDir.path}/$name')..writeAsBytesSync(buildJpegWithExif());

  PhysiqueReplanFlow make({
    PhysiqueGoalRepository? goalRepo,
    Profile? profile,
  }) => PhysiqueReplanFlow(
    service: service,
    dreamPhotos: dreamPhotos,
    assessments: PhysiqueAssessmentRepository(db, clock),
    goals: goalRepo ?? goals,
    store: store,
    clock: clock,
    readProfile: () =>
        profile ??
        const Profile(
          goal: FitnessGoal.weightLoss,
          activityLevel: ActivityLevel.active,
          ageYears: 30,
          weightKg: 80,
        ),
    readMaintenanceKcal: () => 2500,
  );

  /// A goal with a running 3-phase roadmap whose analysis is [analysedDaysAgo]
  /// old.
  Future<PhysiqueGoalData> startGoal({
    bool accept = true,
    bool withDreamPhoto = true,
    int analysedDaysAgo = 20,
  }) async {
    final id = await goals.startGoal(
      StartGoalInput(
        goalSyncUuid: _uuid,
        estimatedMonths: 12,
        targetBfPercent: 12,
        startWeightKg: 80,
        analyses: [
          AnalysisInput(
            analyzedAt: clock.now().subtract(Duration(days: analysedDaysAgo)),
            currentBfPercent: 20,
          ),
        ],
        roadmap: const [_cut, _hold, _build],
      ),
    );
    if (accept) {
      await roadmap.replaceRoadmap(id, const [
        _cut,
        _hold,
        _build,
      ], accept: true);
    }
    if (withDreamPhoto) {
      expect(
        await dreamPhotos.save(pick('dream.jpg'), goalUuid: _uuid),
        isTrue,
      );
    }
    return (await goals.getGoal(id))!;
  }

  Future<StagedPhoto> stage() => sanitizer.stage(pick('now.jpg'));

  Future<List<PhysiqueRoadmapPhaseData>> phases(int id) =>
      roadmap.watchPhases(id).first;

  group('checkReady', () {
    test('passes for a running goal with a dream photo', () async {
      final goal = await startGoal();
      await make().checkReady(goal, weightKg: 80);
    });

    Future<ReplanBlock> blockOf(Future<void> Function() run) async {
      try {
        await run();
      } on ReplanBlockedException catch (e) {
        return e.block;
      }
      fail('expected the update to be blocked');
    }

    test('a roadmap that was never accepted cannot be updated', () async {
      final goal = await startGoal(accept: false);
      expect(
        await blockOf(() => make().checkReady(goal, weightKg: 80)),
        ReplanBlock.notStarted,
      );
    });

    test('needs the dream photo on this device', () async {
      final goal = await startGoal(withDreamPhoto: false);
      expect(
        await blockOf(() => make().checkReady(goal, weightKg: 80)),
        ReplanBlock.noDreamPhoto,
      );
    });

    test('needs a current weight', () async {
      final goal = await startGoal();
      expect(
        await blockOf(() => make().checkReady(goal)),
        ReplanBlock.noWeight,
      );
    });

    test('waits a week after the last analysis', () async {
      final goal = await startGoal(analysedDaysAgo: 3);
      try {
        await make().checkReady(goal, weightKg: 80);
        fail('expected tooSoon');
      } on ReplanBlockedException catch (e) {
        expect(e.block, ReplanBlock.tooSoon);
        expect(e.nextEligibleDate, isNotNull);
      }
      expect(service.calls, 0, reason: 'nothing was sent to the AI');
    });
  });

  group('analyse', () {
    test('sends the new photo and the dream photo, plans from today', () async {
      final goal = await startGoal();
      final staged = await stage();
      final p = await make().analyse(
        goal: goal,
        staged: staged,
        consentGranted: true,
        weightKg: 77.4,
        currentPhase: DietPhase.cut,
        weeksInPhase: 0,
      );
      expect(service.calls, 1);
      expect(service.currentImages!.single.path, staged.file.path);
      expect(service.targetImages!.single.path, endsWith('dream_target.jpg'));
      expect(
        service.profile!.weightKg,
        77.4,
        reason: 'the AI is told today\'s weight, not the stale profile one',
      );
      expect(p.weightKg, 77.4);
      expect(p.phases.first.phase, DietPhase.cut);
      expect(p.phases.first.targetWeightKg, closeTo(71.4, 1e-9));
      expect(p.proposal.totalWeeks, p.proposal.horizonWeeks);
      for (final d in p.phases) {
        expect(d.targetWeightKg, isNotNull);
      }
    });

    test('carries the weeks already spent when the phase continues', () async {
      final goal = await startGoal();
      final p = await make().analyse(
        goal: goal,
        staged: await stage(),
        consentGranted: true,
        weightKg: 77,
        currentPhase: DietPhase.cut,
        weeksInPhase: 5,
      );
      expect(
        p.phases.first.plannedWeeks,
        5 + p.proposal.phases.first.plannedWeeks,
      );
    });

    test('does not carry weeks into a different phase', () async {
      final goal = await startGoal();
      final p = await make().analyse(
        goal: goal,
        staged: await stage(),
        consentGranted: true,
        weightKg: 77,
        currentPhase: DietPhase.maintain,
        weeksInPhase: 5,
      );
      expect(p.phases.first.plannedWeeks, p.proposal.phases.first.plannedWeeks);
    });

    test('an AI failure surfaces and stores nothing', () async {
      final goal = await startGoal();
      service.failure = const DreamPhysiqueAnalysisException('server down');
      await expectLater(
        make().analyse(
          goal: goal,
          staged: await stage(),
          consentGranted: true,
          weightKg: 77,
          currentPhase: DietPhase.cut,
          weeksInPhase: 0,
        ),
        throwsA(isA<DreamPhysiqueAnalysisException>()),
      );
      final analyses = await (db.select(
        db.physiqueAssessments,
      )..where((a) => a.kind.equals('analysis'))).get();
      expect(analyses, hasLength(1), reason: 'only the original analysis');
      expect((await phases(goal.id)).map((p) => p.phaseType), [
        'cut',
        'maintain',
        'maingain',
      ]);
    });
  });

  group('apply', () {
    Future<(ReplanProposal, StagedPhoto)> proposeFor(
      PhysiqueGoalData goal, {
      DietPhase currentPhase = DietPhase.cut,
      int weeks = 0,
    }) async {
      final staged = await stage();
      final p = await make().analyse(
        goal: goal,
        staged: staged,
        consentGranted: true,
        weightKg: 77.4,
        currentPhase: currentPhase,
        weeksInPhase: weeks,
      );
      return (p, staged);
    }

    test('stores analysis, photo, estimate and roadmap together', () async {
      final goal = await startGoal();
      final (p, staged) = await proposeFor(goal);
      await make().apply(
        goal: goal,
        proposal: p,
        staged: staged,
        pose: 'front',
      );

      final analyses =
          await (db.select(db.physiqueAssessments)
                ..where((a) => a.kind.equals('analysis'))
                ..orderBy([(a) => OrderingTerm.desc(a.id)]))
              .get();
      expect(analyses, hasLength(2));
      final latest = analyses.first;
      expect(latest.currentBfPercent, 20);
      expect(latest.weightKg, 77.4);
      expect(latest.summaryJson, contains('"fatLossKg":6'));
      expect(latest.summaryJson, contains('"leanGainKg":3.5'));

      final photos = await (db.select(
        db.physiquePhotos,
      )..where((p) => p.role.equals('checkin'))).get();
      expect(photos.single.assessmentId, latest.id);
      expect(
        (await store.resolve(photos.single.relativePath)).existsSync(),
        isTrue,
      );
      expect(staged.file.existsSync(), isFalse, reason: 'moved, not copied');

      final fresh = (await goals.getGoal(goal.id))!;
      expect(fresh.estimatedMonths, 12);
      expect(fresh.targetBfPercent, 12);

      final rows = await phases(goal.id);
      expect(rows.first.status, 'current');
      expect(rows.first.targetWeightKg, closeTo(71.4, 1e-9));
    });

    test('a new first phase closes the old one as done', () async {
      final goal = await startGoal();
      service.result = _result(bf: 13, target: 12, change: 1, fat: 0, lean: 3);
      final (p, staged) = await proposeFor(goal);
      expect(p.phases.first.phase, isNot(DietPhase.cut));
      await make().apply(
        goal: goal,
        proposal: p,
        staged: staged,
        pose: 'front',
      );

      final rows = await phases(goal.id);
      expect(rows.first.phaseType, 'cut');
      expect(rows.first.status, 'done');
      expect(rows.first.completedAt, clock.now());
      expect(rows[1].status, 'current');
      expect(rows[1].phaseType, p.phases.first.phase.name);
    });

    test('continuing the same phase keeps its start date', () async {
      final goal = await startGoal();
      final startedAt = (await phases(goal.id)).first.startedAt;
      clock.advance(const Duration(days: 35));
      final (p, staged) = await proposeFor(goal, weeks: 5);
      await make().apply(
        goal: goal,
        proposal: p,
        staged: staged,
        pose: 'front',
      );

      final rows = await phases(goal.id);
      expect(rows.first.phaseType, 'cut');
      expect(rows.first.status, 'current');
      expect(rows.first.startedAt, startedAt);
      expect(rows.first.plannedWeeks, p.phases.first.plannedWeeks);
      expect(rows.map((r) => r.status), isNot(contains('done')));
    });

    test(
      'a failed write leaves the roadmap and the file store clean',
      () async {
        final goal = await startGoal();
        final (p, staged) = await proposeFor(goal);
        final before = await phases(goal.id);
        await expectLater(
          make(
            goalRepo: _ThrowingGoals(db, clock),
          ).apply(goal: goal, proposal: p, staged: staged, pose: 'front'),
          throwsStateError,
        );
        final after = await phases(goal.id);
        expect(
          after.map((r) => r.targetWeightKg),
          before.map((r) => r.targetWeightKg),
        );
        final goalDir = Directory('${docs.path}/physique/$_uuid');
        final files = goalDir
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .toList();
        expect(files, ['dream_target.jpg'], reason: 'no orphaned photo');
      },
    );
  });
}
