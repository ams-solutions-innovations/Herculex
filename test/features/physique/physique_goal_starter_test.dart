import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_goal_starter.dart';
import 'package:herculex/features/physique/data/physique_dream_photo_repository.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/data/physique_privacy_preferences.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/exif_jpeg_fixture.dart';
import '../../support/fake_clock.dart';
import '../../support/fake_face_detector.dart';
import '../../support/test_database.dart';

class _ThrowingGoals extends PhysiqueGoalRepository {
  _ThrowingGoals(super.db, super.clock);

  @override
  Future<int> startGoal(StartGoalInput input) =>
      throw StateError('write failed');
}

DreamPhysiqueAnalysisResult _result({
  double bf = 25,
  double target = 15,
  double change = -9,
  int months = 6,
  AssessmentConfidence confidence = AssessmentConfidence.medium,
}) => DreamPhysiqueAnalysisResult(
  estimatedMonths: months,
  timeframeRange: '5-7 months',
  weightChangeKg: change,
  leanMuscleGainKg: 1,
  fatLossKg: 10,
  targetBfPercent: target,
  currentEstimatedBf: bf,
  musclePriorities: const [],
  nutritionStrategy: 'deficit',
  trainingAdvice: 'lift',
  overallAssessment: 'ok',
  targetAestheticStyle: 'lean',
  currentBfRangeMin: bf - 2,
  currentBfRangeMax: bf + 2,
  assessmentConfidence: confidence,
);

