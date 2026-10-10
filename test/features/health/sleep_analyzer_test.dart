import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/health/domain/sleep_analyzer.dart';
import 'package:herculex/features/health/domain/sleep_summary.dart';

/// Minutes after 2026-08-12 23:00 — the night under test runs 23:00–07:00.
DateTime _t(int minutes) =>
    DateTime(2026, 8, 12, 23).add(Duration(minutes: minutes));

SleepInterval _iv(
  SleepStage stage,
  int fromMin,
  int toMin, {
  String source = 'watch',
}) => SleepInterval(
  stage: stage,
  from: _t(fromMin),
  to: _t(toMin),
  source: source,
);

/// A Samsung-style night: 8h session, 40 min awake, 7h20 asleep.
///
///   0–20 awake · 20–120 light · 120–180 deep · 180–240 light · 240–250 awake
///   250–310 REM · 310–470 light · 470–480 awake
List<SleepInterval> _stagedNight({String source = 'watch'}) => [
  _iv(SleepStage.inBed, 0, 480, source: source),
  _iv(SleepStage.awake, 0, 20, source: source),
  _iv(SleepStage.light, 20, 120, source: source),
  _iv(SleepStage.deep, 120, 180, source: source),
  _iv(SleepStage.light, 180, 240, source: source),
  _iv(SleepStage.awake, 240, 250, source: source),
  _iv(SleepStage.rem, 250, 310, source: source),
  _iv(SleepStage.light, 310, 470, source: source),
  _iv(SleepStage.awake, 470, 480, source: source),
];

