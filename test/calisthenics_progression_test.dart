import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workouts/domain/calisthenics_progression.dart';

void main() {
  final now = DateTime(2026, 10, 14, 12);
  final pull = calisthenicsPathFor('pull-up')!;
  CalisthenicsPerformance performance(
    int id, {
    String key = 'pull-up:bodyweight',
    int value = 8,
    int count = 3,
    int? rpe,
    double load = 0,
    String band = '',
    bool standard = true,
    int daysAgo = 0,
  }) => CalisthenicsPerformance(
    sessionId: id,
    at: now.subtract(Duration(days: daysAgo)),
    levelKey: key,
    sets: List.generate(
      count,
      (_) => CalisthenicsSet(
        value: value,
        rpe: rpe,
        load: load,
        assistance: band,
        standard: standard,
      ),
    ),
  );
  CalisthenicsRecommendation recommend(
    List<CalisthenicsPerformance> history, [
    CalisthenicsPath? path,
  ]) => CalisthenicsProgression.recommend(path ?? pull, history, now);

  test('all authored slugs exist and weighted levels support added load', () {
    final catalog =
        (jsonDecode(File('assets/data/exercises.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
    final bySlug = {for (final row in catalog) row['slug']: row};
    for (final path in calisthenicsPaths) {
      for (final slug in path.slugs) {
        expect(bySlug.containsKey(slug), true, reason: slug);
      }
      for (final level in path.levels) {
        if (level.variant == 'weighted') {
          expect(
            bySlug[level.slug]!['supportsWeightedBodyweight'],
            true,
            reason: level.key,
          );
        }
        expect(
          bySlug[level.slug]!['loggingMetric'],
          level.seconds
              ? 'time'
              : level.variant == 'machine_selectorized'
              ? 'weight_reps'
              : 'reps',
        );
      }
    }
  });
  test('fresh users start at minimum with no inferred readiness', () {
    final result = recommend([]);
    expect(result.value, 5);
    expect(result.target.variant, 'band');
    expect(result.ready, false);
  });
  test('all three sets twice unlock weighted with a small starting load', () {
    final result = recommend([performance(1, daysAgo: 2), performance(2)]);
    expect(result.ready, true);
    expect(result.target.variant, 'weighted');
    expect(result.load, 1.25);
    expect(result.value, 5);
  });
  test('one good set, warmups, partials and high RPE cannot unlock', () {
    for (final bad in [
      performance(2, count: 1),
      performance(2, standard: false),
      performance(2, rpe: 90),
      performance(2, value: 7),
    ]) {
      expect(recommend([performance(1, daysAgo: 2), bad]).ready, false);
    }
  });
  test('same session or less than 24 hours is not repeat success', () {
    expect(
      recommend([performance(1, daysAgo: 2), performance(1)]).ready,
      false,
    );
    final first = performance(1);
    final earlier = CalisthenicsPerformance(
      sessionId: 2,
      at: now.subtract(const Duration(hours: 23)),
      levelKey: first.levelKey,
      sets: first.sets,
    );
    expect(recommend([first, earlier]).ready, false);
  });
  test('failed most recent session blocks older successes', () {
    expect(
      recommend([
        performance(1, daysAgo: 4),
        performance(2, daysAgo: 2),
        performance(3, value: 4),
      ]).ready,
      false,
    );
  });
  test('stale and future sessions cannot qualify', () {
    expect(
      recommend([performance(1, daysAgo: 43), performance(2)]).ready,
      false,
    );
    expect(
      recommend([performance(1, daysAgo: -2), performance(2)]).ready,
      false,
    );
  });
  test(
    'assistance must be explicitly logged, matching, and assistance mode',
    () {
      final first = performance(
        1,
        key: 'pull-up:band',
        band: '1:1:assistance',
        daysAgo: 2,
      );
      for (final band in ['', '2:1:assistance', '1:1:resistance']) {
        expect(
          recommend([
            first,
            performance(2, key: 'pull-up:band', band: band),
          ]).ready,
          false,
        );
      }
      expect(
        recommend([
          first,
          performance(2, key: 'pull-up:band', band: '1:1:assistance'),
        ]).ready,
        true,
      );
      expect(
        recommend([
          performance(1, band: '1:1:assistance', daysAgo: 2),
          performance(2, band: '1:1:assistance'),
        ]).ready,
        false,
      );
    },
  );
  test('weighted progress compares matching load across sessions', () {
    final first = performance(1, key: 'pull-up:weighted', load: 10, daysAgo: 2);
    final result = recommend([
      first,
      performance(2, key: 'pull-up:weighted', load: 10),
    ]);
    expect(result.load, 11.25);
    expect(result.value, 5);
    expect(result.ready, false);
    expect(
      recommend([
        first,
        performance(2, key: 'pull-up:weighted', load: 12),
      ]).load,
      12,
    );
  });
  test('kipping and rings never unlock bar strict levels', () {
    final path = calisthenicsPathFor('strict-muscle-up')!;
    expect(calisthenicsPathFor('kipping-muscle-up')!.id, path.id);
    expect(calisthenicsPathFor('ring-muscle-up')!.id, isNot(path.id));
    for (final key in [
      'kipping-muscle-up:bodyweight',
      'ring-muscle-up:bodyweight',
    ]) {
      expect(
        recommend([
          performance(1, key: key, daysAgo: 2),
          performance(2, key: key),
        ], path).ready,
        false,
      );
    }
  });
  test('muscle-up needs strict foundations as well as assisted success', () {
    final path = calisthenicsPathFor('strict-muscle-up')!;
    final history = [
      performance(
        1,
        key: 'strict-muscle-up:band',
        band: '1:1:assistance',
        daysAgo: 2,
      ),
      performance(2, key: 'strict-muscle-up:band', band: '1:1:assistance'),
    ];
    expect(recommend(history, path).ready, false);
    history.addAll([
      performance(3, daysAgo: 3, value: 5),
      performance(4, key: 'chest-dips:bodyweight', value: 5, daysAgo: 3),
    ]);
    expect(recommend(history, path).ready, true);
  });
  test('holds progress seconds and cap duration rather than adding reps', () {
    final path = calisthenicsPathFor('l-sit-floor')!;
    final result = recommend([
      performance(1, key: 'l-sit-floor:bodyweight', value: 10),
    ], path);
    expect(result.target.seconds, true);
    expect(result.value, 12);
    expect(
      recommend([
        performance(1, key: 'l-sit-floor:bodyweight', value: 50),
      ], path).value,
      20,
    );
  });
}
