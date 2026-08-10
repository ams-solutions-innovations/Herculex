import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/workouts/domain/exercise_search.dart';

/// Ranking is exercised against the real shipped catalog rather than a
/// handful of fixtures: the failures this replaced (a "curl" query matching
/// 30% of the catalog, "leg curl" returning L-Sit Ring Pull-Up) only appear at
/// full catalog size.
void main() {
  late ExerciseSearchIndex index;
  late Map<int, String> namesById;

  setUpAll(() {
    final raw = File('assets/data/exercises.json').readAsStringSync();
    final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    // The repository indexes the `aka` *column*, which the importer has already
    // extended with the bare movement name for each movement's canonical
    // member. Reading only the JSON `aka` would index something the app never
    // sees — and it is exactly that alias which decides whether "lateral raise"
    // leads with the dumbbell or with whichever variant sorts first.
    final movementLabel = <String, String>{
      for (final m in (jsonDecode(
        File('assets/data/movements.json').readAsStringSync(),
      ) as List)
          .cast<Map<String, dynamic>>())
        m['canonicalExerciseSlug'] as String: m['label'] as String,
    };

    namesById = {};
    final searchable = <SearchableExercise>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final name = row['name'] as String;
      namesById[i] = name;
      final aliases = [
        ...?(row['aka'] as List?)?.cast<String>(),
      ];
      final label = movementLabel[row['slug'] as String?];
      if (label != null &&
          !aliases.any((a) => a.toLowerCase() == label.toLowerCase()) &&
          label.toLowerCase() != name.toLowerCase()) {
        aliases.add(label);
      }
      searchable.add(
        SearchableExercise(
          id: i,
          name: name,
          aliases: aliases,
          equipment: row['equipment'] as String?,
          modality: row['modality'] as String?,
          primaryMuscle: row['primaryMuscle'] as String?,
          // Stabilizers are deliberately omitted, matching how the repository
          // builds the index.
          secondaryMuscles: [
            ...?(row['primaryMuscles'] as List?)?.cast<String>(),
            ...?(row['secondaryMuscles'] as List?)?.cast<String>(),
          ],
        ),
      );
    }
    index = ExerciseSearchIndex.build(searchable);
  });

  List<String> top(String query, {int count = 5, Set<int> recentIds = const {}}) {
    final hits = index.rank(query, recentIds: recentIds);
    return [for (final hit in hits.take(count)) namesById[hit.id]!];
  }

  int hitCount(String query) => index.rank(query).length;

  group('precision', () {
    test('"curl" no longer matches a third of the catalog', () {
      // Was 120 hits, led by Arc Row (Ring) and Assisted Chin-Up Machine.
      expect(hitCount('curl'), lessThan(45));
      expect(
        top('curl'),
        everyElement(contains(RegExp('curl', caseSensitive: false))),
      );
    });

    test('"leg curl" returns only leg curls', () {
      final results = top('leg curl', count: 3);
      expect(results, contains('Seated Leg Curl'));
      expect(results, contains('Lying Leg Curl'));
      expect(results, isNot(contains('L-Sit Ring Pull-Up')));
    });

    test('"lateral raise" does not return calf raises', () {
      final results = top('lateral raise');
      expect(
        results,
        everyElement(contains(RegExp('lateral raise', caseSensitive: false))),
      );
      expect(results, isNot(contains('Single-Leg Standing Calf Raise')));
    });

    test('"hamstring curl" surfaces the hamstring machines', () {
      expect(top('hamstring curl', count: 4), contains('Seated Leg Curl'));
    });
  });

  group('ranking', () {
    /// The top result for each of these was wrong before the ranker existed:
    /// results came back alphabetically, so "push up" led with "Archer
    /// Push-Up" and "squat" with "45-Degree Leg Press".
    test('the best match is first for the queries that used to fail', () {
      const expected = {
        'push up': 'Standard Push-Up',
        'squat': 'Barbell Back Squat',
        'bench press': 'Barbell Bench Press',
        'lateral raise': 'Dumbbell Lateral Raise',
        'deads': 'Conventional Deadlift',
        'bech press': 'Barbell Bench Press',
      };
      expected.forEach((query, want) {
        expect(top(query).first, want, reason: 'query "$query"');
      });
    });

    test('an exact name wins outright', () {
      expect(top('barbell bench press').first, 'Barbell Bench Press');
      expect(top('conventional deadlift').first, 'Conventional Deadlift');
      expect(top('pec deck machine').first, 'Pec Deck Machine');
    });

    test('the base movement outranks its qualified variants', () {
      // "Seated Leg Curl" (3 words) beats "Standing Single Leg Curl" (4).
      final legCurl = top('leg curl', count: 3);
      expect(
        legCurl.indexOf('Seated Leg Curl'),
        lessThan(legCurl.indexOf('Standing Single Leg Curl')),
      );

      final row = top('barbell row', count: 5);
      expect(row.first, 'Barbell Row');
    });

    test('name matches outrank equipment and muscle matches', () {
      final results = top('squat', count: 6);
      // Every top hit is named "squat"; Box Jump and 45-Degree Leg Press used
      // to place here purely on shared muscles.
      expect(
        results,
        everyElement(contains(RegExp('squat', caseSensitive: false))),
      );
    });

    test('hyphens, spacing and plurals all normalize together', () {
      for (final query in ['push-up', 'push up', 'pushup', 'push ups']) {
        expect(
          top(query, count: 8),
          contains('Standard Push-Up'),
          reason: 'query "$query" should find the plain push-up',
        );
      }
    });

    test('an alias resolves to its canonical exercise', () {
      expect(top('deads').first, 'Conventional Deadlift');
    });
  });

  group('typo tolerance', () {
    test('a single transposed or wrong letter still finds the exercise', () {
      expect(top('bech press', count: 8), contains('Barbell Bench Press'));
      expect(top('deadlfit', count: 5), contains('Conventional Deadlift'));
    });

    test('a typo lands you in the right movement family', () {
      // Every same-family exercise scores identically on a fuzzy hit — there
      // is no lexical signal ranking one squat above another — so the
      // guarantee is the family, not a specific member.
      expect(
        top('sqaut', count: 8),
        everyElement(contains(RegExp('squat', caseSensitive: false))),
      );
      expect(
        top('lat pulldwn', count: 5),
        everyElement(contains(RegExp('pulldown', caseSensitive: false))),
      );
    });

    test('nonsense returns nothing rather than everything', () {
      expect(index.rank('zzzqqqxyw'), isEmpty);
    });
  });

  group('behaviour', () {
    test('an empty or whitespace query yields no hits', () {
      expect(index.rank(''), isEmpty);
      expect(index.rank('   '), isEmpty);
    });

    test('recency breaks ties without outranking a real match', () {
      final declineId = namesById.entries
          .firstWhere((e) => e.value == 'Decline Push-Up')
          .key;

      // Marking an unrelated-ish exercise recent must not displace the
      // exercise the query actually names.
      final withRecent = top('barbell bench press', recentIds: {declineId});
      expect(withRecent.first, 'Barbell Bench Press');
    });

    test('ordering is deterministic across identical calls', () {
      expect(top('row', count: 10), equals(top('row', count: 10)));
    });
  });
}
