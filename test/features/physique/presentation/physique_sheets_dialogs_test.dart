import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_assessment_repository.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/presentation/dialogs/delete_check_in_dialog.dart';
import 'package:herculex/features/physique/presentation/dialogs/discard_changes_dialog.dart';
import 'package:herculex/features/physique/presentation/dialogs/no_face_found_dialog.dart';
import 'package:herculex/features/physique/presentation/dialogs/reset_roadmap_dialog.dart';
import 'package:herculex/features/physique/presentation/dialogs/start_new_goal_dialog.dart';
import 'package:herculex/features/physique/presentation/sheets/check_in_history_sheet.dart';
import 'package:herculex/features/physique/presentation/sheets/past_goals_sheet.dart';
import 'package:herculex/features/physique/presentation/widgets/photo_thumbnail.dart';

import '../../../support/fake_clock.dart';
import '../../../support/test_database.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

PhysiqueAssessmentData _assessment(
  int id, {
  required DateTime at,
  String verdict = 'on_track',
  String? reason,
  double? low = 0.2,
  double? high = 0.6,
}) => PhysiqueAssessmentData(
  id: id,
  goalId: 1,
  kind: 'checkin',
  assessedAt: at,
  dateIso: '2026-10-01',
  confidence: 'medium',
  verdict: verdict,
  directionBandLow: low,
  directionBandHigh: high,
  reason: reason,
  source: 'ai',
);

PhysiquePhotoData _photo(int id, int assessmentId, String path) =>
    PhysiquePhotoData(
      id: id,
      goalId: 1,
      assessmentId: assessmentId,
      role: 'checkin',
      pose: 'front',
      dateIso: '2026-10-01',
      takenAt: DateTime(2026, 10, 1),
      relativePath: path,
      blurred: false,
      source: 'capture',
    );

PhysiqueGoalData _goal({
  int id = 1,
  String status = 'active',
  String style = 'Lean athletic',
  double? targetBf = 12,
  DateTime? archivedAt,
}) => PhysiqueGoalData(
  id: id,
  status: status,
  source: style.isEmpty ? 'legacy_import' : 'ai_analysis',
  targetAestheticStyle: style,
  timeframeRange: '',
  targetBfPercent: targetBf,
  startedAt: DateTime(2026, 3, 1),
  archivedAt: archivedAt,
);

Widget _app(ThemeData theme, List<Override> overrides, Widget home) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: home),
      ),
      GoRoute(
        path: '/dream-physique/progress',
        builder: (_, state) => Scaffold(
          body: Text('Progress:${state.uri.queryParameters['goalId']}'),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(theme: theme, routerConfig: router),
  );
}

