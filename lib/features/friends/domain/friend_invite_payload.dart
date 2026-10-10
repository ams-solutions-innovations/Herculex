/// Codec for friend invite QR codes and links. Carries only the single-use
/// bearer token — the inviter's identity is resolved on the server.
class FriendInvitePayload {
  const FriendInvitePayload(this.token);

  final String token;

  /// `herculex://friend/invite?t=<token>`.
  String encode() => 'herculex://friend/invite?t=${Uri.encodeComponent(token)}';

  /// Accepts a scanned or pasted link, or the bare token on its own (people
  /// copy just the code out of a chat). Null for anything else, never throws.
  static FriendInvitePayload? tryDecode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (_bareToken.hasMatch(trimmed)) return FriendInvitePayload(trimmed);

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != 'herculex' || uri.host != 'friend') return null;
    if (uri.path != '/invite') return null;
    final token = uri.queryParameters['t']?.trim();
    if (token == null || token.isEmpty) return null;
    return FriendInvitePayload(token);
  }

  /// The server mints tokens with `gen_random_uuid()`.
  static final _bareToken = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  @override
  bool operator ==(Object other) =>
      other is FriendInvitePayload && other.token == token;

  @override
  int get hashCode => token.hashCode;
}
