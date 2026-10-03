import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_payload.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';

const _nutrition = NutritionSection(
  daysLogged: 6,
  avgKcal: 2410,
  avgProteinG: 168,
  targetKcal: 2500,
  targetProteinG: 170,
  adherenceDays: 4,
  topFoods: [
    TopFood(name: 'Chicken breast', count: 9),
    TopFood(name: 'Oats', count: 6),
  ],
);

const _training = TrainingSection(
  sessions: 4,
  tonnageKg: 18250.5,
  prevWeekTonnageKg: 17000,
  e1rmMovers: [
    E1rmMover(exerciseName: 'Bench Press', e1rmKg: 105.5, deltaKg: 2.5),
  ],
);

const _recovery = RecoverySection(
  avgSleepHours: 7.4,
  avgSteps: 9120,
  avgRestingHr: 56.5,
  cnsReadinessPct: 82,
  cnsDeloadSuggested: false,
  recoveryWarnings: ['Quads still recovering'],
  correlations: [
    CorrelationLine(
      kind: 'sleep_rpe',
      statement:
          'On days with more sleep, your session RPE tended to be lower (n = 9)',
      sampleSize: 9,
    ),
  ],
);

const _physique = PhysiqueSection(
  checkInVerdict: 'on_track',
  checkInConfidence: 'medium',
  checkInDateIso: '2026-09-30',
  bodyweightKg: 82.4,
  bodyweightDeltaKg: -0.3,
);

const _tdee = TdeeSection(
  oldKcal: 2500,
  newKcal: 2620,
  deltaKcal: 120,
  material: true,
  confidence: 'medium',
);

WeeklyReportPayload _payload({
  NutritionSection? nutrition,
  TrainingSection? training,
  RecoverySection? recovery,
  PhysiqueSection? physique,
  TdeeSection? tdee,
}) => WeeklyReportPayload(
  isoYear: 2026,
  isoWeek: 40,
  weekStartIso: '2026-09-28',
  weekEndIso: '2026-10-04',
  windowEnd: DateTime(2026, 10, 4, 18, 0),
  nutrition: nutrition,
  training: training,
  recovery: recovery,
  physique: physique,
  tdee: tdee,
);

Map<String, dynamic> _roundTrip(WeeklyReportPayload p) =>
    jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;

