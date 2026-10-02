import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_chart_providers.dart';
import 'package:herculex/features/physique/domain/physique_series.dart';
import 'package:herculex/features/physique/domain/physique_strength_series.dart';
import 'package:herculex/features/physique/presentation/widgets/strength_chart_card.dart';
import 'package:herculex/features/physique/presentation/widgets/training_level_chart_card.dart';
import 'package:herculex/features/physique/presentation/widgets/weight_chart_card.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';

const _goal = 1;
final _start = DateTime(2026, 6, 1);
DateTime _d(int i) => DateTime(_start.year, _start.month, _start.day + i);

WeightChartData _richWeight() => WeightChartData(
  trend: [for (var i = 0; i <= 60; i++) ChartPoint(_d(i), 90 - i * 0.05)],
  raw: [
    for (var i = 0; i <= 60; i += 3) ChartPoint(_d(i), 90 - i * 0.05 + 0.3),
  ],
  bands: [
    PhaseBandSpan(
      phase: DietPhase.cut,
      start: _d(-10),
      end: _d(40),
      startLowKg: 89,
      startHighKg: 91,
      endLowKg: 86,
      endHighKg: 88,
    ),
    PhaseBandSpan(
      phase: DietPhase.maintain,
      start: _d(40),
      end: _d(90),
      startLowKg: 86,
      startHighKg: 88,
      endLowKg: 86,
      endHighKg: 88,
    ),
  ],
  textSummary: 'Down 3.0 kg over 3 months.',
);

const _emptyWeight = WeightChartData.empty;
final _singleWeight = WeightChartData(
  trend: [ChartPoint(_d(0), 90)],
  raw: [ChartPoint(_d(0), 90)],
  bands: const [],
  textSummary: 'Not enough weigh-ins yet.',
);

StrengthChartData _strength() => StrengthChartData(
  lift: PrimaryLift.benchPress,
  points: [for (var i = 0; i < 8; i++) ChartPoint(_d(i * 7), 100 + i * 1.0)],
  liftsWithData: {PrimaryLift.benchPress, PrimaryLift.squat},
);

List<TrainingLevelPoint> _levels() => [
  for (var i = 0; i < 12; i++)
    TrainingLevelPoint(
      _d(i * 7),
      i < 6 ? ExperienceLevel.novice : ExperienceLevel.intermediate,
    ),
];

Widget _host({
  required ThemeData theme,
  required Widget child,
  WeightChartData weight = WeightChartData.empty,
  StrengthChartData strength = StrengthChartData.empty,
  List<TrainingLevelPoint> levels = const [],
  double width = 400,
  double scale = 1,
  bool disableAnimations = false,
}) {
  return ProviderScope(
    overrides: [
      physiqueWeightChartProvider(_goal).overrideWith((ref) => weight),
      physiqueStrengthChartProvider(_goal).overrideWith((ref) => strength),
      physiqueTrainingLevelChartProvider(_goal).overrideWith((ref) => levels),
      physiqueEffectiveRangeProvider(
        _goal,
      ).overrideWith((ref) => ChartRange.quarter),
    ],
    child: MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(scale),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}

Finder _plotSemantics(Pattern label) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      w.excludeSemantics &&
      w.properties.label != null &&
      (label is RegExp
          ? label.hasMatch(w.properties.label!)
          : w.properties.label == label),
);

