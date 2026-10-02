import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/presentation/widgets/confidence_range_bar.dart';
import 'package:herculex/features/physique/presentation/widgets/verdict_block.dart';
import 'package:herculex/features/physique/presentation/widgets/verdict_chip.dart';

Widget _host(
  ThemeData theme,
  Widget child, {
  double width = 400,
  double scale = 1,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
      textScaler: TextScaler.linear(scale),
      disableAnimations: disableAnimations,
    ),
    child: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

VerdictBlock _block(
  CheckInVerdict v, {
  CheckInBand? band,
  AssessmentConfidence c = AssessmentConfidence.high,
  String reason = 'Shoulders look fuller.',
  VoidCallback? review,
  VoidCallback? log,
}) => VerdictBlock(
  verdict: v,
  band: band ?? CheckInBand.clamped(0.3, 0.7),
  confidence: c,
  reason: reason,
  onReviewTargets: review,
  onLogMeasurements: log,
);

void main() {
  for (final t in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    final theme = t.$2;

    testWidgets('${t.$1}: chip states', (tester) async {
      final expected = {
        CheckInVerdict.onTrack: ('On track', Icons.trending_up_rounded),
        CheckInVerdict.offTrack: ('Off track', Icons.trending_flat_rounded),
        CheckInVerdict.inconclusive: (
          'Inconclusive',
          Icons.help_outline_rounded,
        ),
      };
      for (final e in expected.entries) {
        await tester.pumpWidget(_host(theme, VerdictChip(verdict: e.key)));
        expect(find.text(e.value.$1), findsOneWidget);
        expect(find.byIcon(e.value.$2), findsOneWidget);
        final hx = tester.element(find.byType(VerdictChip)).hx;
        final icon = tester.widget<Icon>(find.byIcon(e.value.$2));
        final want = switch (e.key) {
          CheckInVerdict.onTrack => hx.success,
          CheckInVerdict.offTrack => hx.warning,
          CheckInVerdict.inconclusive => hx.secondary,
        };
        expect(icon.color, want);
        expect(icon.color, isNot(hx.danger));
        final text = tester.widget<Text>(find.text(e.value.$1));
        expect(text.style!.color, hx.onSurface);
      }
    });

    testWidgets('${t.$1}: bar geometry', (tester) async {
      await tester.pumpWidget(
        _host(
          theme,
          ConfidenceRangeBar(
            band: CheckInBand.clamped(-0.2, 0.5),
            color: Colors.transparent,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(ConfidenceRangeBar));
      var seg = tester.getRect(find.byKey(ConfidenceRangeBar.segmentKey));
      expect(seg.left - bar.left, closeTo(0.4 * 400, 0.5));
      expect(seg.width, closeTo(0.35 * 400, 0.5));
      expect(seg.height, 12);
      expect(find.text('Away from goal'), findsOneWidget);
      expect(find.text('Toward goal'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          theme,
          ConfidenceRangeBar(
            band: CheckInBand.clamped(0.6, 0.9),
            color: Colors.transparent,
          ),
        ),
      );
      await tester.pumpAndSettle();
      seg = tester.getRect(find.byKey(ConfidenceRangeBar.segmentKey));
      expect(seg.left - bar.left, closeTo(0.8 * 400, 0.5));
      expect(seg.width, closeTo(0.15 * 400, 0.5));
    });

    testWidgets('${t.$1}: narrow band keeps minimum width', (tester) async {
      await tester.pumpWidget(
        _host(
          theme,
          ConfidenceRangeBar(
            band: CheckInBand.clamped(0.5, 0.5),
            color: Colors.transparent,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final seg = tester.getRect(find.byKey(ConfidenceRangeBar.segmentKey));
      expect(seg.width, greaterThanOrEqualTo(12));
    });

    testWidgets('${t.$1}: bar animates from centre unless disabled', (
      tester,
    ) async {
      final band = CheckInBand.clamped(0.4, 0.8);
      await tester.pumpWidget(
        _host(theme, ConfidenceRangeBar(band: band, color: Colors.red)),
      );
      final first = tester.getRect(find.byKey(ConfidenceRangeBar.segmentKey));
      await tester.pumpAndSettle();
      final last = tester.getRect(find.byKey(ConfidenceRangeBar.segmentKey));
      expect(first.width, lessThan(last.width));

      await tester.pumpWidget(
        _host(
          theme,
          ConfidenceRangeBar(band: band, color: Colors.red),
          disableAnimations: true,
        ),
      );
      final instant = tester.getRect(find.byKey(ConfidenceRangeBar.segmentKey));
      expect(instant.width, closeTo(last.width, 0.5));
    });

    testWidgets('${t.$1}: confidence caption and hint', (tester) async {
      var logged = 0;
      for (final c in AssessmentConfidence.values) {
        await tester.pumpWidget(
          _host(
            theme,
            _block(CheckInVerdict.inconclusive, c: c, log: () => logged++),
          ),
        );
        final word = switch (c) {
          AssessmentConfidence.high => 'High',
          AssessmentConfidence.medium => 'Medium',
          _ => 'Low',
        };
        expect(find.text('Confidence: $word'), findsOneWidget);
        final low =
            c == AssessmentConfidence.low || c == AssessmentConfidence.unknown;
        expect(
          find.text('Log measurements to refine this.'),
          low ? findsOneWidget : findsNothing,
        );
      }
      await tester.pumpWidget(
        _host(
          theme,
          _block(
            CheckInVerdict.inconclusive,
            c: AssessmentConfidence.low,
            log: () => logged++,
          ),
        ),
      );
      await tester.tap(find.text('Log measurements to refine this.'));
      expect(logged, 1);
      expect(
        find.text('An estimate from your photos, not a measurement.'),
        findsOneWidget,
      );
    });

    testWidgets('${t.$1}: review action rules', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(theme, _block(CheckInVerdict.onTrack, review: () => taps++)),
      );
      expect(find.text('Review nutrition targets'), findsNothing);
      await tester.pumpWidget(
        _host(theme, _block(CheckInVerdict.offTrack, review: () => taps++)),
      );
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
      await tester.tap(find.text('Review nutrition targets'));
      expect(taps, 1);
      await tester.pumpWidget(_host(theme, _block(CheckInVerdict.offTrack)));
      expect(find.text('Review nutrition targets'), findsNothing);
    });

    testWidgets('${t.$1}: no band hides the bar', (tester) async {
      await tester.pumpWidget(
        _host(
          theme,
          const VerdictBlock(
            verdict: CheckInVerdict.inconclusive,
            band: null,
            confidence: AssessmentConfidence.unknown,
            reason: 'Saved without analysis.',
          ),
        ),
      );
      expect(find.byType(ConfidenceRangeBar), findsNothing);
      expect(find.text('Saved without analysis.'), findsOneWidget);
    });

    testWidgets('${t.$1}: semantics labels and no percent', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          theme,
          _block(
            CheckInVerdict.onTrack,
            reason: 'Looks 12% leaner in the shoulders',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('Looks leaner in the shoulders'), findsOneWidget);
      final label = find.semantics
          .byLabel(RegExp('^Check-in verdict'))
          .evaluate()
          .single
          .label;
      expect(
        label,
        'Check-in verdict: On track. Direction estimate leans toward your '
        'goal, high confidence. Looks leaner in the shoulders',
      );
      expect(label.contains('%'), isFalse);

      await tester.pumpWidget(
        _host(
          theme,
          _block(
            CheckInVerdict.offTrack,
            band: CheckInBand.clamped(-0.8, -0.3),
            c: AssessmentConfidence.medium,
          ),
        ),
      );
      expect(
        find.semantics
            .byLabel(RegExp('^Check-in verdict'))
            .evaluate()
            .single
            .label,
        contains(
          'Off track. Direction estimate leans away from your goal, '
          'medium confidence.',
        ),
      );
      handle.dispose();
    });

    testWidgets('${t.$1}: no overflow at 320dp and 2.0 text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          theme,
          _block(
            CheckInVerdict.offTrack,
            c: AssessmentConfidence.low,
            reason:
                'Recent photos do not show the change this phase aims for '
                'yet, so keep going and check back next week.',
            review: () {},
            log: () {},
          ),
          width: 320,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
