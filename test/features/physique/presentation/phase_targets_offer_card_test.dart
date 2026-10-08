import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/in_app_notification_overlay.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/application/phase_targets_applier.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/phase_targets_offer_provider.dart';
import 'package:herculex/features/physique/presentation/widgets/phase_targets_offer_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _goalId = 1;

PhaseTargetsOffer _offer({DietPhase? currentPlan = DietPhase.maintain}) =>
    PhaseTargetsOffer(
      goalId: _goalId,
      phase: DietPhase.cut,
      pace: DietPhaseCalculator.paceOptionsFor(DietPhase.cut)[1],
      targets: const PhaseTargets(
        kcal: 2000,
        proteinG: 176,
        carbsG: 200,
        fatG: 60,
        deltaKcal: -500,
      ),
      currentPlan: currentPlan,
    );

class _FakeApplier implements PhaseTargetsApplier {
  final calls =
      <({DietPhase phase, DietPaceOption pace, PhaseTargets targets})>[];

  @override
  Future<void> apply({
    required DietPhase phase,
    required DietPaceOption pace,
    required PhaseTargets targets,
  }) async {
    calls.add((phase: phase, pace: pace, targets: targets));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  final applier = _FakeApplier();
  late SharedPreferences prefs;
  Object? reviewExtra;
  var reviewOpened = false;

  Future<void> init() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  }

  Widget host(PhaseTargetsOffer? offer, {double scale = 1}) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(
              child: PhaseTargetsOfferCard(goalId: _goalId),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.nutritionTargets,
          builder: (_, state) {
            reviewOpened = true;
            reviewExtra = state.extra;
            return const Scaffold(body: Text('NUTRITION TARGETS'));
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        phaseTargetsApplierProvider.overrideWithValue(applier),
        phaseTargetsOfferProvider(_goalId).overrideWith((ref) => offer),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
        builder: (context, child) => InAppNotificationHost(
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('says what the calories are set for and what the phase needs', (
    tester,
  ) async {
    final h = _Harness();
    await h.init();
    await tester.pumpWidget(h.host(_offer()));
    await tester.pumpAndSettle();
    expect(find.text('Match your calories to this phase'), findsOneWidget);
    expect(
      find.text(
        'Your calories are set for Maintenance. Cut suggests 2000 kcal · '
        'P 176 / C 200 / F 60 g.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a plan that was never set reads differently', (tester) async {
    final h = _Harness();
    await h.init();
    await tester.pumpWidget(h.host(_offer(currentPlan: null)));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('You have not set calories for a phase yet.'),
      findsOneWidget,
    );
  });

  testWidgets('no offer, no card', (tester) async {
    final h = _Harness();
    await h.init();
    await tester.pumpWidget(h.host(null));
    await tester.pumpAndSettle();
    expect(find.text('Match your calories to this phase'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('nothing is applied until Apply targets is tapped', (
    tester,
  ) async {
    final h = _Harness();
    await h.init();
    await tester.pumpWidget(h.host(_offer()));
    await tester.pumpAndSettle();
    expect(h.applier.calls, isEmpty);

    await tester.tap(find.byKey(const Key('phase-offer-apply')));
    await tester.pumpAndSettle();

    expect(h.applier.calls, hasLength(1));
    final call = h.applier.calls.single;
    expect(call.phase, DietPhase.cut);
    expect(call.pace.kcalDelta, -500);
    expect(call.targets.kcal, 2000);
    expect(find.text('Targets updated'), findsOneWidget);
    expect(find.text('Cut • 2000 kcal'), findsOneWidget);
  });

  testWidgets('Review first opens the editor on that phase, applying nothing', (
    tester,
  ) async {
    final h = _Harness();
    await h.init();
    await tester.pumpWidget(h.host(_offer()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('phase-offer-review')));
    await tester.pumpAndSettle();

    expect(h.reviewOpened, isTrue);
    expect(h.reviewExtra, DietPhase.cut);
    expect(find.text('NUTRITION TARGETS'), findsOneWidget);
    expect(h.applier.calls, isEmpty);
  });

  testWidgets('Not now remembers the choice for this phase', (tester) async {
    final h = _Harness();
    await h.init();
    await tester.pumpWidget(h.host(_offer()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('phase-offer-dismiss')));
    await tester.pumpAndSettle();

    expect(h.prefs.getStringList('physique_targets_offer_dismissed'), [
      '$_goalId:cut',
    ]);
    expect(h.applier.calls, isEmpty);
  });

  testWidgets('survives 320 dp at 2.0 text scale', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = _Harness();
    await h.init();
    await tester.pumpWidget(h.host(_offer(), scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Apply targets'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });
}