Widget _opener(void Function(BuildContext) open) => Builder(
  builder: (context) => Center(
    child: TextButton(
      onPressed: () => open(context),
      child: const Text('open'),
    ),
  ),
);

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settleIo(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  for (final t in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    final theme = t.$2;
    final name = t.$1;

    group('PhotoThumbnail ($name)', () {
      late Directory docs;

      setUp(() {
        docs = Directory.systemTemp.createTempSync('physique_thumb');
        addTearDown(() => docs.deleteSync(recursive: true));
      });

      Widget host(String path) => _app(theme, [
        physiquePhotoStoreProvider.overrideWithValue(
          PhysiquePhotoStore(documentsDirectory: () async => docs),
        ),
      ], Center(child: PhotoThumbnail(relativePath: path)));

      testWidgets('shows the image for an existing file', (tester) async {
        final file = File('${docs.path}/physique/g1/a.jpg')
          ..createSync(recursive: true)
          ..writeAsBytesSync(_png);
        expect(file.existsSync(), isTrue);
        await tester.pumpWidget(host('physique/g1/a.jpg'));
        await _settleIo(tester);
        expect(find.byType(Image), findsOneWidget);
        expect(find.text('Photo unavailable'), findsNothing);
      });

      testWidgets('shows the placeholder for a missing file', (tester) async {
        await tester.pumpWidget(host('physique/g1/missing.jpg'));
        await _settleIo(tester);
        expect(find.text('Photo unavailable'), findsOneWidget);
        expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a traversal path shows the placeholder, never throws', (
        tester,
      ) async {
        await tester.pumpWidget(host('physique/../../secret.jpg'));
        await _settleIo(tester);
        expect(find.text('Photo unavailable'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an empty path shows the placeholder', (tester) async {
        await tester.pumpWidget(host(''));
        await tester.pump();
        expect(find.text('Photo unavailable'), findsOneWidget);
      });
    });

    group('CheckInHistorySheet ($name)', () {
      List<Override> overrides({
        List<PhysiqueAssessmentData> checkIns = const [],
        List<PhysiquePhotoData> photos = const [],
        PhysiqueGoalData? goal,
      }) => [
        physiqueCheckInsProvider(
          1,
        ).overrideWith((ref) => Stream.value(checkIns)),
        physiquePhotosProvider(1).overrideWith((ref) => Stream.value(photos)),
        physiqueGoalProvider(
          1,
        ).overrideWith((ref) => Stream.value(goal ?? _goal())),
        physiquePhotoStoreProvider.overrideWithValue(
          PhysiquePhotoStore(
            documentsDirectory: () async => Directory.systemTemp,
          ),
        ),
      ];

      Future<void> open(WidgetTester tester, List<Override> o) async {
        _bigView(tester);
        await tester.pumpWidget(
          _app(
            theme,
            o,
            _opener((c) => CheckInHistorySheet.show(c, goalId: 1)),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      testWidgets('empty state', (tester) async {
        await open(tester, overrides());
        expect(find.text('No check-ins yet'), findsOneWidget);
        expect(
          find.text(
            'Take your first photo to set a baseline. You can check in once a '
            'week.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('lists newest first with verdict chip and one reason line', (
        tester,
      ) async {
        await open(
          tester,
          overrides(
            // The repository stream already orders newest first.
            checkIns: [
              _assessment(
                2,
                at: DateTime(2026, 10, 12),
                verdict: 'off_track',
                reason: 'Newer reason',
              ),
              _assessment(1, at: DateTime(2026, 10, 5), reason: 'Older reason'),
            ],
            photos: [_photo(1, 1, 'physique/g/1.jpg'), _photo(2, 2, '')],
          ),
        );
        expect(find.text('Mon, Oct 12'), findsOneWidget);
        expect(find.text('Mon, Oct 5'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Mon, Oct 12')).dy <
              tester.getTopLeft(find.text('Mon, Oct 5')).dy,
          isTrue,
        );
        expect(find.text('Off track'), findsOneWidget);
        expect(find.text('On track'), findsOneWidget);
        expect(find.text('Newer reason'), findsOneWidget);
        // Missing photos never hide the row.
        expect(find.text('Photo unavailable'), findsWidgets);
      });

      testWidgets('detail shows verdict block, delete only when active', (
        tester,
      ) async {
        final row = _assessment(
          1,
          at: DateTime(2026, 10, 5),
          reason: 'Visible progress.',
        );
        await open(tester, overrides(checkIns: [row]));
        await tester.tap(find.text('Mon, Oct 5'));
        await tester.pumpAndSettle();
        expect(find.text('Visible progress.'), findsOneWidget);
        expect(find.text('Confidence: Medium'), findsOneWidget);
        expect(find.text('Delete check-in'), findsOneWidget);
        await tester.tap(find.text('All check-ins'));
        await tester.pumpAndSettle();
        expect(find.text('Mon, Oct 5'), findsOneWidget);
      });

      testWidgets('an archived goal hides the delete action', (tester) async {
        await open(
          tester,
          overrides(
            checkIns: [_assessment(1, at: DateTime(2026, 10, 5))],
            goal: _goal(status: 'archived', archivedAt: DateTime(2026, 9, 1)),
          ),
        );
        await tester.tap(find.text('Mon, Oct 5'));
        await tester.pumpAndSettle();
        expect(find.text('Delete check-in'), findsNothing);
      });

      testWidgets(
        'delete confirm removes row and file; cap date is unchanged',
        (tester) async {
          _bigView(tester);
          final docs = Directory.systemTemp.createTempSync('physique_del');
          addTearDown(() => docs.deleteSync(recursive: true));
          late AppDatabase db;
          late int goalId;
          addTearDown(() => db.close());
          late String relative;
          final clock = FakeClock(DateTime(2026, 10, 12, 9));
          await tester.runAsync(() async {
            db = await openTestDatabase();
            final goals = PhysiqueGoalRepository(db, clock);
            goalId = await goals.startGoal(
              StartGoalInput(
                targetAestheticStyle: 'Lean',
                estimatedMonths: 6,
                targetBfPercent: 12,
                analyses: [
                  AnalysisInput(
                    analyzedAt: DateTime(2026, 10, 1),
                    currentBfPercent: 20,
                    confidence: AssessmentConfidence.medium,
                  ),
                ],
              ),
            );
            relative = 'physique/g1/c.jpg';
            File('${docs.path}/$relative')
              ..createSync(recursive: true)
              ..writeAsBytesSync(_png);
            await PhysiqueAssessmentRepository(db, clock).recordCheckIn(
              CheckInRecord(
                goalId: goalId,
                pose: 'front',
                relativePath: relative,
                verdict: CheckInVerdict.onTrack,
                confidence: AssessmentConfidence.medium,
                reason: 'Visible progress.',
              ),
            );
          });
          final file = File('${docs.path}/$relative');
          expect(file.existsSync(), isTrue);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(db),
                clockProvider.overrideWithValue(clock),
                physiquePhotoStoreProvider.overrideWithValue(
                  PhysiquePhotoStore(documentsDirectory: () async => docs),
                ),
              ],
              child: MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: _opener(
                    (c) => CheckInHistorySheet.show(c, goalId: goalId),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();
          expect(find.text('Mon, Oct 12'), findsOneWidget);

          final container = ProviderScope.containerOf(
            tester.element(find.byType(CheckInHistorySheet)),
          );
          final before = await tester.runAsync(
            () => container.read(physiqueLastCheckInAtProvider(goalId).future),
          );
          expect(before, isNotNull);

          await tester.tap(find.text('Mon, Oct 12'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete check-in'));
          await tester.pumpAndSettle();
          expect(find.text('Delete this check-in?'), findsOneWidget);

          // Cancel keeps everything.
          await tester.tap(find.text('Keep check-in'));
          await tester.pumpAndSettle();
          expect(file.existsSync(), isTrue);
          expect(find.text('Delete check-in'), findsOneWidget);

          await tester.tap(find.text('Delete check-in'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Delete check-in'),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          await tester.pumpAndSettle();
          expect(file.existsSync(), isFalse);
          expect(find.text('Mon, Oct 12'), findsNothing);
          expect(find.text('No check-ins yet'), findsOneWidget);
          final after = await tester.runAsync(
            () => container.read(physiqueLastCheckInAtProvider(goalId).future),
          );
          expect(after, before);

          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });

    group('PastGoalsSheet ($name)', () {
      List<Override> overrides(List<PhysiqueGoalData> goals) => [
        archivedPhysiqueGoalsProvider.overrideWith(
          (ref) => Stream.value(goals),
        ),
      ];

      testWidgets('legacy goal renders without null or empty artefacts', (
        tester,
      ) async {
        _bigView(tester);
        await tester.pumpWidget(
          _app(
            theme,
            overrides([
              _goal(
                id: 2,
                style: '',
                targetBf: null,
                status: 'archived',
                archivedAt: DateTime(2026, 9, 1),
              ),
              _goal(
                id: 3,
                style: 'Lean athletic',
                targetBf: 12,
                status: 'archived',
                archivedAt: DateTime(2026, 8, 1),
              ),
            ]),
            _opener(PastGoalsSheet.show),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Imported progress photos'), findsOneWidget);
        expect(find.text('Lean athletic'), findsOneWidget);
        expect(find.text('Target 12% body fat'), findsOneWidget);
        // Exactly one Target line: the legacy row has none.
        expect(find.textContaining('Target'), findsOneWidget);
        expect(find.textContaining('null'), findsNothing);
        expect(find.textContaining('Started Mar 1, 2026'), findsNWidgets(2));
      });

      testWidgets('tapping a goal opens its archived progress screen', (
        tester,
      ) async {
        _bigView(tester);
        await tester.pumpWidget(
          _app(
            theme,
            overrides([
              _goal(
                id: 7,
                status: 'archived',
                archivedAt: DateTime(2026, 9, 1),
              ),
            ]),
            _opener(PastGoalsSheet.show),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lean athletic'));
        await tester.pumpAndSettle();
        expect(find.text('Progress:7'), findsOneWidget);
        expect(find.text('Past goals'), findsNothing);
      });
    });

    group('dialogs ($name)', () {
      Future<T?> run<T>(
        WidgetTester tester,
        Future<T?> Function(BuildContext) show,
        Future<void> Function() act,
      ) async {
        T? result;
        await tester.pumpWidget(
          _app(
            theme,
            const [],
            _opener((c) async {
              result = await show(c);
            }),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await act();
        await tester.pumpAndSettle();
        return result;
      }

      Color? bg(WidgetTester tester, String label) => tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, label))
          .style
          ?.backgroundColor
          ?.resolve(<WidgetState>{});

      HxColors hx(WidgetTester tester) =>
          tester.element(find.byType(AlertDialog)).hx;

      testWidgets('delete check-in: copy, danger confirm, bool result', (
        tester,
      ) async {
        final r = await run(tester, DeleteCheckInDialog.show, () async {
          expect(find.text('Delete this check-in?'), findsOneWidget);
          expect(
            find.text(
              'The photo is removed from your device. Your next check-in date '
              "won't change.",
            ),
            findsOneWidget,
          );
          expect(find.text('Keep check-in'), findsOneWidget);
          expect(bg(tester, 'Delete check-in'), hx(tester).danger);
          await tester.tap(find.text('Delete check-in'));
        });
        expect(r, isTrue);
        final c = await run(tester, DeleteCheckInDialog.show, () async {
          await tester.tap(find.text('Keep check-in'));
        });
        expect(c, isFalse);
      });

      testWidgets('discard changes: danger confirm', (tester) async {
        final r = await run(tester, DiscardChangesDialog.show, () async {
          expect(find.text('Discard changes?'), findsOneWidget);
          expect(find.text('Keep editing'), findsOneWidget);
          expect(bg(tester, 'Discard changes'), hx(tester).danger);
          await tester.tap(find.text('Discard changes'));
        });
        expect(r, isTrue);
      });

      testWidgets('reset roadmap: primary confirm', (tester) async {
        final r = await run(tester, ResetRoadmapDialog.show, () async {
          expect(find.text('Reset your roadmap?'), findsOneWidget);
          expect(
            find.text('Your edits will be replaced by the suggested plan.'),
            findsOneWidget,
          );
          expect(find.text('Keep my edits'), findsOneWidget);
          expect(bg(tester, 'Reset roadmap'), isNot(hx(tester).danger));
          await tester.tap(find.text('Reset roadmap'));
        });
        expect(r, isTrue);
      });

      testWidgets('start new goal: primary, not danger', (tester) async {
        final r = await run(tester, StartNewGoalDialog.show, () async {
          expect(find.text('Start a new goal?'), findsOneWidget);
          expect(
            find.text(
              'Your current goal, check-ins and photos move to Past goals. You '
              'can still view them.',
            ),
            findsOneWidget,
          );
          expect(find.text('Keep current goal'), findsOneWidget);
          expect(bg(tester, 'Start new goal'), isNot(hx(tester).danger));
          await tester.tap(find.text('Start new goal'));
        });
        expect(r, isTrue);
        final c = await run(tester, StartNewGoalDialog.show, () async {
          await tester.tap(find.text('Keep current goal'));
        });
        expect(c, isFalse);
      });

      testWidgets('no face found: retake or save without blur', (tester) async {
        final save = await run(tester, NoFaceFoundDialog.show, () async {
          expect(find.text('No face found'), findsOneWidget);
          expect(
            find.text(
              "We couldn't find a face to blur, so this photo isn't blurred. "
              'Save it as is, or retake it.',
            ),
            findsOneWidget,
          );
          expect(bg(tester, 'Save without blur'), isNot(hx(tester).danger));
          await tester.tap(find.text('Save without blur'));
        });
        expect(save, NoFaceChoice.saveWithoutBlur);
        final retake = await run(tester, NoFaceFoundDialog.show, () async {
          await tester.tap(find.text('Retake photo'));
        });
        expect(retake, NoFaceChoice.retake);
      });
    });
  }
}
