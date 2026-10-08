import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/notifications/in_app_notification_overlay.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/goal_target_provider.dart';
import 'package:herculex/features/physique/application/physique_capture_providers.dart';
import 'package:herculex/features/physique/application/physique_check_in_flow.dart';
import 'package:herculex/features/physique/application/physique_replan_flow.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_privacy_preferences.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/presentation/sheets/check_in_sheet.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/exif_jpeg_fixture.dart';
import '../../../support/fake_clock.dart';
import '../../../support/fake_face_detector.dart';

const _consentKey = 'herculex.physique.consent_version.v1';

final _goal = PhysiqueGoalData(
  id: 1,
  status: 'active',
  source: 'ai_analysis',
  targetAestheticStyle: 'Lean athletic',
  timeframeRange: '12 months',
  targetBfPercent: 12,
  startedAt: DateTime(2026, 9, 1),
  roadmapAcceptedAt: DateTime(2026, 9, 2),
);

DreamPhysiqueAnalysisResult _result() => DreamPhysiqueAnalysisResult(
  estimatedMonths: 12,
  timeframeRange: '10-14 months',
  weightChangeKg: -2.5,
  leanMuscleGainKg: 3.5,
  fatLossKg: 6,
  targetBfPercent: 12,
  currentEstimatedBf: 20,
  musclePriorities: const [],
  nutritionStrategy: 'deficit',
  trainingAdvice: 'lift',
  overallAssessment: 'ok',
  targetAestheticStyle: 'lean',
  assessmentConfidence: AssessmentConfidence.medium,
);

ReplanProposal _proposal() {
  final plan = PhysiqueRoadmapGenerator.propose(
    const PhysiqueRoadmapInput(
      weightKg: 80,
      currentBfPercent: 20,
      targetBfPercent: 12,
      plannedWeightChangeKg: -2.5,
      estimatedMonths: 12,
      ageYears: 30,
      confidence: AssessmentConfidence.medium,
      fatLossKg: 6,
      leanGainKg: 3.5,
    ),
  );
  return ReplanProposal(
    analysis: _result(),
    proposal: plan,
    phases: plan.phases,
    weightKg: 80,
    analyzedAt: DateTime(2026, 10, 1, 9),
  );
}

class _FakeCheckInFlow implements PhysiqueCheckInFlow {
  _FakeCheckInFlow(this.sanitizer);

  final PhysiquePhotoSanitizer sanitizer;

  @override
  Future<StagedPhoto> stage(
    File source, {
    required bool blurFaces,
    void Function(CheckInProgressStep step)? onProgress,
  }) => sanitizer.stage(source, blurFaces: blurFaces);

