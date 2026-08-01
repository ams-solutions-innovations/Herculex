package com.ams.herculex.auth

import com.google.firebase.auth.FirebaseUser

enum class HerculexAuthProvider {
    EMAIL_PASSWORD,
    GOOGLE,
    APPLE,
}

data class AuthSession(
    val uid: String,
    val email: String?,
    val displayName: String?,
    val photoUrl: String?,
    val provider: HerculexAuthProvider,
    val idToken: String?,
    val isEmailVerified: Boolean,
)

internal fun FirebaseUser.toAuthSession(
    provider: HerculexAuthProvider,
    idToken: String?,
): AuthSession {
    return AuthSession(
        uid = uid,
        email = email,
        displayName = displayName,
        photoUrl = photoUrl?.toString(),
        provider = provider,
        idToken = idToken,
        isEmailVerified = isEmailVerified,
    )
}
