/// Rejects causal wording in AI-written weekly-report text (D-12, RPT-05).
///
/// The weekly report may only describe correlation: "tended to go with", never
/// "because". [patterns] is the single source of truth for the word list; do
/// not duplicate it elsewhere.
///
/// False positives (even a negated "does not cause") only cost the user a
/// Retry, so the list errs wide. The prompt asks the model to avoid even
/// negated causal words.
///
/// Pure Dart.
library;

abstract final class CausalLanguageGuard {
  /// Phrases that signal a causal claim. A single space matches any run of
  /// whitespace; every entry is matched on word boundaries, case-insensitively.
  /// Regex alternations are allowed (see the `caus*` and `that's why` entries).
  static const List<String> patterns = [
    'because',
    'caus(?:e|es|ed|ing)',
    'led to',
    'leads to',
    'leading to',
    'due to',
    'owing to',
    'as a result',
    'resulted in',
    'results in',
    'resulting in',
    'thanks to',
    'which is why',
    "that(?:'s|’s| is) why",
    'this is why',
    'the reason',
    'driven by',
    'explains why',
    'responsible for',
  ];

  static final RegExp _regex = RegExp(
    '\\b(?:${patterns.map((p) => p.replaceAll(' ', r'\s+')).join('|')})\\b',
    caseSensitive: false,
  );

  /// The first causal token found in [texts] (lower-cased), or null.
  static String? firstViolation(Iterable<String> texts) {
    for (final text in texts) {
      final match = _regex.firstMatch(text);
      if (match != null) return match.group(0)!.toLowerCase();
    }
    return null;
  }
}
