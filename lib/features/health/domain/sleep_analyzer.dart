import 'package:herculex/features/health/domain/sleep_summary.dart';

/// Platform-neutral sleep stage. Health Connect and HealthKit name and split
/// these differently; the data layer maps both onto this.
enum SleepStage {
  /// Asleep with no staging (Health Connect "sleeping", HealthKit "asleep").
  asleep,
  light,
  deep,
  rem,

  /// Awake, awake-in-bed or out of bed — all time not asleep inside a session.
  awake,

  /// A whole-session / in-bed span with no sleep claim (Health Connect's
  /// session record, HealthKit's in-bed). Defines when the night started and
  /// ended, never counts as sleep.
  inBed,
}

class SleepInterval {
  const SleepInterval({
    required this.stage,
    required this.from,
    required this.to,
    required this.source,
  });

  final SleepStage stage;
  final DateTime from;
  final DateTime to;

  /// Data origin (app package or device) — two sources describing the same
  /// night must not be added together.
  final String source;

  double get minutes => to.difference(from).inSeconds / 60.0;
}

/// Reduces raw sleep intervals from one or more sources to a [SleepSummary].
///
/// The naive reading — union every sleep interval — counted awake time inside
/// the session as sleep and double-counted when a watch and a phone both
/// logged the same night. This does it in three steps:
///
///  1. per source, split intervals into blocks (a night, a nap) wherever there
///     is a gap longer than [blockGap];
///  2. blocks from different sources that overlap in time are the same sleep —
///     keep only the richest source for each (stages beat a bare session);
///  3. sum what is left, so a night plus a nap still adds up.
abstract final class SleepAnalyzer {
  /// A silence longer than this starts a new block (e.g. a nap). Shorter
  /// breaks — a toilet trip a device logged as a second session — stay inside
  /// the night.
  static const blockGap = Duration(minutes: 45);

  /// Awake periods closer together than this count as one awakening.
  static const _awakeningMerge = Duration(minutes: 1);

  static SleepSummary? summarize(Iterable<SleepInterval> intervals) {
    final bySource = <String, List<SleepInterval>>{};
    for (final i in intervals) {
      if (!i.to.isAfter(i.from)) continue;
      bySource.putIfAbsent(i.source, () => []).add(i);
    }
    if (bySource.isEmpty) return null;

    final blocks = <_Block>[
      for (final e in bySource.entries) ..._blocksFor(e.key, e.value),
    ]..sort((a, b) => a.start.compareTo(b.start));

    // Overlapping blocks (any source) are one episode of sleep.
    final episodes = <List<_Block>>[];
    DateTime? episodeEnd;
    for (final block in blocks) {
      if (episodeEnd == null || !block.start.isBefore(episodeEnd)) {
        episodes.add([block]);
        episodeEnd = block.end;
      } else {
        episodes.last.add(block);
        if (block.end.isAfter(episodeEnd)) episodeEnd = block.end;
      }
    }

    var inBed = 0.0, asleep = 0.0, awake = 0.0;
    var light = 0.0, deep = 0.0, rem = 0.0;
    var awakenings = 0;
    var staged = false;
    for (final episode in episodes) {
      final best = _richestSource(episode);
      inBed += best.inBed;
      asleep += best.asleep;
      awake += best.awake;
      if (best.quality == _Quality.staged) {
        staged = true;
        light += best.light;
        deep += best.deep;
        rem += best.rem;
        awakenings += best.awakenings;
      }
    }
    if (asleep <= 0) return null;

    return SleepSummary(
      inBedMinutes: inBed,
      asleepMinutes: asleep,
      awakeMinutes: awake,
      lightMinutes: staged ? light : null,
      deepMinutes: staged ? deep : null,
      remMinutes: staged ? rem : null,
      awakenings: staged ? awakenings : null,
    );
  }

  static List<_Block> _blocksFor(String source, List<SleepInterval> all) {
    final sorted = [...all]..sort((a, b) => a.from.compareTo(b.from));
    final blocks = <_Block>[];
    _Block? current;
    for (final i in sorted) {
      if (current == null || i.from.difference(current.end) > blockGap) {
        current = _Block(source)..add(i);
        blocks.add(current);
      } else {
        current.add(i);
      }
    }
    return blocks;
  }

