import 'dart:convert';

/// Safely decodes `set_entries.set_type_meta_json`.
///
/// That column is free-form JSON written by several set-type editors, is
/// carried across cloud sync, and survives schema migrations untouched — so it
/// is untrusted input by the time a widget reads it. Two of its four call
/// sites decoded it **inside `build()`** with no guard, which turned any
/// malformed or legacy value into a `FormatException` during layout on the
/// active-workout screen — a red screen on the app's hottest path.
///
/// Returns an empty map for null, malformed, or non-object JSON, so callers can
/// subscript the result unconditionally.
Map<String, dynamic> decodeSetTypeMeta(String? json) {
  if (json == null || json.isEmpty) return const {};
  try {
    final decoded = jsonDecode(json);
    // A bare list or scalar at the root would make `meta['key']` a
    // NoSuchMethodError rather than a decode failure.
    return decoded is Map<String, dynamic>
        ? decoded
        : (decoded is Map ? Map<String, dynamic>.from(decoded) : const {});
  } catch (_) {
    return const {};
  }
}

/// Normalises a meta value into a list of ints — `miniSets`, `extraReps` and
/// friends, which are written as either a list or a bare number depending on
/// which editor produced them.
///
/// `cast<int>()` is lazy, so a non-int element would otherwise throw later at
/// render time, far from the decode that admitted it.
List<int> setTypeMetaInts(Object? raw) {
  if (raw is num) return [raw.toInt()];
  if (raw is! List) return const [];
  return raw.whereType<num>().map((n) => n.toInt()).toList(growable: false);
}
