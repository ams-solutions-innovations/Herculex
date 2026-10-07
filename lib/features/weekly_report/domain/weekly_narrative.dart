/// Client-side parser for the Herculex AI weekly-report narrative.
///
/// This is the authoritative gate on AI-written report text (D-02, D-12,
/// RPT-05); the server normalizer is a first-pass shape guard only. Every
/// structural miss throws [FormatException] — no silent defaults — and
/// causal wording is rejected via [CausalLanguageGuard]. A rejected narrative
/// is treated like any other narrative failure by the caller; this file only
/// throws.
///
/// Stored narratives re-parse structurally without the guard
/// ([WeeklyNarrative.tryDecodeStored]) so a future word-list change can never
/// orphan a saved narrative.
///
/// Pure Dart.
library;

import 'dart:convert';

import 'package:herculex/features/weekly_report/domain/causal_language_guard.dart';

const _maxSummaryChars = WeeklyNarrativeLimits.summaryChars;
const _maxSuggestionChars = WeeklyNarrativeLimits.suggestionChars;
const _minSuggestions = WeeklyNarrativeLimits.minSuggestions;
const _maxSuggestions = WeeklyNarrativeLimits.maxSuggestions;

/// The narrative limits, public so a test can assert they equal the Edge
/// Function's constants in `supabase/functions/gemini-analyze/index.ts`
/// (IN-03). Change both together.
abstract final class WeeklyNarrativeLimits {
  static const int summaryChars = 700;
  static const int suggestionChars = 300;
  static const int minSuggestions = 2;
  static const int maxSuggestions = 3;
  static const int factsChars = 8000;
}

/// Integers 0..[_alwaysAllowedMax] never need to occur in the facts.
const _alwaysAllowedMax = 60;

/// Keys whose values are dates; mirrored from weekly_report_guard.ts.
const _dateKeys = <String>{
  'weekStartIso',
  'weekEndIso',
  'windowEnd',
  'start',
  'end',
};

// Mirrored from weekly_report_guard.ts (`extractNumbers`): "2,150" / "2 150"
// are one number; "3, 4" and "1,20" stay separate; "." is the decimal mark.
final _numberPattern = RegExp(
  r'\d{1,3}(?:[, ]\d{3})+(?:\.\d+)?(?!\d)|\d+(?:\.\d+)?',
);
final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Absolute, canonical numbers in [text] (identical to the server).
List<double> extractNarrativeNumbers(String text) {
  final out = <double>[];
  for (final m in _numberPattern.allMatches(text)) {
    final n = double.tryParse(m.group(0)!.replaceAll(RegExp('[, ]'), ''));
    if (n != null && n.isFinite) out.add(n);
  }
  return out;
}

/// Every number that may be quoted from [facts] (identical to the server).
Set<double> collectFactNumbers(Object? facts) {
  final out = <double>{};
  void walk(Object? value, String? key) {
    if (key != null && _dateKeys.contains(key)) return;
    if (value is num) {
      if (value.isFinite) out.add(value.abs().toDouble());
    } else if (value is String) {
      if (_isoDate.hasMatch(value.trim())) return;
      out.addAll(extractNarrativeNumbers(value));
    } else if (value is List) {
      for (final v in value) {
        walk(v, null);
      }
    } else if (value is Map) {
      value.forEach((k, v) => walk(v, k.toString()));
    }
  }

  walk(facts, null);
  return out;
}

/// Returns the first number in [texts] that is neither in [facts] nor an
/// always-allowed integer 0..60, or null.
double? firstNumberNotInFacts(Iterable<String> texts, Object? facts) {
  final allowed = collectFactNumbers(facts);
  for (final text in texts) {
    for (final n in extractNarrativeNumbers(text)) {
      final small =
          n == n.truncateToDouble() && n >= 0 && n <= _alwaysAllowedMax;
      if (!small && !allowed.contains(n)) return n;
    }
  }
  return null;
}

/// A validated weekly narrative: one summary plus 2-3 suggestions.
class WeeklyNarrative {
  const WeeklyNarrative({required this.summary, required this.suggestions});

  /// Strict parse. Throws [FormatException] on any miss. Pass
  /// `checkCausalLanguage: false` to skip the causal-wording guard and the
  /// number-in-facts check. When [facts] is given, every number in the text
  /// must occur in it (WR-05).
  factory WeeklyNarrative.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? facts,
    bool checkCausalLanguage = true,
  }) {
    final summary = _requiredString(json, 'summary', _maxSummaryChars);

    final rawSuggestions = json['suggestions'];
    if (rawSuggestions is! List) {
      throw const FormatException(
        'Weekly narrative is missing a suggestions list.',
      );
    }
    if (rawSuggestions.length < _minSuggestions ||
        rawSuggestions.length > _maxSuggestions) {
      throw FormatException(
        'Weekly narrative needs $_minSuggestions-$_maxSuggestions '
        'suggestions, got ${rawSuggestions.length}.',
      );
    }
    final suggestions = <String>[];
    for (var i = 0; i < rawSuggestions.length; i++) {
      final item = rawSuggestions[i];
      if (item is! String || item.trim().isEmpty) {
        throw FormatException('Weekly narrative suggestion $i is not text.');
      }
      final trimmed = item.trim();
      if (trimmed.length > _maxSuggestionChars) {
        throw FormatException(
          'Weekly narrative suggestion $i exceeds $_maxSuggestionChars '
          'characters.',
        );
      }
      suggestions.add(trimmed);
    }

    if (checkCausalLanguage) {
      final token = CausalLanguageGuard.firstViolation([
        summary,
        ...suggestions,
      ]);
      if (token != null) {
        throw FormatException('Causal wording rejected: $token');
      }
      if (facts != null) {
        final stray = firstNumberNotInFacts([summary, ...suggestions], facts);
        if (stray != null) {
          throw FormatException('Number not in facts: $stray');
        }
      }
    }

    return WeeklyNarrative(
      summary: summary,
      suggestions: List.unmodifiable(suggestions),
    );
  }

  /// Re-reads a stored narrative. Never throws; the causal guard is not
  /// applied (the text was validated when it was saved).
  static WeeklyNarrative? tryDecodeStored(String? json) {
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      return WeeklyNarrative.fromJson(decoded, checkCausalLanguage: false);
    } on FormatException {
      return null;
    }
  }

  final String summary;
  final List<String> suggestions;

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'suggestions': suggestions,
  };
}

String _requiredString(Map<String, dynamic> json, String key, int maxChars) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Weekly narrative is missing $key.');
  }
  final trimmed = value.trim();
  if (trimmed.length > maxChars) {
    throw FormatException(
      'Weekly narrative $key exceeds $maxChars characters.',
    );
  }
  return trimmed;
}