void main() {
  for (final t in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    final theme = t.$2;

    testWidgets('${t.$1}: weight card with rich data', (tester) async {
      await tester.pumpWidget(
        _host(
          theme: theme,
          weight: _richWeight(),
          child: const WeightChartCard(goalId: _goal),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('Trend'), findsOneWidget);
      expect(find.text('Target range'), findsOneWidget);
      expect(find.text('Down 3.0 kg over 3 months.'), findsOneWidget);
      expect(find.text('87 kg'), findsNothing);
      expect(find.text('87.0 kg'), findsOneWidget);
    });

    testWidgets('${t.$1}: weight card empty and single point', (tester) async {
      for (final data in [_emptyWeight, _singleWeight]) {
        await tester.pumpWidget(
          _host(
            theme: theme,
            weight: data,
            child: const WeightChartCard(goalId: _goal),
          ),
        );
        await tester.pump();
        expect(find.byType(LineChart), findsNothing);
        expect(find.text('Log your weight to see your trend.'), findsOneWidget);
      }
    });

    testWidgets('${t.$1}: strength card selector and summary', (tester) async {
      await tester.pumpWidget(
        _host(
          theme: theme,
          strength: _strength(),
          child: const StrengthChartCard(goalId: _goal),
        ),
      );
      await tester.pump();
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('Estimated 1RM'), findsOneWidget);
      expect(find.text('Up 7 kg over 3 months.'), findsOneWidget);

      HxPill pillFor(PrimaryLift l) => tester.widget<HxPill>(
        find.ancestor(of: find.text(l.label), matching: find.byType(HxPill)),
      );
      expect(pillFor(PrimaryLift.deadlift).onTap, isNull);
      expect(pillFor(PrimaryLift.pullUp).onTap, isNull);
      expect(pillFor(PrimaryLift.squat).onTap, isNotNull);
      expect(pillFor(PrimaryLift.benchPress).selected, isTrue);

      await tester.tap(find.text('Squat'));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StrengthChartCard)),
      );
      expect(container.read(physiqueSelectedLiftProvider), PrimaryLift.squat);
    });

    testWidgets('${t.$1}: strength card empty', (tester) async {
      await tester.pumpWidget(
        _host(
          theme: theme,
          child: const StrengthChartCard(goalId: _goal),
        ),
      );
      await tester.pump();
      expect(find.byType(LineChart), findsNothing);
      expect(
        find.text('Log a Squat set to see your strength trend.'),
        findsOneWidget,
      );
      final pill = tester.widget<HxPill>(
        find.ancestor(of: find.text('Squat'), matching: find.byType(HxPill)),
      );
      expect(pill.onTap, isNull);
    });

    testWidgets('${t.$1}: training level card', (tester) async {
      await tester.pumpWidget(
        _host(
          theme: theme,
          levels: _levels(),
          child: const TrainingLevelChartCard(goalId: _goal),
        ),
      );
      await tester.pump();
      expect(find.byType(LineChart), findsOneWidget);
      expect(
        find.text('Based on your training history, not your XP rank.'),
        findsOneWidget,
      );
      expect(find.text('Intermediate'), findsWidgets);
      expect(find.textContaining('Reached Intermediate in'), findsOneWidget);
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final bar = chart.data.lineBarsData.single;
      expect(bar.isStepLineChart, isTrue);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('${t.$1}: training level card empty', (tester) async {
      await tester.pumpWidget(
        _host(
          theme: theme,
          child: const TrainingLevelChartCard(goalId: _goal),
        ),
      );
      await tester.pump();
      expect(find.byType(LineChart), findsNothing);
      expect(
        find.text('Keep training and your level will appear here.'),
        findsOneWidget,
      );
    });
  }

  testWidgets('each plot exposes its summary through Semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        theme: AppTheme.lightTheme,
        weight: _richWeight(),
        strength: _strength(),
        levels: _levels(),
        child: const Column(
          children: [
            WeightChartCard(goalId: _goal),
            StrengthChartCard(goalId: _goal),
            TrainingLevelChartCard(goalId: _goal),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(_plotSemantics('Down 3.0 kg over 3 months.'), findsOneWidget);
    expect(_plotSemantics('Up 7 kg over 3 months.'), findsOneWidget);
    expect(_plotSemantics(RegExp('^Reached Intermediate')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('disableAnimations renders without pending frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        theme: AppTheme.darkTheme,
        weight: _richWeight(),
        disableAnimations: true,
        child: const WeightChartCard(goalId: _goal),
      ),
    );
    await tester.pump();
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.duration, Duration.zero);
  });

  testWidgets('320 dp at 2.0 text scale does not overflow', (tester) async {
    for (final data in [true, false]) {
      await tester.pumpWidget(
        _host(
          theme: AppTheme.lightTheme,
          weight: data ? _richWeight() : WeightChartData.empty,
          strength: data ? _strength() : StrengthChartData.empty,
          levels: data ? _levels() : const [],
          width: 320,
          scale: 2,
          child: const Column(
            children: [
              WeightChartCard(goalId: _goal),
              StrengthChartCard(goalId: _goal),
              TrainingLevelChartCard(goalId: _goal),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  test('chart sources stay free of XP and gamification', () {
    for (final f in [
      'weight_chart_card.dart',
      'strength_chart_card.dart',
      'training_level_chart_card.dart',
    ]) {
      final src = File(
        'lib/features/physique/presentation/widgets/$f',
      ).readAsStringSync();
      expect(src.contains('gamification'), isFalse, reason: f);
      expect(src.contains('levelProgressProvider'), isFalse, reason: f);
    }
  });
}
