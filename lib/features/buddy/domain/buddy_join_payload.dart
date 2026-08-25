/// Codec for Gym Buddy join QR codes and deep links.
/// Carries only the single-use bearer token, never personal identities or session IDs.
class BuddyJoinPayload {
  const BuddyJoinPayload(this.token);

  final String token;

  /// Encodes the token into a `herculex://buddy/join?t=<token>` URI string.
  String encode() => 'herculex://buddy/join?t=${Uri.encodeComponent(token)}';

  /// Decodes a raw scanned string or URI.
  /// Returns `null` on malformed inputs, wrong scheme, or missing token without throwing.
  static BuddyJoinPayload? tryDecode(String raw) {
    try {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;

      final uri = Uri.tryParse(trimmed);
      if (uri == null) return null;

      if (uri.scheme != 'herculex') return null;
      if (uri.host != 'buddy') return null;
      if (uri.path != '/join') return null;

      final token = uri.queryParameters['t'];
      if (token == null || token.trim().isEmpty) return null;

      return BuddyJoinPayload(token.trim());
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuddyJoinPayload &&
          runtimeType == other.runtimeType &&
          token == other.token;

  @override
  int get hashCode => token.hashCode;
}