  @override
  Future<void> discardStaged(StagedPhoto staged) => sanitizer.discard(staged);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeReplan implements PhysiqueReplanFlow {
  ReplanBlockedException? blocked;
  Object? analyseFailure;
  final proposal = _proposal();
  int analysed = 0;
  int applied = 0;
  ReplanProposal? appliedProposal;

  @override
  Future<void> checkReady(PhysiqueGoalData goal, {double? weightKg}) async {
    final b = blocked;
    if (b != null) throw b;
  }

  @override
  Future<ReplanProposal> analyse({
    required PhysiqueGoalData goal,
    required StagedPhoto staged,
    required bool consentGranted,
    required double? weightKg,
    required DietPhase currentPhase,
    required int weeksInPhase,
  }) async {
    analysed++;
    final f = analyseFailure;
    if (f != null) throw f;
    return proposal;
  }

  @override
  Future<void> apply({
    required PhysiqueGoalData goal,
    required ReplanProposal proposal,
    required StagedPhoto staged,
    required String pose,
  }) async {
    applied++;
    appliedProposal = proposal;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  final replan = _FakeReplan();
  late SharedPreferences prefs;
  late File fixture;
  late PhysiquePhotoSanitizer sanitizer;
  var captureCalls = 0;

  static Future<_Harness> create(
    WidgetTester tester, {
    bool consent = true,
  }) async {
    final h = _Harness(tester);
    SharedPreferences.setMockInitialValues({
      PhysiquePrivacyPreferences.blurKey: false,
      if (consent) _consentKey: dreamPhysiqueImageConsentVersion,
    });
    final staging = Directory.systemTemp.createTempSync('urs_stage_');
    final pick = Directory.systemTemp.createTempSync('urs_pick_');
    addTearDown(() {
      for (final d in [staging, pick]) {
        try {
          if (d.existsSync()) d.deleteSync(recursive: true);
        } on FileSystemException {
          // Windows keeps the decoded fixture open until the image is GC'd.
        }
      }
    });
    h.fixture = File('${pick.path}/fixture.jpg')
      ..writeAsBytesSync(buildJpegWithExif());
    h.sanitizer = PhysiquePhotoSanitizer(
      faceDetector: FakeFaceDetector(),
      stagingDirectory: () async => staging,
    );
    await tester.runAsync(() async {
      h.prefs = await SharedPreferences.getInstance();
    });
    return h;
  }

  Future<XFile?> capture(ImageSource source) async {
    captureCalls++;
    return XFile(fixture.path);
  }

  Widget host() {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(FakeClock(DateTime(2026, 10, 1, 9))),
        weightFormatProvider.overrideWithValue(
          const WeightFormat(MeasurementUnit.metric),
        ),
        physiqueCheckInFlowProvider.overrideWithValue(
          _FakeCheckInFlow(sanitizer),
        ),
        physiqueReplanFlowProvider.overrideWithValue(replan),
        physiqueCheckInContextProvider(_goal.id).overrideWith(
          (ref) => const CheckInFlowContext(
            phase: DietPhase.cut,
            weeksInPhase: 3,
            weightKg: 80,
          ),
        ),
        goalTargetProvider.overrideWithValue(
          const GoalTarget(
            source: GoalTargetSource.roadmap,
            targetKg: 76,
            dreamKg: 76,
            phase: DietPhase.cut,
            goalId: 1,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => InAppNotificationHost(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => CheckInSheet.show(
                  context,
                  goal: _goal,
                  updateRoadmap: true,
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

  Future<void> open() async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Lets real isolates and file IO finish between pumps.
  Future<void> settle({required Finder until}) async {
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (until.evaluate().isNotEmpty) return;
    }
    fail('never found $until');
  }

  Future<void> takePhotoAndContinue() async {
    await tester.tap(find.text('Take photo'));
    await tester.pump();
    await settle(until: find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump();
  }
}

void main() {
  testWidgets('opens as Update roadmap with the usual first step', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    await h.open();
    expect(find.text('Update roadmap'), findsOneWidget);
    expect(find.text('Add check-in'), findsNothing);
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
  });

  group('blocked before a photo is taken', () {
    testWidgets('missing dream photo offers to add one', (tester) async {
      final h = await _Harness.create(tester);
      h.replan.blocked = const ReplanBlockedException(ReplanBlock.noDreamPhoto);
      await h.open();
      expect(
        find.textContaining('Add your dream physique photo first'),
        findsOneWidget,
      );
      expect(find.text('Choose dream photo'), findsOneWidget);
      expect(find.text('Take photo'), findsNothing);
      expect(find.textContaining('Step 1'), findsNothing);
    });

    testWidgets('too soon names the day it opens again', (tester) async {
      final h = await _Harness.create(tester);
      h.replan.blocked = ReplanBlockedException(
        ReplanBlock.tooSoon,
        nextEligibleDate: DateTime(2026, 10, 12),
      );
      await h.open();
      expect(find.textContaining('available Mon, Oct 12'), findsOneWidget);
      expect(find.text('Take photo'), findsNothing);
      expect(find.text('Choose dream photo'), findsNothing);
    });

    testWidgets('missing weight asks for one', (tester) async {
      final h = await _Harness.create(tester);
      h.replan.blocked = const ReplanBlockedException(ReplanBlock.noWeight);
      await h.open();
      expect(find.textContaining('Log your current weight'), findsOneWidget);
    });
  });

  testWidgets('consent step says what is compared and has no photo-only '
      'shortcut', (tester) async {
    final h = await _Harness.create(tester, consent: false);
    await h.open();
    await h.takePhotoAndContinue();
    await h.settle(until: find.text('Update my roadmap'));
    expect(find.textContaining('dream physique photo'), findsOneWidget);
    expect(find.text('Save photo without analysis'), findsNothing);
    expect(h.replan.analysed, 0);
  });

  testWidgets('photo, analysis, review, then Use this roadmap stores it', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    await h.open();
    await h.takePhotoAndContinue();
    await h.settle(until: find.text('Your new roadmap'));

    expect(h.replan.analysed, 1);
    expect(h.replan.applied, 0, reason: 'nothing is stored before the tap');
    expect(find.text('Step 4 of 4'), findsOneWidget);
    expect(find.text('Body fat now about 20%, target 12%.'), findsOneWidget);
    expect(
      find.text('About 12 months to your dream physique.'),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('replan-dream-weight'))).data,
      'Dream weight 78.2 kg (was 76 kg)',
    );
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('80 → 74 kg'), findsOneWidget);
    expect(find.text('Use this roadmap'), findsOneWidget);
    expect(find.text('Keep my current roadmap'), findsOneWidget);

    await tester.tap(find.byKey(const Key('replan-use')));
    await tester.pump();
    await h.settle(
      until: find.text('Roadmap updated. Your target is now 74 kg.'),
    );

    expect(h.replan.applied, 1);
    expect(h.replan.appliedProposal, same(h.replan.proposal));
    expect(find.text('Use this roadmap'), findsNothing, reason: 'sheet closed');
  });

  testWidgets('Keep my current roadmap closes without storing anything', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    await h.open();
    await h.takePhotoAndContinue();
    await h.settle(until: find.text('Your new roadmap'));

    await tester.tap(find.byKey(const Key('replan-keep')));
    await tester.pumpAndSettle();
    expect(find.text('Your new roadmap'), findsNothing);
    expect(h.replan.applied, 0);
  });

  testWidgets('an AI failure says so and offers Try again, not a photo-only '
      'save', (tester) async {
    final h = await _Harness.create(tester);
    h.replan.analyseFailure = const DreamPhysiqueAnalysisException(
      'Server unreachable',
    );
    await h.open();
    await h.takePhotoAndContinue();
    await h.settle(until: find.text('Server unreachable'));

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Save without analysis'), findsNothing);

    // The staged photo is still there, so trying again re-runs the analysis.
    h.replan.analyseFailure = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await h.settle(until: find.text('Your new roadmap'));
    expect(h.replan.analysed, 2);
  });
}
