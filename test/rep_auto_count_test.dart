import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/reps/data/rep_tracking_repository.dart';
import 'package:herculex/features/reps/domain/rep_movement.dart';
import 'package:herculex/features/reps/domain/rep_suggestion.dart';
import 'package:herculex/features/reps/presentation/rep_auto_count_tile.dart';
import 'package:herculex/features/reps/presentation/rep_tracking_providers.dart';

import 'support/rep_profiles.dart';
import 'support/test_database.dart';

/// The two halves of the "one global switch" rework that are not covered by
/// the repository tests: the rule that decides whether a detected count
/// reaches the user without review, and the settings tile that turns the
/// feature on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  loadRepProfilesForTest();

  group('isConfidentEnoughToPrefill', () {
    test('a high-confidence tracked count prefills', () {
      expect(_suggestion().isConfidentEnoughToPrefill, isTrue);
    });

    test('a medium-confidence tracked count prefills', () {
      expect(
        _suggestion(band: ConfidenceBand.medium).isConfidentEnoughToPrefill,
        isTrue,
      );
    });

    test('a low-confidence count goes to the review sheet instead', () {
      // The band is already lowered one step per independent reason to doubt
      // the capture, so reaching low means something specific went wrong and
      // the user should see what.
      expect(
        _suggestion(
          band: ConfidenceBand.low,
          state: TrackerState.countOnly,
          reason: 'low confidence',
        ).isConfidentEnoughToPrefill,
        isFalse,
      );
    });

    test('countOnly never prefills, however confident', () {
      // Short-range work — a shrug, a calf raise. The count may be right and
      // still not be something to slip into the field unannounced.
      expect(
        _suggestion(
          state: TrackerState.countOnly,
          reason: 'short range of motion',
        ).isConfidentEnoughToPrefill,
        isFalse,
      );
    });

    test('an unmeasured set never prefills', () {
      expect(
        _suggestion(
          state: TrackerState.manual,
          reps: 0,
          reason: 'watch was not connected',
        ).isConfidentEnoughToPrefill,
        isFalse,
      );
    });

    test('a confident zero does not prefill', () {
      // A confident zero is still a zero, and filling a set with it silently
      // would be worse than saying nothing.
      expect(_suggestion(reps: 0).isConfidentEnoughToPrefill, isFalse);
    });
  });

  group('RepAutoCountTile', () {
    late AppDatabase db;
    late RepTrackingRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      repo = RepTrackingRepository(db);
    });

    tearDown(() async => db.close());

    Widget wrap() => ProviderScope(
          overrides: [repTrackingRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: Scaffold(body: RepAutoCountTile())),
        );

    testWidgets('without consent it offers the consent screen, not a switch',
        (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('how motion data is used'), findsOneWidget);
    });

    testWidgets('with consent it shows an off switch', (tester) async {
      await repo.grantConsent(version: 1);

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isFalse, reason: 'off until the user turns it on');
    });

    testWidgets('turning it on enables every measurable exercise', (tester) async {
      await repo.grantConsent(version: 1);

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect((await repo.settings())!.autoCountEnabled, isTrue);
      expect(await repo.isEnabledFor('barbell-bench-press'), isTrue);
      expect(await repo.isEnabledFor('pull-up'), isTrue);
      expect(await repo.isEnabledFor('seated-leg-curl'), isFalse);
    });

    testWidgets('once on, it says where the phone has to go', (tester) async {
      // Stated before the set rather than discovered after it produced
      // nothing: there is no threshold that recovers a pull-up from the
      // wrist, so the only useful moment to mention the pocket is up front.
      await repo.grantConsent(version: 1);
      await repo.setAutoCountEnabled(true);

      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.textContaining('pocket'), findsOneWidget);
    });
  });
}

RepSuggestion _suggestion({
  ConfidenceBand band = ConfidenceBand.high,
  TrackerState state = TrackerState.tracking,
  int reps = 8,
  String? reason,
}) =>
    RepSuggestion(
      captureId: 'c1',
      exerciseSlug: 'barbell-bench-press',
      movement: RepMovement.horizontalPush,
      source: 'wrist',
      sensorType: 'linear_acceleration',
      proposedReps: reps,
      provisionalDisagrees: false,
      setConfidence: band == ConfidenceBand.high ? 0.9 : 0.5,
      confidenceBand: band,
      missedRepSuspected: false,
      missedBatches: 0,
      sampleCount: 500,
      coverageRatio: 1,
      state: state,
      stateReason: reason,
    );