void main() {
  group('SleepAnalyzer', () {
    test('no intervals, or only empty ones, is no sleep', () {
      expect(SleepAnalyzer.summarize(const []), isNull);
      expect(SleepAnalyzer.summarize([_iv(SleepStage.light, 60, 60)]), isNull);
    });

    test('actual sleep excludes the awake time inside the session', () {
      final s = SleepAnalyzer.summarize(_stagedNight())!;

      expect(s.inBedMinutes, 480);
      expect(s.asleepMinutes, 440);
      expect(s.awakeMinutes, 40);
      expect(s.lightMinutes, 320);
      expect(s.deepMinutes, 60);
      expect(s.remMinutes, 60);
      expect(s.hasStages, isTrue);
      expect(s.efficiency, closeTo(440 / 480, 1e-9));
    });

    test('awakenings count only awake periods between sleep onset and the '
        'final wake-up', () {
      final s = SleepAnalyzer.summarize(_stagedNight())!;

      // 0–20 is falling asleep and 470–480 is waking up; only 240–250 is a
      // mid-night awakening.
      expect(s.awakenings, 1);
    });

    test('back-to-back awake stages are one awakening', () {
      final s = SleepAnalyzer.summarize([
        _iv(SleepStage.light, 0, 120),
        _iv(SleepStage.awake, 120, 130),
        _iv(SleepStage.awake, 130, 140),
        _iv(SleepStage.light, 140, 300),
      ])!;

      expect(s.awakenings, 1);
    });

    test('a bare session with no stages falls back to its length', () {
      final s = SleepAnalyzer.summarize([_iv(SleepStage.inBed, 0, 480)])!;

      expect(s.asleepMinutes, 480);
      expect(s.inBedMinutes, 480);
      expect(s.hasStages, isFalse);
      expect(s.deepMinutes, isNull);
      expect(s.remMinutes, isNull);
      expect(s.awakenings, isNull);
    });

    test('unstaged sleep counts what was slept, not the whole session', () {
      final s = SleepAnalyzer.summarize([
        _iv(SleepStage.inBed, 0, 480),
        _iv(SleepStage.asleep, 30, 450),
      ])!;

      expect(s.asleepMinutes, 420);
      expect(s.inBedMinutes, 480);
      expect(s.hasStages, isFalse);
    });

    test(
      'a watch and a phone logging the same night are not added together',
      () {
        final s = SleepAnalyzer.summarize([
          ..._stagedNight(source: 'watch'),
          _iv(SleepStage.inBed, -10, 490, source: 'phone'),
        ])!;

        expect(s.asleepMinutes, 440);
        expect(s.deepMinutes, 60);
      },
    );

    test('staged data beats a longer bare session from another source', () {
      final s = SleepAnalyzer.summarize([
        ..._stagedNight(source: 'watch'),
        _iv(SleepStage.inBed, -60, 540, source: 'phone'),
      ])!;

      expect(s.asleepMinutes, 440, reason: 'not the phone\'s 600');
      expect(s.hasStages, isTrue);
    });

    test('a night plus an afternoon nap adds up', () {
      final s = SleepAnalyzer.summarize([
        ..._stagedNight(),
        // A 40 minute nap, hours after waking.
        _iv(SleepStage.asleep, 900, 940),
      ])!;

      expect(s.asleepMinutes, 480);
      expect(s.deepMinutes, 60, reason: 'the nap has no stages to add');
    });

    test('a short break inside the night does not split it into a nap', () {
      final s = SleepAnalyzer.summarize([
        _iv(SleepStage.light, 0, 200),
        _iv(SleepStage.light, 230, 480),
      ])!;

      expect(s.asleepMinutes, 450);
      // One block: in-bed spans the break rather than counting two sessions.
      expect(s.inBedMinutes, 480);
    });

    test('time in bed is never less than time asleep plus awake', () {
      // Stages overrun a session record that stops short.
      final s = SleepAnalyzer.summarize([
        _iv(SleepStage.inBed, 0, 300),
        _iv(SleepStage.light, 0, 360),
      ])!;

      expect(s.inBedMinutes, greaterThanOrEqualTo(s.asleepMinutes));
    });
  });

  group('SleepSummary persistence', () {
    test('round-trips through health_samples rows', () {
      final night = SleepAnalyzer.summarize(_stagedNight())!;

      final back = SleepSummary.fromSamples(night.toSamples())!;

      expect(back.asleepMinutes, closeTo(night.asleepMinutes, 1e-9));
      expect(back.inBedMinutes, closeTo(night.inBedMinutes, 1e-9));
      expect(back.deepMinutes, closeTo(60, 1e-9));
      expect(back.remMinutes, closeTo(60, 1e-9));
      expect(back.awakenings, 1);
    });

    test('a stage-less night writes no stage rows', () {
      final night = SleepAnalyzer.summarize([_iv(SleepStage.inBed, 0, 480)])!;

      final rows = night.toSamples();

      expect(rows.keys, isNot(contains(SleepSummary.kindDeepMinutes)));
      expect(rows.keys, isNot(contains(SleepSummary.kindRemMinutes)));
      expect(SleepSummary.fromSamples(rows)!.hasStages, isFalse);
    });

    test('a legacy sleep_hours-only row reads back as a stage-less night', () {
      final s = SleepSummary.fromSamples({'sleep_hours': 7.5})!;

      expect(s.asleepHours, 7.5);
      expect(s.inBedHours, 7.5);
      expect(s.hasStages, isFalse);
    });

    test('no sleep_hours row is no night', () {
      expect(SleepSummary.fromSamples({'sleep_deep_min': 60}), isNull);
      expect(SleepSummary.fromSamples({'sleep_hours': 0}), isNull);
    });

    test('latestFromSamples takes the newest date that has a night', () {
      final s = SleepSummary.latestFromSamples([
        (dateIso: '2026-08-11', kind: 'sleep_hours', value: 6.0),
        (dateIso: '2026-08-12', kind: 'sleep_hours', value: 8.0),
        (dateIso: '2026-08-12', kind: 'sleep_deep_min', value: 70),
        // Newest date but no sleep_hours row — not a night, skipped.
        (dateIso: '2026-08-13', kind: 'sleep_deep_min', value: 30),
      ]);

      expect(s!.asleepHours, 8.0);
      expect(s.deepMinutes, 70);
    });

    test('latestFromSamples is null with no rows', () {
      expect(SleepSummary.latestFromSamples(const []), isNull);
    });
  });
}
