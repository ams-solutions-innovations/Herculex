import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/features/nutrition/data/tdee_estimates_repository.dart';
import 'package:herculex/features/weekly_report/application/weekly_report_controller.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_inputs_repository.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_narrative_service.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_repository.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_service.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/narrative_status.dart';
import 'package:herculex/features/weekly_report/domain/weekly_narrative.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_payload.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

/// Counts calls; can be gated on a [Completer] to keep a call "in flight".
class _FakeBackend implements WeeklyReportBackend {
  int calls = 0;
  Completer<void>? gate;
  Object? error;
  Future<void> Function()? onCall;

  @override
  Future<(Map<String, dynamic>, Map<String, dynamic>)>
  generateWeeklyReportNarrative({required Map<String, dynamic> facts}) async {
    calls++;
    await onCall?.call();
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return (
      {
        'summary': 'You logged food on most days.',
        'suggestions': ['Keep protein steady.'],
      },
      {'knowledgeVersion': 'kb', 'modelVersion': 'm'},
    );
  }
}

/// A service whose calls throw, to prove the controller is the fail-soft layer.
class _ThrowingService extends WeeklyReportService {
  _ThrowingService({
    required super.repository,
    required super.inputs,
    required super.narrative,
    required super.clock,
  }) : super(targetForDay: (_) async => null);

  bool throwOnGenerate = true;
  bool throwOnNarrative = true;

  @override
  Future<WeeklyReportRecord?> generate(IsoWeek week) async {
    if (throwOnGenerate) throw StateError('generate exploded');
    return super.generate(week);
  }

