import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_check_in_flow.dart';
import 'package:herculex/features/physique/data/physique_assessment_repository.dart';
import 'package:herculex/features/physique/data/physique_checkin_service.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

import '../../support/exif_jpeg_fixture.dart';
import '../../support/fake_clock.dart';
import '../../support/fake_face_detector.dart';
import '../../support/test_database.dart';

class _FakeBackend implements PhysiqueCheckInBackend {
  Object? error;
  int calls = 0;
  int lastBaselineCount = 0;
  Map<String, dynamic>? lastContext;
  Map<String, dynamic> result = {
    'directionBand': {'low': 0.3, 'high': 0.6},
    'confidence': 'medium',
    'reason': 'Visible progress in the shoulders.',
    'limitations': ['lighting'],
  };

  @override
  Future<(Map<String, dynamic>, Map<String, dynamic>)> analyzePhysiqueCheckIn({
    required List<Map<String, dynamic>> baselineImages,
    required Map<String, dynamic> currentImage,
    required Map<String, dynamic> context,
    String? userNote,
  }) async {
    calls++;
    lastBaselineCount = baselineImages.length;
    lastContext = context;
    if (error != null) throw error!;
    return (result, {'modelVersion': 'm1', 'knowledgeVersion': 'k1'});
  }
}

class _ThrowingAssessments extends PhysiqueAssessmentRepository {
  _ThrowingAssessments(super.db, super.clock);

  @override
  Future<int> recordCheckIn(CheckInRecord record) =>
      throw StateError('write failed');
}

