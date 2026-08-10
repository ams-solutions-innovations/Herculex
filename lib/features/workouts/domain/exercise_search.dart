/// Relevance ranking for the exercise picker.
///
/// Replaces the previous boolean substring filter, which returned matches in
/// alphabetical order — so typing "push up" led with "Archer Push-Up" and
/// buried "Standard Push-Up" thirty rows down, and typing "curl" matched 30%
/// of the catalog.
///
/// Pure Dart on purpose: no Drift, no Flutter. The whole ranker is unit
/// testable without a database. The caller supplies plain [SearchableExercise]
/// records, so [WorkoutsRepository] owns the Drift → domain mapping.
library;

/// One catalog row flattened into the fields ranking actually looks at.
class SearchableExercise {
  final int id;
  final String name;

  /// Alternate names (the catalog's `aka` list, plus any movement-level bare
  /// name). Matched almost as strongly as [name].
  final List<String> aliases;

  final String? equipment;
  final String? modality;
  final String? primaryMuscle;

  /// Non-stabilizer muscles. Stabilizers are deliberately excluded — matching
  /// them is what made "curl" return every pulling exercise.
  final List<String> secondaryMuscles;

  const SearchableExercise({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.equipment,
    this.modality,
    this.primaryMuscle,
    this.secondaryMuscles = const [],
  });
}

/// A ranked hit. [score] is only meaningful relative to other hits for the
/// same query.
class ExerciseSearchHit {
  final int id;
  final int score;
  const ExerciseSearchHit(this.id, this.score);
}

/// Prebuilt, immutable index over the catalog. Build once per catalog load and
/// call [rank] per keystroke; ranking allocates nothing per exercise beyond
/// the result list.
class ExerciseSearchIndex {
  final List<_IndexedExercise> _entries;

  const ExerciseSearchIndex._(this._entries);

  factory ExerciseSearchIndex.build(Iterable<SearchableExercise> exercises) {
    return ExerciseSearchIndex._([
      for (final e in exercises) _IndexedExercise.from(e),
    ]);
  }

  /// Hits for [query], best first. Empty query returns nothing — the caller
  /// shows the browse list in that case.
  ///
  /// [recentIds] nudges recently logged exercises up, but by far less than any
  /// name signal, so it can break ties without ever outranking a real match.
  List<ExerciseSearchHit> rank(String query, {Set<int> recentIds = const {}}) {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) return const [];
    final normalizedQuery = tokens.join(' ');
    final compactQuery = tokens.join();

    final scored = <_ScoredEntry>[];
    for (final entry in _entries) {
      final score = entry.score(tokens, normalizedQuery, compactQuery);
      if (score < _scoreFloor) continue;
      scored.add(
        _ScoredEntry(
          entry,
          score + (recentIds.contains(entry.id) ? _recentBonus : 0),
        ),
      );
    }
    // Deterministic ordering: score, then the shorter (less qualified) name,
    // then alphabetical. List.sort is not stable, so ties must be total or
    // results shuffle between keystrokes.
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byLength = a.entry.name.length.compareTo(b.entry.name.length);
      if (byLength != 0) return byLength;
      return a.entry.name.compareTo(b.entry.name);
    });
    return [for (final s in scored) ExerciseSearchHit(s.entry.id, s.score)];
  }

  /// Below this, a "match" is a single weak metadata signal and is noise.
  static const _scoreFloor = 40;
  static const _recentBonus = 25;
}

/// An entry paired with its score, kept together only for the sort.
class _ScoredEntry {
  final _IndexedExercise entry;
  final int score;
  const _ScoredEntry(this.entry, this.score);
}

// ── Scoring ────────────────────────────────────────────────────────────────

// Exact tiers sit an order of magnitude above the additive signals below, so
// no accumulation of partial matches can outrank something the user typed
// verbatim. Without the gap, "deads" ranked "Dead Bug" (name-prefix + word +
// all-tokens) above "Conventional Deadlift", whose alias is literally "Deads".
const _scoreNameExact = 10000;
const _scoreAliasExact = 9000;

const _scoreNamePrefix = 600;
const _scoreAllTokensInName = 400;
const _scoreNameWordPrefix = 300;
const _scoreAliasContains = 200;

// A typo against the name beats the same typo against an alias, mirroring how
// exact name matches outrank alias matches at every other tier. Without the
// split, "bech press" ranked Guillotine Press (aliased "Neck Press (Bench)")
// above Barbell Bench Press.
const _scoreFuzzyNameWord = 150;
const _scoreFuzzyAliasWord = 100;
const _scoreEquipment = 60;
const _scorePrimaryMuscle = 40;
const _scoreSecondaryMuscle = 15;

