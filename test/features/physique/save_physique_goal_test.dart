import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/physique/application/physique_goal_starter.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/presentation/save_physique_goal.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStarter implements PhysiqueGoalStarter {
  _FakeStarter(this.prefsSetter, {required this.noFace, this.fail = false});

  final Future<void> Function(bool) prefsSetter;
  final bool noFace;
  final bool fail;

  bool? stagedBlur;
  int stageCalls = 0;
  List<StagedPhoto>? discarded;
  List<StagedPhoto>? persisted;
  int startCalls = 0;

  @override
  Future<List<StagedPhoto>> stagePhotos({
    required List<File> files,
    required bool blurFaces,
  }) async {
    stageCalls++;
    stagedBlur = blurFaces;
    await prefsSetter(blurFaces);
    return [
      for (final f in files)
        StagedPhoto(
          file: f,
          width: 10,
          height: 10,
          blurRequested: blurFaces,
          facesFound: noFace ? 0 : 1,
          blurApplied: blurFaces && !noFace,
        ),
    ];
  }

  @override
  Future<void> discardStaged(List<StagedPhoto> staged) async {
    discarded = staged;
  }

  @override
  Future<int> startFromAnalysis({
    required DreamPhysiqueAnalysisResult result,
    required List<StagedPhoto> staged,
    required int targetPhotoCount,
  }) async {
    startCalls++;
    if (fail) throw StateError('disk full');
    persisted = staged;
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _result = DreamPhysiqueAnalysisResult(
  estimatedMonths: 6,
  timeframeRange: '6 months',
  weightChangeKg: -3,
  leanMuscleGainKg: 1,
  fatLossKg: 4,
  targetBfPercent: 12,
  currentEstimatedBf: 18,
  musclePriorities: [],
  nutritionStrategy: '',
  trainingAdvice: '',
  overallAssessment: '',
  targetAestheticStyle: 'Athletic',
);

PhysiqueGoalData _goal() => PhysiqueGoalData(
  id: 1,
  status: 'active',
  source: 'ai_analysis',
  targetAestheticStyle: 'Athletic',
  timeframeRange: '',
  startedAt: DateTime(2026, 9, 1),
);

void main() {
  late SharedPreferences prefs;
  bool? outcome;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    outcome = null;
  });

  Future<_FakeStarter> run(
    WidgetTester tester, {
    PhysiqueGoalData? active,
    bool noFace = false,
    bool fail = false,
    bool startBlur = false,
  }) async {
    if (startBlur) await prefs.setBool('herculex.physique.blur_faces.v1', true);
    final starter = _FakeStarter(
      (v) => prefs.setBool('herculex.physique.blur_faces.v1', v),
      noFace: noFace,
      fail: fail,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          physiqueGoalStarterProvider.overrideWithValue(starter),
          activePhysiqueGoalProvider.overrideWith(
            (ref) => Stream.value(active),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () async {
                  outcome = await savePhysiqueGoal(
                    context,
                    ref,
                    result: _result,
                    currentPhotos: [File('a.jpg'), File('b.jpg')],
                    targetPhotoCount: 1,
                  );
                },
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    return starter;
  }

  testWidgets('no active goal: privacy dialog then creates the goal', (
    tester,
  ) async {
    final starter = await run(tester);
    expect(find.text('Start a new goal?'), findsNothing);
    expect(find.text('Photo privacy'), findsOneWidget);
    expect(find.text('Blur my face'), findsOneWidget);
    expect(
      find.text('Location and camera details are removed from every photo.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(outcome, isTrue);
    expect(starter.startCalls, 1);
    expect(starter.stagedBlur, isFalse);
  });

  testWidgets('active goal: confirmation first, cancel creates nothing', (
    tester,
  ) async {
    final starter = await run(tester, active: _goal());
    expect(find.text('Start a new goal?'), findsOneWidget);
    expect(find.text('Photo privacy'), findsNothing);

    await tester.tap(find.text('Keep current goal'));
    await tester.pumpAndSettle();
    expect(outcome, isFalse);
    expect(starter.stageCalls, 0);
    expect(starter.startCalls, 0);
  });

  testWidgets('active goal: confirm continues to the privacy dialog', (
    tester,
  ) async {
    final starter = await run(tester, active: _goal());
    await tester.tap(find.text('Start new goal'));
    await tester.pumpAndSettle();
    expect(find.text('Photo privacy'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(outcome, isTrue);
    expect(starter.startCalls, 1);
  });

  testWidgets('privacy dialog cancel stages and stores nothing', (
    tester,
  ) async {
    final starter = await run(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(outcome, isFalse);
    expect(starter.stageCalls, 0);
    expect(starter.startCalls, 0);
  });

  testWidgets('the toggle defaults to the stored choice and is persisted', (
    tester,
  ) async {
    final starter = await run(tester, startBlur: true);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(starter.stagedBlur, isFalse);
    expect(prefs.getBool('herculex.physique.blur_faces.v1'), isFalse);
    expect(outcome, isTrue);
  });

  testWidgets('blur on with no face: Retake discards and creates nothing', (
    tester,
  ) async {
    final starter = await run(tester, startBlur: true, noFace: true);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('No face found'), findsOneWidget);

    await tester.tap(find.text('Retake photo'));
    await tester.pumpAndSettle();
    expect(outcome, isFalse);
    expect(starter.discarded, hasLength(2));
    expect(starter.startCalls, 0);
  });

  testWidgets('blur on with no face: Save without blur keeps unblurred', (
    tester,
  ) async {
    final starter = await run(tester, startBlur: true, noFace: true);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save without blur'));
    await tester.pumpAndSettle();
    expect(outcome, isTrue);
    expect(starter.discarded, isNull);
    expect(starter.persisted!.every((s) => !s.blurApplied), isTrue);
  });

  testWidgets('blur off never shows the no-face dialog', (tester) async {
    final starter = await run(tester, noFace: true);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('No face found'), findsNothing);
    expect(outcome, isTrue);
    expect(starter.startCalls, 1);
  });

  testWidgets('blur on with faces found shows no extra dialog', (tester) async {
    final starter = await run(tester, startBlur: true);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('No face found'), findsNothing);
    expect(outcome, isTrue);
    expect(starter.persisted!.every((s) => s.blurApplied), isTrue);
  });

  testWidgets('a starter failure returns false, discards, never throws', (
    tester,
  ) async {
    final starter = await run(tester, fail: true);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(outcome, isFalse);
    expect(starter.discarded, hasLength(2));
  });
}
