import 'dart:convert';

/// Encodes a `SharedPreferences` value for the synced `user_preferences`
/// table and back, keeping its type: JSON alone can't tell an int `1` from a
/// double `1.0`, and writing the wrong setter on the other device would make
/// the next typed getter throw.
abstract final class PrefValueCodec {
  static String encode(Object value) => jsonEncode(switch (value) {
    bool() => {'t': 'bool', 'v': value},
    int() => {'t': 'int', 'v': value},
    double() => {'t': 'double', 'v': value},
    String() => {'t': 'string', 'v': value},
    List<String>() => {'t': 'stringList', 'v': value},
    _ => throw ArgumentError.value(value, 'value', 'not a preference type'),
  });

  /// Null for anything malformed or of an unknown type — a newer app version
  /// may sync a type this one doesn't know, and that must not crash it.
  static Object? decode(String json) {
    final Object? envelope;
    try {
      envelope = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (envelope is! Map) return null;
    final value = envelope['v'];
    return switch (envelope['t']) {
      'bool' when value is bool => value,
      'int' when value is int => value,
      'double' when value is num => value.toDouble(),
      'string' when value is String => value,
      'stringList' when value is List => value.whereType<String>().toList(),
      _ => null,
    };
  }
}
