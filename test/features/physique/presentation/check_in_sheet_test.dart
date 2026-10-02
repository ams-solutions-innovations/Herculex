import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_capture_providers.dart';
import 'package:herculex/features/physique/application/physique_check_in_flow.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_assessment_repository.dart';
import 'package:herculex/features/physique/data/physique_checkin_service.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/presentation/sheets/check_in_sheet.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';
import 'package:herculex/services/ai/pending_ai_scan_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/exif_jpeg_fixture.dart';
import '../../../support/fake_clock.dart';
import '../../../support/fake_face_detector.dart';
import '../../../support/test_database.dart';

class _FakeBackend implements PhysiqueCheckInBackend {
  Object? error;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<(Map<String, dynamic>, Map<String, dynamic>)> analyzePhysiqueCheckIn({
    required List<Map<String, dynamic>> baselineImages,
    required Map<String, dynamic> currentImage,
    required Map<String, dynamic> context,
    String? userNote,
  }) async {
    calls++;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return (
      {
        'directionBand': {'low': 0.3, 'high': 0.6},
        'confidence': 'medium',
        'reason': 'Visible progress in the shoulders.',
        'limitations': ['lighting'],
      },
      {'modelVersion': 'm1', 'knowledgeVersion': 'k1'},
    );
  }
}

const _consentKey = 'herculex.physique.consent_version.v1';