/// Charged per name word the query did not account for. This is what surfaces
/// base movements: for "leg curl", "Seated Leg Curl" (3 words) outranks
/// "Standing Single Leg Curl" (4 words).
const _penaltyExtraWord = 8;

/// Words that mark an exercise as the plain version of its movement rather
/// than a qualified variant. Purely lexically, "Standard Push-Up" and "Clap
/// Push-Up" are indistinguishable for the query "push up" — both are
/// three-word names matching two tokens. These words are the signal that
/// breaks that tie, and they carry the same meaning across the catalog.
const _canonicalMarkers = <String>{
  'standard',
  'conventional',
  'regular',
  'basic',
  'classic',
  'traditional',
};

/// Small enough to only break ties between otherwise equal matches, never to
/// promote an exercise the query did not really name.
const _scoreCanonicalMarker = 50;

class _IndexedExercise {
  final int id;
  final String name; // normalized, space-joined
  final String nameCompact; // normalized, no spaces
  final List<String> nameWords;
  final List<String> aliases; // normalized
  final List<String> aliasCompacts;
  final List<String> aliasWords; // flattened, for per-token matching
  final List<String> metaTokens; // equipment + modality words
  final List<String> primaryMuscleTokens;
  final List<String> secondaryMuscleTokens;

  /// How many of [nameWords] are canonical markers ("Standard", …).
  final int canonicalMarkers;

  const _IndexedExercise({
    required this.id,
    required this.name,
    required this.nameCompact,
    required this.nameWords,
    required this.aliases,
    required this.aliasCompacts,
    required this.aliasWords,
    required this.metaTokens,
    required this.primaryMuscleTokens,
    required this.secondaryMuscleTokens,
    required this.canonicalMarkers,
  });

  factory _IndexedExercise.from(SearchableExercise e) {
    final nameWords = _tokenize(e.name);
    final aliases = <String>[];
    for (final alias in e.aliases) {
      final normalized = _tokenize(alias).join(' ');
      if (normalized.isNotEmpty) aliases.add(normalized);
    }
    return _IndexedExercise(
      id: e.id,
      name: nameWords.join(' '),
      nameCompact: nameWords.join(),
      nameWords: nameWords,
      aliases: aliases,
      aliasCompacts: [for (final a in aliases) a.replaceAll(' ', '')],
      aliasWords: [for (final a in aliases) ...a.split(' ')],
      metaTokens: [..._tokenize(e.equipment), ..._tokenize(e.modality)],
      primaryMuscleTokens: _tokenize(e.primaryMuscle),
      secondaryMuscleTokens: [
        for (final m in e.secondaryMuscles) ..._tokenize(m),
      ],
      canonicalMarkers: nameWords.where(_canonicalMarkers.contains).length,
    );
  }

  int score(List<String> tokens, String normalizedQuery, String compactQuery) {
    // Whole-query signals first; they dominate and short-circuit the rest.
    if (name == normalizedQuery || nameCompact == compactQuery) {
      return _scoreNameExact;
    }
    for (var i = 0; i < aliases.length; i++) {
      if (aliases[i] == normalizedQuery || aliasCompacts[i] == compactQuery) {
        return _scoreAliasExact;
      }
    }

    var total = 0;
    if (name.startsWith(normalizedQuery) ||
        nameCompact.startsWith(compactQuery)) {
      total += _scoreNamePrefix;
    }

    var matchedNameWords = 0;
    var tokensFoundInName = 0;
    for (final token in tokens) {
      var hit = false;
      for (final word in nameWords) {
        if (word == token || word.startsWith(token)) {
          hit = true;
          break;
        }
      }
      if (hit) {
        tokensFoundInName++;
        matchedNameWords++;
        total += _scoreNameWordPrefix;
        continue;
      }

      // Metadata is worth far less than the name, and only counts once per
      // token so a multi-word query can't stack its way past a name match.
      if (_containsToken(primaryMuscleTokens, token)) {
        total += _scorePrimaryMuscle;
        continue;
      }
      if (_containsToken(metaTokens, token)) {
        total += _scoreEquipment;
        continue;
      }
      if (_containsToken(secondaryMuscleTokens, token)) {
        total += _scoreSecondaryMuscle;
        continue;
      }
      if (_containsToken(aliasWords, token)) {
        total += _scoreAliasContains;
        continue;
      }
      // Last resort: tolerate a typo against name/alias words only. A fuzzy
      // hit still counts as the token being found, so multi-word typo queries
      // earn the all-tokens bonus — but only a hit on the *name* suppresses
      // that word's length penalty.
      if (_fuzzyMatchesWord(nameWords, token)) {
        tokensFoundInName++;
        matchedNameWords++;
        total += _scoreFuzzyNameWord;
      } else if (_fuzzyMatchesWord(aliasWords, token)) {
        tokensFoundInName++;
        total += _scoreFuzzyAliasWord;
      }
    }

    if (tokensFoundInName == tokens.length) total += _scoreAllTokensInName;

    // Only penalise length once the query actually engaged the name; otherwise
    // a pure metadata hit would be punished for the exercise having a long
    // name, which has nothing to do with relevance. A canonical marker
    // ("Standard", "Conventional") is not a qualifier, so it is not counted
    // as an extra word.
    if (matchedNameWords > 0) {
      final unmatched = nameWords.length - matchedNameWords - canonicalMarkers;
      if (unmatched > 0) total -= unmatched * _penaltyExtraWord;
    }
    if (total > 0 && canonicalMarkers > 0) total += _scoreCanonicalMarker;
    return total;
  }