void main() {
  group('round trip', () {
    test('fully populated payload survives encode and decode', () {
      final p = _payload(
        nutrition: _nutrition,
        training: _training,
        recovery: _recovery,
        physique: _physique,
        tdee: _tdee,
      );
      final back = WeeklyReportPayload.fromJson(_roundTrip(p));

      expect(back.payloadVersion, 1);
      expect(back.isoYear, 2026);
      expect(back.isoWeek, 40);
      expect(back.weekStartIso, '2026-09-28');
      expect(back.weekEndIso, '2026-10-04');
      expect(back.windowEnd, DateTime(2026, 10, 4, 18, 0));
      expect(back.nutrition!.avgKcal, 2410);
      expect(back.nutrition!.topFoods.map((f) => f.name), [
        'Chicken breast',
        'Oats',
      ]);
      expect(back.nutrition!.adherenceDays, 4);
      expect(back.training!.tonnageKg, 18250.5);
      expect(back.training!.prevWeekTonnageKg, 17000);
      expect(back.training!.e1rmMovers.single.exerciseName, 'Bench Press');
      expect(back.recovery!.avgSleepHours, 7.4);
      expect(back.recovery!.recoveryWarnings, ['Quads still recovering']);
      expect(back.recovery!.correlations.single.kind, 'sleep_rpe');
      expect(back.recovery!.correlations.single.sampleSize, 9);
      expect(back.physique!.checkInVerdict, 'on_track');
      expect(back.physique!.bodyweightDeltaKg, -0.3);
      expect(back.tdee!.deltaKcal, 120);
      expect(back.tdee!.material, isTrue);
      // Whole-structure equality as a catch-all.
      expect(back.toJson(), p.toJson());
    });

    test('payload with all sections null round-trips', () {
      final p = _payload();
      final back = WeeklyReportPayload.fromJson(_roundTrip(p));
      expect(back.nutrition, isNull);
      expect(back.training, isNull);
      expect(back.recovery, isNull);
      expect(back.physique, isNull);
      expect(back.tdee, isNull);
      expect(back.hasSignal, isFalse);
      expect(back.hasNarrativeSignal, isFalse);
    });

    test('nullable fields inside sections survive as null', () {
      const n = NutritionSection(
        daysLogged: 1,
        avgKcal: 2000,
        avgProteinG: 100,
        topFoods: [],
      );
      final back = WeeklyReportPayload.fromJson(
        _roundTrip(_payload(nutrition: n)),
      );
      expect(back.nutrition!.targetKcal, isNull);
      expect(back.nutrition!.targetProteinG, isNull);
      expect(back.nutrition!.adherenceDays, isNull);
    });

    test('fromJsonString and tryDecode agree on valid input', () {
      final text = jsonEncode(_payload(nutrition: _nutrition).toJson());
      expect(WeeklyReportPayload.fromJsonString(text).nutrition, isNotNull);
      expect(WeeklyReportPayload.tryDecode(text), isNotNull);
    });
  });

  group('signal getters', () {
    test('tdee-only payload has no signal (D-06)', () {
      final p = _payload(tdee: _tdee);
      expect(p.hasSignal, isFalse);
      expect(p.hasNarrativeSignal, isFalse);
    });

    test('tdee plus any in-window section has signal', () {
      expect(_payload(tdee: _tdee, nutrition: _nutrition).hasSignal, isTrue);
      expect(_payload(tdee: _tdee, training: _training).hasSignal, isTrue);
      expect(_payload(tdee: _tdee, recovery: _recovery).hasSignal, isTrue);
      expect(_payload(tdee: _tdee, physique: _physique).hasSignal, isTrue);
    });

    test('physique-only: signal but no narrative signal', () {
      final p = _payload(physique: _physique);
      expect(p.hasSignal, isTrue);
      expect(p.hasNarrativeSignal, isFalse);
    });

    test('recovery-only: both signals', () {
      final p = _payload(recovery: _recovery);
      expect(p.hasSignal, isTrue);
      expect(p.hasNarrativeSignal, isTrue);
    });

    test('nutrition-only and training-only are narrative signals', () {
      expect(_payload(nutrition: _nutrition).hasNarrativeSignal, isTrue);
      expect(_payload(training: _training).hasNarrativeSignal, isTrue);
    });
  });

  test('week getter equals IsoWeek built from isoYear and isoWeek', () {
    expect(_payload().week, const IsoWeek(2026, 40));
  });

  group('strict parsing', () {
    Map<String, dynamic> valid() => _roundTrip(
      _payload(
        nutrition: _nutrition,
        training: _training,
        recovery: _recovery,
        physique: _physique,
        tdee: _tdee,
      ),
    );

    test('payloadVersion 2 throws FormatException', () {
      final j = valid()..['payloadVersion'] = 2;
      expect(() => WeeklyReportPayload.fromJson(j), throwsFormatException);
    });

    test('missing payloadVersion throws', () {
      final j = valid()..remove('payloadVersion');
      expect(() => WeeklyReportPayload.fromJson(j), throwsFormatException);
    });

    test('missing isoYear throws', () {
      final j = valid()..remove('isoYear');
      expect(() => WeeklyReportPayload.fromJson(j), throwsFormatException);
    });

    test('unparseable windowEnd throws', () {
      final j = valid()..['windowEnd'] = 'not a date';
      expect(() => WeeklyReportPayload.fromJson(j), throwsFormatException);
    });

    test('non-string windowEnd throws', () {
      final j = valid()..['windowEnd'] = 12345;
      expect(() => WeeklyReportPayload.fromJson(j), throwsFormatException);
    });

    test('section with a wrong-typed field throws', () {
      final j = valid();
      (j['nutrition'] as Map<String, dynamic>)['avgKcal'] = 'lots';
      expect(() => WeeklyReportPayload.fromJson(j), throwsFormatException);
    });

    test('section that is not a map throws', () {
      final j = valid()..['training'] = 'oops';
      expect(() => WeeklyReportPayload.fromJson(j), throwsFormatException);
    });

    test('topFoods not a list throws', () {
      final j = valid();
      (j['nutrition'] as Map<String, dynamic>)['topFoods'] = 'Chicken';
      expect(() => WeeklyReportPayload.fromJson(j), throwsFormatException);
    });

    test('topFoods element of wrong type throws', () {
      final j = valid();
      (j['nutrition'] as Map<String, dynamic>)['topFoods'] = [42];
      expect(() => WeeklyReportPayload.fromJson(j), throwsFormatException);
    });

    test('recoveryWarnings with a non-string element throws', () {
      final j = valid();
      (j['recovery'] as Map<String, dynamic>)['recoveryWarnings'] = [1];
      expect(() => WeeklyReportPayload.fromJson(j), throwsFormatException);
    });

    test('fromJsonString on garbage throws FormatException', () {
      expect(
        () => WeeklyReportPayload.fromJsonString('{{{'),
        throwsFormatException,
      );
      expect(
        () => WeeklyReportPayload.fromJsonString('[1,2]'),
        throwsFormatException,
      );
    });

    test('tryDecode returns null on any failure', () {
      expect(WeeklyReportPayload.tryDecode('{{{'), isNull);
      expect(WeeklyReportPayload.tryDecode('[]'), isNull);
      expect(WeeklyReportPayload.tryDecode('{"payloadVersion":9}'), isNull);
    });

    test('ints are accepted where doubles are expected', () {
      final j = valid();
      (j['training'] as Map<String, dynamic>)['tonnageKg'] = 18000;
      (j['recovery'] as Map<String, dynamic>)['avgSleepHours'] = 7;
      final back = WeeklyReportPayload.fromJson(j);
      expect(back.training!.tonnageKg, 18000.0);
      expect(back.recovery!.avgSleepHours, 7.0);
    });

    test('doubles are accepted where ints are expected', () {
      final j = valid();
      (j['nutrition'] as Map<String, dynamic>)['avgKcal'] = 2410.0;
      expect(WeeklyReportPayload.fromJson(j).nutrition!.avgKcal, 2410);
    });
  });
}
