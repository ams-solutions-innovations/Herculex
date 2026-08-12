import 'dart:convert';

enum AuthProvider {
  emailPassword,
  google,
  apple;

  static AuthProvider fromNative(String raw) => switch (raw) {
    'GOOGLE' => AuthProvider.google,
    'APPLE' => AuthProvider.apple,
    _ => AuthProvider.emailPassword,
  };
}

class AuthSession {
  const AuthSession({
    required this.uid,
    required this.provider,
    this.email,
    this.displayName,
    this.photoUrl,
    this.idToken,
    required this.isEmailVerified,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final AuthProvider provider;
  final String? idToken;
  final bool isEmailVerified;

  factory AuthSession.fromMap(Map<Object?, Object?> map) {
    return AuthSession(
      uid: map['uid'] as String,
      email: map['email'] as String?,
      displayName: map['displayName'] as String?,
      photoUrl: map['photoUrl'] as String?,
      provider: AuthProvider.fromNative((map['provider'] as String?) ?? ''),
      idToken: map['idToken'] as String?,
      isEmailVerified: map['isEmailVerified'] as bool? ?? false,
    );
  }

  /// Disk-facing serialization. Deliberately omits [idToken] — that is a
  /// bearer credential and must never land in SharedPreferences; callers
  /// that need it read it from secure storage via `LocalAuthRepository`.
  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'provider': provider.name,
    'isEmailVerified': isEmailVerified,
  };

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      uid: json['uid'] as String,
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      provider: switch (json['provider'] as String? ?? '') {
        'google' => AuthProvider.google,
        'apple' => AuthProvider.apple,
        _ => AuthProvider.emailPassword,
      },
      isEmailVerified: json['isEmailVerified'] as bool? ?? false,
    );
  }

  String encode() => jsonEncode(toJson());

  static AuthSession decode(String raw) =>
      AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