Profile _profile({int? age = 30, double? weight = 90}) => Profile(
  goal: FitnessGoal.weightLoss,
  activityLevel: ActivityLevel.active,
  ageYears: age,
  weightKg: weight,
);

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late Directory docs;
  late Directory staging;
  late Directory pickerDir;
  late SharedPreferences prefs;

  setUp(() async {
    db = await openTestDatabase();
    clock = FakeClock(DateTime(2026, 10, 1, 9));
    docs = await Directory.systemTemp.createTemp('starter_docs_');
    staging = await Directory.systemTemp.createTemp('starter_stage_');
    pickerDir = await Directory.systemTemp.createTemp('starter_pick_');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() async {
    await db.close();
    for (final d in [docs, staging, pickerDir]) {
      if (d.existsSync()) await d.delete(recursive: true);
    }
  });

  File pick(String name, {List<int>? bytes}) =>
      File('${pickerDir.path}/$name')
        ..writeAsBytesSync(bytes ?? buildJpegWithExif());

  PhysiqueGoalStarter make({
    Profile? profile,
    List<FaceBox> faces = const [],
    PhysiqueGoalRepository? goals,
    int? maintenance,
  }) => PhysiqueGoalStarter(
    goals: goals ?? PhysiqueGoalRepository(db, clock),
    sanitizer: PhysiquePhotoSanitizer(
      faceDetector: FakeFaceDetector(boxes: faces),
      stagingDirectory: () async => staging,
    ),
    store: PhysiquePhotoStore(documentsDirectory: () async => docs),
    dreamPhotos: PhysiqueDreamPhotoRepository(
      store: PhysiquePhotoStore(documentsDirectory: () async => docs),
      sanitizer: PhysiquePhotoSanitizer(
        faceDetector: FakeFaceDetector(boxes: faces),
        stagingDirectory: () async => staging,
      ),
    ),
    privacy: PhysiquePrivacyPreferences(prefs),
    clock: clock,
    readProfile: () => profile,
    readMaintenanceKcal: () => maintenance,
  );

  const face = FaceBox(left: 10, top: 5, width: 20, height: 20);

  Future<List<PhysiqueRoadmapPhaseData>> phasesOf(int goalId) => (db.select(
    db.physiqueRoadmapPhases,
  )..where((p) => p.goalId.equals(goalId))).get();

  Future<List<PhysiquePhotoData>> photosOf(int goalId) => (db.select(
    db.physiquePhotos,
  )..where((p) => p.goalId.equals(goalId))).get();

  group('stagePhotos', () {
    test('stores the blur choice and caps at three photos', () async {
      final starter = make();
      final files = [for (var i = 0; i < 4; i++) pick('p$i.jpg')];
      final staged = await starter.stagePhotos(files: files, blurFaces: true);
      expect(staged, hasLength(3));
      expect(prefs.getBool(PhysiquePrivacyPreferences.blurKey), isTrue);
      for (final f in files) {
        expect(f.existsSync(), isTrue, reason: 'picker files stay');
      }
      await starter.discardStaged(staged);
      for (final s in staged) {
        expect(s.file.existsSync(), isFalse);
      }
    });

    test('a corrupt photo is skipped', () async {
      final starter = make();
      final staged = await starter.stagePhotos(
        files: [
          pick('bad.jpg', bytes: [1, 2, 3]),
          pick('ok.jpg'),
        ],
        blurFaces: false,
      );
      expect(staged, hasLength(1));
      expect(prefs.getBool(PhysiquePrivacyPreferences.blurKey), isFalse);
    });

    test('reports noFaceFound per photo when blur finds nothing', () async {
      final staged = await make().stagePhotos(
        files: [pick('a.jpg')],
        blurFaces: true,
      );
      expect(staged.single.noFaceFound, isTrue);
      expect(staged.single.blurApplied, isFalse);
    });
  });

  group('startFromAnalysis', () {
    test('persists goal, analysis, roadmap and sanitised photos', () async {
      final goals = PhysiqueGoalRepository(db, clock);
      final old = await goals.startGoal(
        StartGoalInput(
          estimatedMonths: 3,
          targetBfPercent: 12,
          analyses: [AnalysisInput(analyzedAt: DateTime(2026, 9, 1))],
        ),
      );
      final starter = make(profile: _profile(), maintenance: 2800);
      final staged = await starter.stagePhotos(
        files: [pick('a.jpg'), pick('b.jpg')],
        blurFaces: false,
      );
      final id = await starter.startFromAnalysis(
        result: _result(),
        staged: staged,
        targetPhotoCount: 1,
      );

      final goal = await goals.getGoal(id);
      expect(goal!.source, 'ai_analysis');
      expect(goal.status, 'active');
      expect(goal.startWeightKg, 90);
      expect(goal.startBfPercent, 25);
      expect((await goals.getGoal(old))!.status, 'archived');

      final analysis = await (db.select(
        db.physiqueAssessments,
      )..where((a) => a.goalId.equals(id))).get();
      expect(analysis, hasLength(1));
      expect(analysis.single.kind, 'analysis');
      expect(analysis.single.summaryJson, contains('"estimatedMonths":6'));
      expect(analysis.single.confidence, 'medium');
      expect(analysis.single.bfRangeMin, 23);

      final phases = await phasesOf(id);
      expect(phases, isNotEmpty);
      expect(phases.first.phaseType, 'cut');

      final photos = await photosOf(id);
      expect(photos, hasLength(2));
      for (final p in photos) {
        expect(p.role, 'baseline');
        expect(p.pose, 'front');
        expect(p.blurred, isFalse);
        expect(p.relativePath, startsWith('physique/${goal.syncUuid}/'));
        final file = await PhysiquePhotoStore(
          documentsDirectory: () async => docs,
        ).resolve(p.relativePath);
        expect(file.existsSync(), isTrue);
      }
      for (final s in staged) {
        expect(s.file.existsSync(), isFalse, reason: 'adopted by move');
      }
    });

    test('a blurred photo is stored blurred; a no-face photo is not', () async {
      final withFace = make(profile: _profile(), faces: const [face]);
      var staged = await withFace.stagePhotos(
        files: [pick('a.jpg')],
        blurFaces: true,
      );
      var id = await withFace.startFromAnalysis(
        result: _result(),
        staged: staged,
        targetPhotoCount: 0,
      );
      expect((await photosOf(id)).single.blurred, isTrue);

      final noFace = make(profile: _profile());
      staged = await noFace.stagePhotos(
        files: [pick('b.jpg')],
        blurFaces: true,
      );
      expect(staged.single.noFaceFound, isTrue);
      id = await noFace.startFromAnalysis(
        result: _result(),
        staged: staged,
        targetPhotoCount: 0,
      );
      expect((await photosOf(id)).single.blurred, isFalse);
    });

    test('without a profile weight it proposes a single maintain', () async {
      final starter = make(profile: _profile(weight: null));
      final id = await starter.startFromAnalysis(
        result: _result(),
        staged: const [],
        targetPhotoCount: 0,
      );
      final phases = await phasesOf(id);
      expect(phases, hasLength(1));
      expect(phases.single.phaseType, DietPhase.maintain.name);

      final noProfile = make();
      final id2 = await noProfile.startFromAnalysis(
        result: _result(),
        staged: const [],
        targetPhotoCount: 0,
      );
      expect((await phasesOf(id2)).single.phaseType, 'maintain');
    });

    test('an under-18 profile never gets a cut or bulk', () async {
      final starter = make(profile: _profile(age: 17));
      final id = await starter.startFromAnalysis(
        result: _result(),
        staged: const [],
        targetPhotoCount: 0,
      );
      final types = (await phasesOf(id)).map((p) => p.phaseType).toSet();
      expect(types, isNotEmpty);
      expect(types, isNot(contains('cut')));
      expect(types, isNot(contains('bulk')));
    });

    test('a low-confidence analysis never gets a cut or bulk', () async {
      final starter = make(profile: _profile());
      final id = await starter.startFromAnalysis(
        result: _result(confidence: AssessmentConfidence.low),
        staged: const [],
        targetPhotoCount: 0,
      );
      final types = (await phasesOf(id)).map((p) => p.phaseType).toSet();
      expect(types, isNot(contains('cut')));
    });

    test('a failed write cleans up files and rethrows', () async {
      final starter = make(
        profile: _profile(),
        goals: _ThrowingGoals(db, clock),
      );
      final pickA = pick('a.jpg');
      final staged = await starter.stagePhotos(
        files: [pickA, pick('b.jpg')],
        blurFaces: false,
      );
      await expectLater(
        starter.startFromAnalysis(
          result: _result(),
          staged: staged,
          targetPhotoCount: 0,
        ),
        throwsStateError,
      );
      final root = Directory('${docs.path}/physique');
      final leftovers = root.existsSync()
          ? root.listSync(recursive: true).whereType<File>().toList()
          : <File>[];
      expect(leftovers, isEmpty);
      expect(staging.listSync(), isEmpty);
      expect(pickA.existsSync(), isTrue, reason: 'caller owns picker files');
      expect(await db.select(db.physiqueGoals).get(), isEmpty);
    });
  });
}