  /// Per source in the episode, total its blocks; keep the best by data
  /// quality, then by how much sleep it found.
  static _Tally _richestSource(List<_Block> episode) {
    final bySource = <String, _Tally>{};
    for (final block in episode) {
      bySource.update(
        block.source,
        (t) => t + block.tally(),
        ifAbsent: block.tally,
      );
    }
    return bySource.values.reduce((a, b) {
      final byQuality = a.quality.index.compareTo(b.quality.index);
      if (byQuality != 0) return byQuality > 0 ? a : b;
      return a.asleep >= b.asleep ? a : b;
    });
  }
}

/// How much a source told us, best last.
enum _Quality { sessionOnly, unstaged, staged }

class _Block {
  _Block(this.source);

  final String source;
  final _intervals = <SleepInterval>[];
  late DateTime start;
  late DateTime end;

  void add(SleepInterval i) {
    if (_intervals.isEmpty) {
      start = i.from;
      end = i.to;
    } else {
      if (i.from.isBefore(start)) start = i.from;
      if (i.to.isAfter(end)) end = i.to;
    }
    _intervals.add(i);
  }

  _Tally tally() {
    var light = 0.0, deep = 0.0, rem = 0.0, unstaged = 0.0, awake = 0.0;
    final awakeIntervals = <SleepInterval>[];
    DateTime? firstAsleep, lastAsleep;
    for (final i in _intervals) {
      switch (i.stage) {
        case SleepStage.light:
          light += i.minutes;
        case SleepStage.deep:
          deep += i.minutes;
        case SleepStage.rem:
          rem += i.minutes;
        case SleepStage.asleep:
          unstaged += i.minutes;
        case SleepStage.awake:
          awake += i.minutes;
          awakeIntervals.add(i);
        case SleepStage.inBed:
          break;
      }
      if (i.stage
          case SleepStage.light ||
              SleepStage.deep ||
              SleepStage.rem ||
              SleepStage.asleep) {
        if (firstAsleep == null || i.from.isBefore(firstAsleep)) {
          firstAsleep = i.from;
        }
        if (lastAsleep == null || i.to.isAfter(lastAsleep)) lastAsleep = i.to;
      }
    }

    final span = end.difference(start).inSeconds / 60.0;
    final staged = light + deep + rem;
    final asleepFromStages = staged + unstaged;
    final quality = staged > 0
        ? _Quality.staged
        : (unstaged > 0 ? _Quality.unstaged : _Quality.sessionOnly);

    // A bare session carries no staging, so its length is the best estimate of
    // sleep we have; otherwise trust the stages over the span.
    final asleep = quality == _Quality.sessionOnly ? span : asleepFromStages;
    final awakeMinutes = quality == _Quality.sessionOnly ? 0.0 : awake;

    return _Tally(
      quality: quality,
      inBed: span > asleep + awakeMinutes ? span : asleep + awakeMinutes,
      asleep: asleep,
      awake: awakeMinutes,
      light: light,
      deep: deep,
      rem: rem,
      awakenings: quality == _Quality.staged
          ? _countAwakenings(awakeIntervals, firstAsleep, lastAsleep)
          : 0,
    );
  }

  /// Awake periods strictly between first falling asleep and the last stage of
  /// sleep. Awake time before sleep onset or after the final wake-up is not an
  /// awakening.
  static int _countAwakenings(
    List<SleepInterval> awake,
    DateTime? firstAsleep,
    DateTime? lastAsleep,
  ) {
    if (firstAsleep == null || lastAsleep == null) return 0;
    final sorted = [...awake]..sort((a, b) => a.from.compareTo(b.from));
    var count = 0;
    DateTime? mergedEnd;
    for (final i in sorted) {
      final startsNewPeriod =
          mergedEnd == null ||
          i.from.difference(mergedEnd) > SleepAnalyzer._awakeningMerge;
      if (startsNewPeriod &&
          i.from.isAfter(firstAsleep) &&
          i.to.isBefore(lastAsleep)) {
        count++;
      }
      if (mergedEnd == null || i.to.isAfter(mergedEnd)) mergedEnd = i.to;
    }
    return count;
  }
}

class _Tally {
  const _Tally({
    required this.quality,
    required this.inBed,
    required this.asleep,
    required this.awake,
    required this.light,
    required this.deep,
    required this.rem,
    required this.awakenings,
  });

  final _Quality quality;
  final double inBed, asleep, awake, light, deep, rem;
  final int awakenings;

  _Tally operator +(_Tally o) => _Tally(
    quality: quality.index >= o.quality.index ? quality : o.quality,
    inBed: inBed + o.inBed,
    asleep: asleep + o.asleep,
    awake: awake + o.awake,
    light: light + o.light,
    deep: deep + o.deep,
    rem: rem + o.rem,
    awakenings: awakenings + o.awakenings,
  );
}