class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  late AppDatabase db;
  late FakeClock clock;
  late SharedPreferences prefs;
  late PhysiqueGoalData goal;
  late PhysiqueAssessmentRepository assessments;
  late PhysiqueCheckInFlow flow;
  late List<PhysiquePhotoData> photos;
  final backend = _FakeBackend();
  late File fixture;
  final captured = <PendingAiScanContext?>[];
  var captureCalls = 0;
  var returnNull = false;

  Future<XFile?> capture(ImageSource source) async {
    captureCalls++;
    // Raw read: the service would drop it as expired against the real clock.
    final raw = prefs.getString('herculex_pending_ai_scan_context');
    captured.add(
      raw == null
          ? null
          : PendingAiScanContext.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
            ),
    );
    return returnNull ? null : XFile(fixture.path);
  }

  static Future<_Harness> create(
    WidgetTester tester, {
    bool baseline = true,
    bool consent = false,
    FakeFaceDetector? detector,
  }) async {
    final h = _Harness(tester);
    SharedPreferences.setMockInitialValues({
      if (consent) _consentKey: dreamPhysiqueImageConsentVersion,
    });
    final docs = Directory.systemTemp.createTempSync('cis_docs_');
    final staging = Directory.systemTemp.createTempSync('cis_stage_');
    final pick = Directory.systemTemp.createTempSync('cis_pick_');
    addTearDown(() {
      for (final d in [docs, staging, pick]) {
        try {
          if (d.existsSync()) d.deleteSync(recursive: true);
        } on FileSystemException {
          // Windows keeps the decoded fixture open until the image is GC'd.
        }
      }
    });
    h.fixture = File('${pick.path}/fixture.jpg')
      ..writeAsBytesSync(buildJpegWithExif());
    h.clock = FakeClock(DateTime(2026, 10, 1, 9));
    await tester.runAsync(() async {
      h.prefs = await SharedPreferences.getInstance();
      h.db = await openTestDatabase();
      h.assessments = PhysiqueAssessmentRepository(h.db, h.clock);
      final goals = PhysiqueGoalRepository(h.db, h.clock);
      final id = await goals.startGoal(
        StartGoalInput(
          goalSyncUuid: 'goal-uuid-1',
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
      h.goal = (await goals.getGoal(id))!;
      h.flow = PhysiqueCheckInFlow(
        sanitizer: PhysiquePhotoSanitizer(
          faceDetector: detector ?? FakeFaceDetector(),
          stagingDirectory: () async => staging,
        ),
        store: PhysiquePhotoStore(documentsDirectory: () async => docs),
        assessments: h.assessments,
        service: PhysiqueCheckInService(h.backend),
        clock: h.clock,
      );
      if (baseline) {
        await h.flow.saveBaseline(
          goal: h.goal,
          staged: await h.flow.stage(h.fixture, blurFaces: false),
          pose: 'front',
        );
      }
      h.photos = await h.assessments.baselinePhotos(h.goal.id);
    });
    addTearDown(() => h.db.close());
    return h;
  }

  Widget host({
    ThemeData? theme,
    ResumedCapture? resumed,
    double textScale = 1,
  }) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(clock),
        physiqueCheckInFlowProvider.overrideWithValue(flow),
        physiquePhotosProvider(
          goal.id,
        ).overrideWith((ref) => Stream.value(photos)),
        physiqueCheckInContextProvider(goal.id).overrideWith(
          (ref) => const CheckInFlowContext(
            phase: DietPhase.cut,
            weeksInPhase: 2,
            weightKg: 82,
            weeklyTrendKg: -0.4,
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => CheckInSheet.show(
                  context,
                  goal: goal,
                  resumed: resumed,
                  capture: capture,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(Widget host, {Size size = const Size(400, 1600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Lets real isolates and file IO finish between pumps.
  Future<void> settle({Finder? until}) async {
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (until != null && until.evaluate().isNotEmpty) return;
    }
    if (until != null) fail('never found $until');
  }

  Future<void> tapText(String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
  }

  Future<List<PhysiqueAssessmentData>> checkIns() async =>
      (await tester.runAsync(
        () => (db.select(
          db.physiqueAssessments,
        )..where((a) => a.kind.equals('checkin'))).get(),
      ))!;

  Future<List<PhysiquePhotoData>> checkInPhotos() async =>
      (await tester.runAsync(
        () => (db.select(
          db.physiquePhotos,
        )..where((p) => p.role.equals('checkin'))).get(),
      ))!;
}

void main() {
  testWidgets('step 1 shows poses and the two capture buttons', (tester) async {
    final h = await _Harness.create(tester);
    await h.open(h.host());

    expect(find.text('Add check-in'), findsOneWidget);
    expect(find.text('Step 1 of 4'), findsOneWidget);
    for (final p in ['Front', 'Side', 'Back']) {
      expect(find.text(p), findsOneWidget);
    }
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from library'), findsOneWidget);
  });

  testWidgets('capture sets the pending context first, clears it, then goes '
      'to the privacy step', (tester) async {
    final h = await _Harness.create(tester);
    await h.open(h.host());

    await h.tapText('Side');
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));

    final ctx = h.captured.single!;
    expect(ctx.type, AiScanContextType.physiqueCheckin);
    expect(ctx.extra, {'goalId': h.goal.id, 'pose': 'side'});
    expect(ctx.createdAt, h.clock.now());
    expect(PendingAiScanService(h.prefs).getPendingContext(), isNull);

    expect(find.text('Step 2 of 4'), findsOneWidget);
    expect(
      find.text('Location and camera details are removed from every photo.'),
      findsOneWidget,
    );
    expect(
      find.text('Happens on your device. The original face is never saved.'),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('a cancelled pick stays on step 1', (tester) async {
    final h = await _Harness.create(tester)
      ..returnNull = true;
    await h.open(h.host());

    await h.tapText('Choose from library');
    await h.settle();

    expect(h.captureCalls, 1);
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('Blur my face'), findsNothing);
    expect(PendingAiScanService(h.prefs).getPendingContext(), isNull);
  });

  testWidgets('a resumed capture opens at the privacy step', (tester) async {
    final h = await _Harness.create(tester);
    await h.open(
      h.host(
        resumed: ResumedCapture(
          goalId: h.goal.id,
          pose: 'back',
          path: h.fixture.path,
        ),
      ),
    );

    expect(find.text('Step 2 of 4'), findsOneWidget);
    expect(find.text('Blur my face'), findsOneWidget);
    expect(h.captureCalls, 0);
  });

  testWidgets('baseline mode saves the photo without cap, AI or consent', (
    tester,
  ) async {
    final h = await _Harness.create(tester, baseline: false);
    await h.open(h.host());

    expect(find.text('Add baseline photo'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));
    expect(find.text('Step 2 of 2'), findsOneWidget);

    await h.tapText('Continue');
    await h.settle(until: find.text('Baseline photo saved.'));

    expect(find.text('Blur my face'), findsNothing);
    expect(h.backend.calls, 0);
    final rows = await h.tester.runAsync(
      () => h.assessments.baselinePhotos(h.goal.id),
    );
    expect(rows, hasLength(1));
  });

  testWidgets('no face found: retake returns to step 1 and discards', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    await h.open(h.host());
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await h.tapText('Continue');
    await h.settle(until: find.text('No face found'));

    expect(find.text('Retake photo'), findsOneWidget);
    await h.tapText('Retake photo');
    await h.settle(until: find.text('Step 1 of 4'));
    expect(find.text('Take photo'), findsOneWidget);
    expect(h.prefs.getBool('herculex.physique.blur_faces.v1'), isTrue);
    expect(await h.checkIns(), isEmpty);
  });

  testWidgets('no face found: save without blur never records it as blurred', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    await h.open(h.host());
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await h.tapText('Continue');
    await h.settle(until: find.text('No face found'));

    await h.tapText('Save without blur');
    await h.settle(until: find.text('Analyze my progress'));
    await h.tapText('Save photo without analysis');
    await h.settle(until: find.text('Done'));

    final photos = await h.checkInPhotos();
    expect(photos, hasLength(1));
    expect(photos.single.blurred, isFalse);
    expect(find.textContaining('blurred'), findsNothing);
  });

  testWidgets('consent not yet accepted: step 3, accept then analyse', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    await h.open(h.host());
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));
    await h.tapText('Continue');
    await h.settle(until: find.text('Analyze my progress'));

    expect(find.text('Step 3 of 4'), findsOneWidget);
    expect(
      find.text(
        'Your photos stay on this device. Herculex AI looks at them once to '
        "compare your progress, and Herculex doesn't keep a copy.",
      ),
      findsOneWidget,
    );
    expect(h.backend.calls, 0);
    expect(h.prefs.getString(_consentKey), isNull);

    await h.tapText('Analyze my progress');
    await h.settle(until: find.text('Done'));

    expect(h.prefs.getString(_consentKey), dreamPhysiqueImageConsentVersion);
    expect(h.backend.calls, 1);
    expect(find.text('Step 4 of 4'), findsOneWidget);
    expect(find.text('Visible progress in the shoulders.'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    final rows = await h.checkIns();
    expect(rows, hasLength(1));
    expect(rows.single.source, 'ai');

    await h.tapText('Done');
    await tester.pumpAndSettle();
    expect(find.text('Add check-in'), findsNothing);
  });

  testWidgets('consent already accepted skips step 3', (tester) async {
    final h = await _Harness.create(tester, consent: true);
    await h.open(h.host());
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));
    await h.tapText('Continue');
    await h.settle(until: find.text('Done'));

    expect(find.text('Analyze my progress'), findsNothing);
    expect(h.backend.calls, 1);
    expect(await h.checkIns(), hasLength(1));
  });

  testWidgets('save without analysis never uploads and stores no verdict', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    await h.open(h.host());
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));
    await h.tapText('Continue');
    await h.settle(until: find.text('Analyze my progress'));
    await h.tapText('Save photo without analysis');
    await h.settle(until: find.text('Done'));

    expect(h.backend.calls, 0);
    expect(
      find.text(
        "Herculex AI couldn't review this photo, so this check-in is "
        'inconclusive.',
      ),
      findsOneWidget,
    );
    expect((await h.checkIns()).single.source, 'no_analysis');
  });

  testWidgets('AI unavailable: error copy, then save without analysis', (
    tester,
  ) async {
    final h = await _Harness.create(tester, consent: true);
    h.backend.error = Exception('network down');
    await h.open(h.host());
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));
    await h.tapText('Continue');
    await h.settle(until: find.text('Save without analysis'));

    expect(find.textContaining("isn't available right now"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(await h.checkIns(), isEmpty);

    await h.tapText('Save without analysis');
    await h.settle(until: find.text('Done'));
    expect((await h.checkIns()).single.source, 'no_analysis');
  });

  testWidgets('quota exhausted shows its copy and no Try again', (
    tester,
  ) async {
    final h = await _Harness.create(tester, consent: true);
    h.backend.error = Exception('Daily checks are used up');
    await h.open(h.host());
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));
    await h.tapText('Continue');
    await h.settle(until: find.text('Save without analysis'));

    expect(
      find.text(
        "You've used today's Herculex AI check-ins. Try again tomorrow, or "
        'save your photo without analysis.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('cap race closes the sheet and shows the next date', (
    tester,
  ) async {
    final h = await _Harness.create(tester, consent: true);
    await tester.runAsync(
      () => h.assessments.recordCheckIn(
        CheckInRecord(
          goalId: h.goal.id,
          pose: 'front',
          relativePath: 'physique/x.jpg',
        ),
      ),
    );
    await h.open(h.host());
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));
    await h.tapText('Continue');
    await h.settle(until: find.textContaining("You've already checked in"));

    expect(
      find.text(
        "You've already checked in this week. Your next check-in is "
        'available Thu, Oct 8.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CheckInSheet), findsNothing);
    expect(await h.checkIns(), hasLength(1));
    expect(h.backend.calls, 0);
  });

  testWidgets('the sheet cannot be dismissed mid-analysis', (tester) async {
    final h = await _Harness.create(tester, consent: true);
    h.backend.gate = Completer<void>();
    await h.open(h.host());
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));
    await h.tapText('Continue');
    await h.settle(until: find.text('Comparing with your baseline...'));

    final nav = Navigator.of(tester.element(find.byType(CheckInSheet)));
    await tester.runAsync(nav.maybePop);
    await tester.pump();
    expect(find.text('Hang on, almost done'), findsOneWidget);
    expect(find.byType(CheckInSheet), findsOneWidget);

    h.backend.gate!.complete();
    await h.settle(until: find.text('Done'));
    expect(await h.checkIns(), hasLength(1));
  });

  testWidgets('320 dp at 2.0 text scale does not overflow', (tester) async {
    final h = await _Harness.create(tester);
    await h.open(h.host(textScale: 2), size: const Size(320, 700));
    expect(tester.takeException(), isNull);
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme smoke', (tester) async {
    final h = await _Harness.create(tester);
    await h.open(h.host(theme: AppTheme.darkTheme));
    expect(find.text('Take photo'), findsOneWidget);
    await h.tapText('Take photo');
    await h.settle(until: find.text('Blur my face'));
    expect(tester.takeException(), isNull);
  });
}