  @override
  Future<NarrativeOutcome> generateNarrative(IsoWeek week) async {
    if (throwOnNarrative) throw StateError('narrative exploded');
    return super.generateNarrative(week);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 2026-W40: Monday 2026-09-28 to Sunday 2026-10-04.
  final week = IsoWeek(2026, 40);
  final wednesday = DateTime(2026, 9, 30, 18);

  group('WeeklyReportController', () {
    late AppDatabase db;
    late FakeClock clock;
    late SharedPreferences prefs;
    late NutritionRepository nutrition;
    late WeeklyReportRepository repository;
    late WeeklyReportInputsRepository inputs;
    late _FakeBackend backend;
    late WeeklyReportService service;
    late WeeklyReportController controller;
    late Map<IsoWeek, NarrativeUiState> uiStates;
    late List<String> dismissed;
    late bool enabled;

    WeeklyReportController build(WeeklyReportService s) =>
        WeeklyReportController(
          service: s,
          repository: repository,
          clock: clock,
          prefs: prefs,
          isEnabled: () => enabled,
          readUiState: (w) => uiStates[w] ?? const NarrativeUiState(),
          writeUiState: (w, s) => uiStates[w] = s,
          onDismissedWeek: dismissed.add,
        );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = await openTestDatabase();
      clock = FakeClock(wednesday);
      nutrition = NutritionRepository(db, OpenFoodFactsClient(), clock);
      repository = WeeklyReportRepository(db, clock);
      inputs = WeeklyReportInputsRepository(
        db,
        nutrition,
        TdeeEstimatesRepository(db, clock),
      );
      backend = _FakeBackend();
      service = WeeklyReportService(
        repository: repository,
        inputs: inputs,
        narrative: WeeklyReportNarrativeService(backend),
        clock: clock,
        targetForDay: (_) async => null,
      );
      uiStates = {};
      dismissed = [];
      enabled = true;
      controller = build(service);
    });

    tearDown(() async => db.close());

    Future<void> seedFood() async {
      final id = await db
          .into(db.foods)
          .insert(FoodsCompanion.insert(name: 'Oats', kcalPer100g: 400));
      await nutrition.logFood(
        date: DateTime(2026, 9, 28),
        foodId: id,
        grams: 100,
      );
      await nutrition.logFood(
        date: DateTime(2026, 9, 29),
        foodId: id,
        grams: 100,
      );
    }

    Future<int> reportRows() async =>
        (await db.select(db.weeklyReports).get()).length;

    Future<void> pumpUntil(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(done(), isTrue, reason: 'condition not reached');
    }

    NarrativeUiState ui() => uiStates[week] ?? const NarrativeUiState();

    test('concurrent open() calls share one generate and one backend call', () async {
      await seedFood();
      backend.gate = Completer<void>();

      final results = await Future.wait([
        controller.open(week),
        controller.open(week),
      ]);

      expect(results[0], isA<WeeklyReportReady>());
      expect(results[1], isA<WeeklyReportReady>());
      expect(await reportRows(), 1);
      await pumpUntil(() => backend.calls == 1);
      backend.gate!.complete();
      await controller.narrationInFlight(week);
      expect(backend.calls, 1);
    });

    test('row is persisted before the backend is called and open() does not '
        'wait for the call', () async {
      await seedFood();
      int? rowsAtCall;
      backend.onCall = () async => rowsAtCall = await reportRows();
      backend.gate = Completer<void>();

      final result = await controller.open(week);

      expect(result, isA<WeeklyReportReady>());
      expect(await reportRows(), 1);
      await pumpUntil(() => backend.calls == 1);
      expect(rowsAtCall, 1);
      // The call is still gated, so open() demonstrably returned without it.
      expect(ui().inFlight, isTrue);
      expect(controller.narrationInFlight(week), isNotNull);

      backend.gate!.complete();
      await controller.narrationInFlight(week);
      expect(ui().inFlight, isFalse);
      final record = await repository.forWeek(week);
      expect(record!.narrativeJson, isNotNull);
    });

    test('UI state is already in flight when open() returns', () async {
      await seedFood();
      backend.gate = Completer<void>();

      await controller.open(week);

      expect(ui().inFlight, isTrue);
      backend.gate!.complete();
      await controller.narrationInFlight(week);
    });

    test('a failed narrative is never retried automatically', () async {
      await seedFood();
      backend.error = Exception('boom');

      await controller.open(week);
      await controller.narrationInFlight(week);

      var record = await repository.forWeek(week);
      expect(record, isNotNull);
      expect(record!.narrativeJson, isNull);
      expect(record.narrativeAttempts, 1);
      expect(backend.calls, 1);
      expect(ui().failure, NarrativeFailureKind.unavailable);
      expect(ui().inFlight, isFalse);

      for (var i = 0; i < 3; i++) {
        await controller.open(week);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(controller.narrationInFlight(week), isNull);
      }

      expect(backend.calls, 1);
      record = await repository.forWeek(week);
      expect(record!.narrativeAttempts, 1);
    });

    test('retryNarrative fires exactly one call and saves on success', () async {
      await seedFood();
      backend.error = Exception('boom');
      await controller.open(week);
      await controller.narrationInFlight(week);
      backend.error = null;

      final outcome = await controller.retryNarrative(week);

      expect(outcome.isSaved, isTrue);
      expect(backend.calls, 2);
      final record = await repository.forWeek(week);
      expect(record!.narrativeAttempts, 2);
      expect(record.narrativeJson, isNotNull);
      expect(ui().failure, isNull);
      expect(ui().inFlight, isFalse);
    });

    test('concurrent retries share one backend call', () async {
      await seedFood();
      backend.error = Exception('boom');
      await controller.open(week);
      await controller.narrationInFlight(week);
      final before = backend.calls;
      backend.error = null;
      backend.gate = Completer<void>();

      final a = controller.retryNarrative(week);
      final b = controller.retryNarrative(week);
      await pumpUntil(() => backend.calls == before + 1);
      backend.gate!.complete();
      final outcomes = await Future.wait([a, b]);

      expect(outcomes.every((o) => o.isSaved), isTrue);
      expect(backend.calls, before + 1);
    });

    test('once saved, neither open() nor retryNarrative() calls the backend', () async {
      await seedFood();
      await controller.open(week);
      await controller.narrationInFlight(week);
      expect(backend.calls, 1);

      await controller.open(week);
      final outcome = await controller.retryNarrative(week);

      expect(outcome.status, NarrativeOutcomeStatus.alreadySaved);
      expect(backend.calls, 1);
    });

    test('opt-in off, no row: Disabled, nothing created, no call', () async {
      await seedFood();
      enabled = false;

      final result = await controller.open(week);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(result, isA<WeeklyReportDisabled>());
      expect(await reportRows(), 0);
      expect(backend.calls, 0);
    });

    test('opt-in off, existing row: returned, no narrative fired', () async {
      await seedFood();
      await service.generate(week);
      enabled = false;

      final result = await controller.open(week);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(result, isA<WeeklyReportReady>());
      expect(await reportRows(), 1);
      expect(backend.calls, 0);
      expect(ui().inFlight, isFalse);
    });

    test('no-signal week: NoData, no row, dismissed marker stored', () async {
      final result = await controller.open(week);

      expect(result, isA<WeeklyReportNoData>());
      expect(await reportRows(), 0);
      expect(backend.calls, 0);
      expect(prefs.getString('weekly_report_dismissed_week'), '2026-40');
      expect(dismissed, ['2026-40']);
    });

    test('open marks the row viewed once', () async {
      await seedFood();
      await controller.open(week);
      await controller.narrationInFlight(week);
      final first = (await repository.forWeek(week))!.viewedAt;
      expect(first, isNotNull);

      clock.advance(const Duration(hours: 3));
      await controller.open(week);

      expect((await repository.forWeek(week))!.viewedAt, first);
    });

    test('service exceptions become state, never thrown', () async {
      final throwing = _ThrowingService(
        repository: repository,
        inputs: inputs,
        narrative: WeeklyReportNarrativeService(backend),
        clock: clock,
      );
      final c = build(throwing);

      final result = await c.open(week);
      expect(result, isA<WeeklyReportFailed>());

      final outcome = await c.retryNarrative(week);
      expect(outcome.isFailed, isTrue);
      expect(outcome.failure, NarrativeFailureKind.unavailable);
      expect(ui().failure, NarrativeFailureKind.unavailable);
      expect(ui().inFlight, isFalse);
    });

    test('quota exhaustion records the calendar day', () async {
      await seedFood();
      backend.error = Exception("You've used up today's allowance");

      await controller.open(week);
      await controller.narrationInFlight(week);

      expect(ui().failure, NarrativeFailureKind.quotaExhausted);
      expect(ui().quotaDayIso, '2026-09-30');
    });
  });

  group('narrativeStatusFor', () {
    final payloadWithSignal = WeeklyReportPayload(
      isoYear: 2026,
      isoWeek: 40,
      weekStartIso: '2026-09-28',
      weekEndIso: '2026-10-04',
      windowEnd: DateTime(2026, 10, 5),
      nutrition: NutritionSection(
        daysLogged: 2,
        avgKcal: 2000,
        avgProteinG: 100,
        topFoods: [],
      ),
    );
    final noSignal = WeeklyReportPayload(
      isoYear: 2026,
      isoWeek: 40,
      weekStartIso: '2026-09-28',
      weekEndIso: '2026-10-04',
      windowEnd: DateTime(2026, 10, 5),
    );
    final now = DateTime(2026, 9, 30, 18);

    WeeklyReportRecord record({String? narrativeJson, int attempts = 0}) =>
        WeeklyReportRecord(
          id: 1,
          week: week,
          weekStartIso: '2026-09-28',
          generatedAt: now,
          payloadVersion: 1,
          payloadJson: '{}',
          narrativeJson: narrativeJson,
          narrativeAttempts: attempts,
          knowledgeVersion: null,
          modelVersion: null,
          tdeeDecision: null,
          tdeeDecisionKcal: null,
          viewedAt: null,
        );

    NarrativeCardModel? status({
      WeeklyReportRecord? r,
      WeeklyReportPayload? payload,
      NarrativeUiState ui = const NarrativeUiState(),
      DateTime? at,
    }) => narrativeStatusFor(
      record: r ?? record(),
      payload: payload ?? payloadWithSignal,
      ui: ui,
      now: at ?? now,
    );

    test('saved narrative -> ready with the narrative, no retry', () {
      final stored = jsonEncode(
        const WeeklyNarrative(
          summary: 'You logged food on most days.',
          suggestions: ['Keep protein steady.'],
        ).toJson(),
      );
      final model = status(r: record(narrativeJson: stored))!;
      expect(model.status, NarrativeStatus.ready);
      expect(model.narrative?.summary, 'You logged food on most days.');
      expect(model.retryEnabled, isFalse);
    });

    test('unreadable stored narrative -> pending without retry', () {
      final model = status(r: record(narrativeJson: '{not json'))!;
      expect(model.status, NarrativeStatus.pending);
      expect(model.retryEnabled, isFalse);
    });

    test('endless-skeleton guard: not in flight is pending, in flight is '
        'loading', () {
      final idle = status(ui: const NarrativeUiState(inFlight: false))!;
      expect(idle.status, NarrativeStatus.pending);
      expect(idle.retryEnabled, isTrue);

      final busy = status(ui: const NarrativeUiState(inFlight: true))!;
      expect(busy.status, NarrativeStatus.loading);
      expect(busy.retryEnabled, isFalse);
    });

    test('attempts already spent and not in flight -> pending with retry', () {
      final model = status(r: record(attempts: 3))!;
      expect(model.status, NarrativeStatus.pending);
      expect(model.retryEnabled, isTrue);
    });

    test('failure kinds map to offline / quotaExhausted / pending', () {
      NarrativeStatus of(NarrativeFailureKind kind) =>
          status(ui: NarrativeUiState(failure: kind, quotaDayIso: '2026-09-30'))!
              .status;

      expect(of(NarrativeFailureKind.offline), NarrativeStatus.offline);
      expect(
        of(NarrativeFailureKind.quotaExhausted),
        NarrativeStatus.quotaExhausted,
      );
      expect(of(NarrativeFailureKind.rejected), NarrativeStatus.pending);
      expect(of(NarrativeFailureKind.unavailable), NarrativeStatus.pending);
      expect(of(NarrativeFailureKind.unconfigured), NarrativeStatus.pending);
    });

    test('quota blocks Retry only for the rest of the same calendar day', () {
      const quota = NarrativeUiState(
        failure: NarrativeFailureKind.quotaExhausted,
        quotaDayIso: '2026-09-30',
      );

      final sameDay = status(ui: quota, at: DateTime(2026, 9, 30, 23, 59))!;
      expect(sameDay.status, NarrativeStatus.quotaExhausted);
      expect(sameDay.retryEnabled, isFalse);

      final nextDay = status(ui: quota, at: DateTime(2026, 10, 1, 0, 1))!;
      expect(nextDay.status, NarrativeStatus.pending);
      expect(nextDay.retryEnabled, isTrue);
    });

    test('offline and other failures keep Retry enabled', () {
      final model = status(
        ui: const NarrativeUiState(failure: NarrativeFailureKind.offline),
      )!;
      expect(model.retryEnabled, isTrue);
    });

    test('no narrative signal or no payload -> skipped (null)', () {
      expect(status(payload: noSignal), isNull);
      expect(
        narrativeStatusFor(
          record: record(),
          payload: null,
          ui: const NarrativeUiState(),
          now: now,
        ),
        isNull,
      );
    });
  });
}