void main() {
  late AppDatabase db;
  late FakeClock clock;
  late Directory docs;
  late Directory staging;
  late Directory pickerDir;
  late PhysiqueGoalRepository goals;
  late PhysiqueAssessmentRepository assessments;
  late PhysiquePhotoStore store;
  late PhysiquePhotoSanitizer sanitizer;
  late _FakeBackend backend;
  late PhysiqueCheckInFlow flow;
  late PhysiqueGoalData goal;

  const goalUuid = 'goal-uuid-1';

  setUp(() async {
    db = await openTestDatabase();
    clock = FakeClock(DateTime(2026, 10, 1, 9));
    docs = await Directory.systemTemp.createTemp('flow_docs_');
    staging = await Directory.systemTemp.createTemp('flow_stage_');
    pickerDir = await Directory.systemTemp.createTemp('flow_pick_');
    goals = PhysiqueGoalRepository(db, clock);
    assessments = PhysiqueAssessmentRepository(db, clock);
    store = PhysiquePhotoStore(documentsDirectory: () async => docs);
    sanitizer = PhysiquePhotoSanitizer(
      faceDetector: FakeFaceDetector(),
      stagingDirectory: () async => staging,
    );
    backend = _FakeBackend();
    flow = PhysiqueCheckInFlow(
      sanitizer: sanitizer,
      store: store,
      assessments: assessments,
      service: PhysiqueCheckInService(backend),
      clock: clock,
    );
    final id = await goals.startGoal(
      StartGoalInput(
        goalSyncUuid: goalUuid,
        estimatedMonths: 6,
        targetBfPercent: 12,
        analyses: [
          AnalysisInput(
            analyzedAt: DateTime(2026, 9, 30),
            currentBfPercent: 20,
            confidence: AssessmentConfidence.medium,
          ),
        ],
      ),
    );
    goal = (await goals.getGoal(id))!;
  });
  tearDown(() async {
    await db.close();
    for (final d in [docs, staging, pickerDir]) {
      if (d.existsSync()) await d.delete(recursive: true);
    }
  });

  var pickCounter = 0;
  File pick() =>
      File('${pickerDir.path}/p${pickCounter++}.jpg')
        ..writeAsBytesSync(buildJpegWithExif());

  Future<StagedPhoto> staged({bool blur = false}) =>
      flow.stage(pick(), blurFaces: blur);

  Future<int> addBaseline(String pose) async {
    final outcome = await flow.saveBaseline(
      goal: goal,
      staged: await staged(),
      pose: pose,
    );
    return (outcome as BaselineSaved).photoId;
  }

  Future<List<PhysiqueAssessmentData>> checkInRows() => (db.select(
    db.physiqueAssessments,
  )..where((a) => a.kind.equals('checkin'))).get();

  int storedFiles() {
    final root = Directory('${docs.path}/physique');
    if (!root.existsSync()) return 0;
    return root.listSync(recursive: true).whereType<File>().length;
  }

  Future<CheckInOutcome> complete(
    StagedPhoto s, {
    bool analyze = true,
    bool consent = true,
    DietPhase phase = DietPhase.cut,
    double? trend,
    List<CheckInProgressStep>? steps,
    PhysiqueCheckInFlow? using,
  }) => (using ?? flow).completeCheckIn(
    goal: goal,
    staged: s,
    pose: 'front',
    phase: phase,
    weeksInPhase: 3,
    weightKg: 82.5,
    weeklyTrendKg: trend,
    analyze: analyze,
    consentGranted: consent,
    onProgress: steps?.add,
  );

  group('stage', () {
    test('reports progress steps and never modifies the source', () async {
      final src = pick();
      final before = src.readAsBytesSync();
      final steps = <CheckInProgressStep>[];
      final s = await flow.stage(src, blurFaces: false, onProgress: steps.add);
      expect(steps, [CheckInProgressStep.removingLocation]);
      expect(s.file.existsSync(), isTrue);
      expect(src.readAsBytesSync(), before);

      steps.clear();
      await flow.stage(src, blurFaces: true, onProgress: steps.add);
      expect(steps, [
        CheckInProgressStep.removingLocation,
        CheckInProgressStep.checkingFaces,
      ]);
    });

    test('discardStaged removes the temp file', () async {
      final s = await staged();
      await flow.discardStaged(s);
      expect(s.file.existsSync(), isFalse);
    });
  });

  group('completeCheckIn with analysis', () {
    test('classifies in Dart and persists the evidence', () async {
      await addBaseline('side');
      await addBaseline('front');
      final s = await staged();
      final steps = <CheckInProgressStep>[];
      final outcome = await complete(s, steps: steps);

      final recorded = outcome as CheckInRecorded;
      expect(recorded.analyzed, isTrue);
      expect(recorded.verdict, CheckInVerdict.onTrack);
      expect(recorded.evidence!.confidence, AssessmentConfidence.medium);
      expect(steps, [
        CheckInProgressStep.comparing,
        CheckInProgressStep.saving,
      ]);
      expect(backend.lastBaselineCount, 2);
      expect(backend.lastContext!['phase'], 'cut');
      expect(backend.lastContext!['weeksInPhase'], 3);

      final row = (await checkInRows()).single;
      expect(row.id, recorded.assessmentId);
      expect(row.verdict, 'on_track');
      expect(row.source, 'ai');
      expect(row.modelVersion, 'm1');
      expect(row.knowledgeVersion, 'k1');
      expect(row.weightKg, 82.5);
      expect(row.directionBandLow, closeTo(0.3, 1e-9));

      final photo = await (db.select(
        db.physiquePhotos,
      )..where((p) => p.assessmentId.equals(row.id))).getSingle();
      expect(photo.role, 'checkin');
      expect(photo.relativePath, startsWith('physique/$goalUuid/'));
      expect((await store.resolve(photo.relativePath)).existsSync(), isTrue);
      expect(s.file.existsSync(), isFalse, reason: 'adopted by move');
    });

    test('a contradicting weight trend tempers on-track', () async {
      await addBaseline('front');
      final outcome = await complete(await staged(), trend: 0.5);
      expect((outcome as CheckInRecorded).verdict, CheckInVerdict.inconclusive);
      expect((await checkInRows()).single.verdict, 'inconclusive');
    });

    test('caps at three baseline photos, front first', () async {
      for (final pose in ['side', 'back', 'side', 'front']) {
        try {
          await addBaseline(pose);
        } on BaselineLimitException {
          // the fourth is rejected
        }
      }
      expect(backend.calls, 0);
      await complete(await staged());
      expect(backend.lastBaselineCount, 3);
    });

    test('a second check-in inside the window is rejected before the '
        'network', () async {
      await addBaseline('front');
      expect(await complete(await staged()), isA<CheckInRecorded>());
      expect(backend.calls, 1);

      final second = await staged();
      await expectLater(
        complete(second),
        throwsA(isA<CheckInTooSoonException>()),
      );
      expect(backend.calls, 1);
      expect(second.file.existsSync(), isTrue, reason: 'caller discards');
      expect(await checkInRows(), hasLength(1));
    });

    test('consent not granted throws before any network call', () async {
      await addBaseline('front');
      final s = await staged();
      await expectLater(
        complete(s, consent: false),
        throwsA(
          isA<PhysiqueCheckInException>().having(
            (e) => e.kind,
            'kind',
            PhysiqueCheckInFailure.consentRequired,
          ),
        ),
      );
      expect(backend.calls, 0);
      expect(await checkInRows(), isEmpty);
      expect(s.file.existsSync(), isTrue);
    });

    test('no loadable baseline returns invalidInput', () async {
      final s = await staged();
      final outcome = await complete(s);
      final unavailable = outcome as CheckInAiUnavailable;
      expect(unavailable.failure, PhysiqueCheckInFailure.invalidInput);
      expect(
        unavailable.message,
        'Add a baseline photo so Herculex AI has something to compare with.',
      );
      expect(backend.calls, 0);
      expect(await checkInRows(), isEmpty);
    });

    test('a missing baseline file is skipped', () async {
      final missingId = await addBaseline('front');
      await addBaseline('side');
      final row = await (db.select(
        db.physiquePhotos,
      )..where((p) => p.id.equals(missingId))).getSingle();
      (await store.resolve(row.relativePath)).deleteSync();

      await complete(await staged());
      expect(backend.lastBaselineCount, 1);
    });

    test('all baseline files missing returns invalidInput', () async {
      final id = await addBaseline('front');
      final row = await (db.select(
        db.physiquePhotos,
      )..where((p) => p.id.equals(id))).getSingle();
      (await store.resolve(row.relativePath)).deleteSync();
      final outcome = await complete(await staged());
      expect(
        (outcome as CheckInAiUnavailable).failure,
        PhysiqueCheckInFailure.invalidInput,
      );
    });
  });

  group('AI failure', () {
    test('quota failure persists nothing and keeps the staged photo', () async {
      await addBaseline('front');
      backend.error = Exception('Your credits are used up for today');
      final s = await staged();
      final outcome = await complete(s);
      expect(
        (outcome as CheckInAiUnavailable).failure,
        PhysiqueCheckInFailure.quotaExhausted,
      );
      expect(await checkInRows(), isEmpty);
      expect(s.file.existsSync(), isTrue);
    });

    test('generic failure is unavailable', () async {
      await addBaseline('front');
      backend.error = StateError('network');
      final outcome = await complete(await staged());
      expect(
        (outcome as CheckInAiUnavailable).failure,
        PhysiqueCheckInFailure.unavailable,
      );
    });

    test('a malformed response is a typed failure', () async {
      await addBaseline('front');
      backend.result = {'confidence': 'medium'};
      final outcome = await complete(await staged());
      expect(
        (outcome as CheckInAiUnavailable).failure,
        PhysiqueCheckInFailure.malformedResponse,
      );
      expect(await checkInRows(), isEmpty);
    });

    test('save without analysis finishes it and counts toward the '
        'cap', () async {
      await addBaseline('front');
      backend.error = StateError('down');
      final s = await staged();
      expect(await complete(s), isA<CheckInAiUnavailable>());

      final callsBefore = backend.calls;
      final saved = await complete(s, analyze: false, consent: false);
      final recorded = saved as CheckInRecorded;
      expect(recorded.analyzed, isFalse);
      expect(recorded.evidence, isNull);
      expect(recorded.verdict, CheckInVerdict.inconclusive);
      expect(backend.calls, callsBefore, reason: 'no service call');

      final row = (await checkInRows()).single;
      expect(row.source, 'no_analysis');
      expect(row.verdict, 'inconclusive');
      expect(row.confidence, 'unknown');
      expect(row.directionBandLow, isNull);
      expect(
        row.reason,
        "Herculex AI couldn't review this photo, so this check-in is "
        'inconclusive.',
      );

      await expectLater(
        complete(await staged(), analyze: false),
        throwsA(isA<CheckInTooSoonException>()),
      );
    });
  });

  group('rollback', () {
    test('a failed write removes the adopted file and rethrows', () async {
      final throwing = PhysiqueCheckInFlow(
        sanitizer: sanitizer,
        store: store,
        assessments: _ThrowingAssessments(db, clock),
        service: PhysiqueCheckInService(backend),
        clock: clock,
      );
      final before = storedFiles();
      await expectLater(
        complete(await staged(), analyze: false, using: throwing),
        throwsStateError,
      );
      expect(storedFiles(), before);
    });

    test('a null sync uuid is a StateError', () async {
      goal = goal.copyWith(syncUuid: const Value(null));
      await expectLater(
        complete(await staged(), analyze: false),
        throwsStateError,
      );
    });
  });

  group('saveBaseline', () {
    test('adopts, records and needs no cap or AI', () async {
      await addBaseline('front');
      await addBaseline('side');
      final rows = await assessments.baselinePhotos(goal.id);
      expect(rows.map((r) => r.pose), ['front', 'side']);
      expect(backend.calls, 0);
      expect(await checkInRows(), isEmpty);
    });

    test('the limit propagates and the adopted file is removed', () async {
      for (var i = 0; i < 3; i++) {
        await addBaseline('front');
      }
      final before = storedFiles();
      final extra = await staged();
      await expectLater(
        flow.saveBaseline(goal: goal, staged: extra, pose: 'front'),
        throwsA(isA<BaselineLimitException>()),
      );
      expect(storedFiles(), before);
    });
  });
}
