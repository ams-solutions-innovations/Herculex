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

const _maxSummaryChars = 700;
const _maxSuggestionChars = 300;
const _minSuggestions = 2;
const _maxSuggestions = 3;

/// A validated weekly narrative: one summary plus 2-3 suggestions.
class WeeklyNarrative {
  const WeeklyNarrative({required this.summary, required this.suggestions});

  /// Strict parse. Throws [FormatException] on any miss. Pass
  /// `checkCausalLanguage: false` to skip only the causal-wording guard.
  factory WeeklyNarrative.fromJson(
    Map<String, dynamic> json, {
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
