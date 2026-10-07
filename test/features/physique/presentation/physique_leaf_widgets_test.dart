import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/physique/presentation/widgets/phase_type_pill.dart';
import 'package:herculex/features/physique/presentation/widgets/restriction_notice.dart';

Widget _host(ThemeData theme, Widget child) => MaterialApp(
  theme: theme,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  test('route constants', () {
    expect(AppRoutes.dreamPhysiqueProgress, '/dream-physique/progress');
    expect(AppPaths.dreamPhysiqueProgress(), '/dream-physique/progress');
    expect(
      AppPaths.dreamPhysiqueProgress(goalId: 7),
      '/dream-physique/progress?goalId=7',
    );
  });

  test('phase icons', () {
    expect(PhaseTypeIcon.of(DietPhase.cut), Icons.trending_down_rounded);
    expect(PhaseTypeIcon.of(DietPhase.bulk), Icons.trending_up_rounded);
    expect(PhaseTypeIcon.of(DietPhase.maintain), Icons.drag_handle_rounded);
    expect(PhaseTypeIcon.of(DietPhase.recomp), Icons.swap_vert_rounded);
    expect(PhaseTypeIcon.of(DietPhase.maingain), Icons.north_east_rounded);
  });

  for (final t in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    final theme = t.$2;

    testWidgets('${t.$1}: disabled pill is 48 high and disabled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(theme, const PhaseTypePill(phase: DietPhase.cut)),
      );
      expect(
        tester.getSize(find.byType(PhaseTypePill)).height,
        greaterThanOrEqualTo(48),
      );
      final node = tester.getSemantics(find.byType(PhaseTypePill));
      expect(node.flagsCollection.isEnabled, isNot(isTrue));
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('${t.$1}: enabled pill taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(theme, PhaseTypePill(phase: DietPhase.bulk, onTap: () => taps++)),
      );
      await tester.tap(find.text(DietPhase.bulk.label));
      expect(taps, 1);
    });

    for (final r in PhaseRestrictionReason.values) {
      testWidgets('${t.$1}: notice copy and action for $r', (tester) async {
        var taps = 0;
        await tester.pumpWidget(_host(theme, RestrictionNotice(reason: r)));
        expect(find.text(RestrictionNotice.copyFor(r)), findsOneWidget);
        expect(find.byType(TextButton), findsNothing);

        final label = RestrictionNotice.actionLabelFor(r);
        await tester.pumpWidget(
          _host(theme, RestrictionNotice(reason: r, onAction: () => taps++)),
        );
        if (label == null) {
          expect(find.byType(TextButton), findsNothing);
        } else {
          await tester.tap(find.text(label));
          expect(taps, 1);
        }
      });
    }

    testWidgets('${t.$1}: exact copy', (tester) async {
      expect(
        RestrictionNotice.copyFor(PhaseRestrictionReason.under18),
        'Cut and Bulk are not available under 18. Maintenance, '
        'Recomp or a small Lean bulk move you forward safely, '
        'and Maintenance is a good starting point.',
      );
      expect(
        RestrictionNotice.copyFor(PhaseRestrictionReason.ageMissing),
        'Add your age to unlock all phases. Until then we offer Maintenance, '
        'Recomp and Lean bulk.',
      );
      expect(
        RestrictionNotice.copyFor(PhaseRestrictionReason.lowConfidence),
        'This analysis is not reliable enough for a cut or bulk plan. '
        'Add measurements to improve it.',
      );
      expect(
        RestrictionNotice.actionLabelFor(PhaseRestrictionReason.ageMissing),
        'Add age in profile',
      );
      expect(
        RestrictionNotice.actionLabelFor(PhaseRestrictionReason.lowConfidence),
        'Add measurements',
      );
    });

    testWidgets('${t.$1}: list renders per reason', (tester) async {
      await tester.pumpWidget(
        _host(
          theme,
          const RestrictionNoticeList(
            eligibility: PhaseEligibility.unrestricted(),
          ),
        ),
      );
      expect(find.byType(RestrictionNotice), findsNothing);

      await tester.pumpWidget(
        _host(
          theme,
          const RestrictionNoticeList(
            eligibility: PhaseEligibility(
              allowedPhases: {DietPhase.maintain},
              reasons: {
                PhaseRestrictionReason.lowConfidence,
                PhaseRestrictionReason.under18,
              },
            ),
          ),
        ),
      );
      expect(find.byType(RestrictionNotice), findsNWidgets(2));
    });
  }

  test('presentation sources use tokens and allowed weights only', () {
    final files = Directory('lib/features/physique/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    const banned = [
      'AppColors',
      'Color(0x',
      'Colors.',
      'FontWeight.w500',
      'FontWeight.w700',
      'FontWeight.w800',
      'FontWeight.w900',
      'boxShadow',
    ];
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final b in banned) {
        expect(src.contains(b), isFalse, reason: '${f.path} contains $b');
      }
    }
  });
}