  /// Short tokens get one edit of slack, longer ones two — a single wrong
  /// letter in a four-letter word is a much bigger proportional change.
  static bool _fuzzyMatchesWord(List<String> words, String token) {
    final maxDist = token.length <= 5 ? 1 : 2;
    for (final word in words) {
      if (_withinEditDistance(word, token, maxDist)) return true;
    }
    return false;
  }

  static bool _containsToken(List<String> haystack, String token) {
    for (final value in haystack) {
      if (value == token || value.startsWith(token)) return true;
    }
    return false;
  }
}

// ── Text normalization ─────────────────────────────────────────────────────

/// Lowercases, folds the accents that appear in the catalog and in Slovenian
/// keyboards, strips punctuation, and singularizes. "Push-Up", "push up" and
/// "push ups" all reduce to `[push, up]`.
List<String> _tokenize(String? value) {
  if (value == null || value.isEmpty) return const [];
  final lower = value
      .toLowerCase()
      .replaceAll('š', 's')
      .replaceAll('č', 'c')
      .replaceAll('ć', 'c')
      .replaceAll('ž', 'z')
      .replaceAll('đ', 'd');
  final spaced = lower
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  if (spaced.isEmpty) return const [];
  return [
    for (final word in spaced.split(RegExp(r'\s+')))
      if (word.isNotEmpty) _singularize(word),
  ];
}

String _singularize(String word) {
  if (word == 'abs') return word;
  if (word.length > 4 && word.endsWith('ies')) {
    return '${word.substring(0, word.length - 3)}y';
  }
  for (final suffix in const ['ches', 'shes', 'xes', 'ses']) {
    if (word.length > 4 && word.endsWith(suffix)) {
      return word.substring(0, word.length - 2);
    }
  }
  if (word.length > 3 && word.endsWith('s') && !word.endsWith('ss')) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

/// Damerau-Levenshtein with an early exit once every cell in a row provably
/// exceeds [maxDist], so the common no-match case costs almost nothing.
///
/// Hand-rolled rather than pulled from a package because the available Dart
/// options return whole-string similarity, which cannot express the per-field
/// weighting above. Operands are single words (≤ ~15 chars), so the full DP is
/// a couple hundred cells at worst and is not worth banding.
bool _withinEditDistance(String a, String b, int maxDist) {
  if (a == b) return true;
  if ((a.length - b.length).abs() > maxDist) return false;
  if (a.isEmpty || b.isEmpty) return a.length + b.length <= maxDist;

  // Three rolling rows: i-2 (for transpositions), i-1, and the row being built.
  var twoBack = List<int>.filled(b.length + 1, 0);
  var oneBack = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    var rowMin = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var value = _min3(
        current[j - 1] + 1, // insertion
        oneBack[j] + 1, // deletion
        oneBack[j - 1] + cost, // substitution
      );
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        final transposed = twoBack[j - 2] + 1;
        if (transposed < value) value = transposed;
      }
      current[j] = value;
      if (value < rowMin) rowMin = value;
    }
    if (rowMin > maxDist) return false;

    final recycled = twoBack;
    twoBack = oneBack;
    oneBack = current;
    current = recycled;
  }
  return oneBack[b.length] <= maxDist;
}

int _min3(int a, int b, int c) {
  final ab = a < b ? a : b;
  return ab < c ? ab : c;
}
