package com.ams.herculex.auth

import android.app.Activity
import android.content.Context
import android.content.Intent
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInAccount
import com.google.android.gms.auth.api.signin.GoogleSignInClient
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.tasks.Task
import com.google.firebase.auth.AuthCredential
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.auth.OAuthProvider
import com.google.firebase.auth.UserProfileChangeRequest
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

class FirebaseAuthRepository(
    private val appContext: Context,
    private val firebaseAuth: FirebaseAuth = FirebaseAuth.getInstance(),
) {

    val currentUser get() = firebaseAuth.currentUser

    suspend fun registerWithEmail(
        email: String,
        password: String,
        displayName: String? = null,
    ): AuthSession {
        val authResult = firebaseAuth
            .createUserWithEmailAndPassword(email.trim(), password)
            .awaitResult()

        if (!displayName.isNullOrBlank()) {
            authResult.user
                ?.updateProfile(
                    UserProfileChangeRequest.Builder()
                        .setDisplayName(displayName.trim())
                        .build(),
                )
                ?.awaitResult()
        }

        authResult.user?.sendEmailVerification()?.awaitResult()
        val token = authResult.user?.getIdToken(false)?.awaitResult()?.token
        return requireNotNull(authResult.user).toAuthSession(
            provider = HerculexAuthProvider.EMAIL_PASSWORD,
            idToken = token,
        )
    }

    suspend fun loginWithEmail(
        email: String,
        password: String,
    ): AuthSession {
        val authResult = firebaseAuth
            .signInWithEmailAndPassword(email.trim(), password)
            .awaitResult()

        val token = authResult.user?.getIdToken(false)?.awaitResult()?.token
        return requireNotNull(authResult.user).toAuthSession(
            provider = HerculexAuthProvider.EMAIL_PASSWORD,
            idToken = token,
        )
    }

    suspend fun sendPasswordReset(email: String) {
        firebaseAuth.sendPasswordResetEmail(email.trim()).awaitResult()
    }

    fun buildGoogleSignInIntent(serverClientId: String): Intent {
        return buildGoogleSignInClient(serverClientId).signInIntent
    }

    suspend fun signInWithGoogleResult(
        data: Intent?,
        serverClientId: String,
    ): AuthSession {
        val account = resolveGoogleAccount(data)
        val idToken = account.idToken
            ?: throw IllegalStateException(
                "Google Sign-In did not return an ID token. Verify the Firebase Web client ID.",
            )

        val credential = GoogleAuthProvider.getCredential(idToken, null)
        return signInWithCredential(
            credential = credential,
            provider = HerculexAuthProvider.GOOGLE,
        )
    }

    suspend fun signInWithApple(activity: Activity): AuthSession {
        val providerBuilder = OAuthProvider.newBuilder("apple.com").apply {
            scopes = listOf("email", "name")
        }

        val authResult = firebaseAuth.pendingAuthResult?.awaitResult()
            ?: firebaseAuth.startActivityForSignInWithProvider(activity, providerBuilder.build())
                .awaitResult()

        val token = authResult.user?.getIdToken(false)?.awaitResult()?.token
        return requireNotNull(authResult.user).toAuthSession(
            provider = HerculexAuthProvider.APPLE,
            idToken = token,
        )
    }

    suspend fun signOut(serverClientId: String? = null) {
        firebaseAuth.signOut()
        if (!serverClientId.isNullOrBlank()) {
            buildGoogleSignInClient(serverClientId).signOut().awaitResult()
        }
    }

    private suspend fun signInWithCredential(
        credential: AuthCredential,
        provider: HerculexAuthProvider,
    ): AuthSession {
        val authResult = firebaseAuth.signInWithCredential(credential).awaitResult()
        val token = authResult.user?.getIdToken(false)?.awaitResult()?.token
        return requireNotNull(authResult.user).toAuthSession(
            provider = provider,
            idToken = token,
        )
    }

    private fun buildGoogleSignInClient(serverClientId: String): GoogleSignInClient {
        val options = GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
            .requestEmail()
            .requestIdToken(serverClientId)
            .build()

        return GoogleSignIn.getClient(appContext, options)
    }

    private suspend fun resolveGoogleAccount(data: Intent?): GoogleSignInAccount {
        return try {
            GoogleSignIn.getSignedInAccountFromIntent(data).awaitResult()
        } catch (error: ApiException) {
            throw IllegalStateException("Google Sign-In failed with code ${error.statusCode}.", error)
        }
    }
}

private suspend fun <T> Task<T>.awaitResult(): T {
    return suspendCoroutine { continuation ->
        addOnSuccessListener { continuation.resume(it) }
        addOnFailureListener { continuation.resumeWithException(it) }
        addOnCanceledListener { continuation.resumeWithException(IllegalStateException("Task was cancelled.")) }
    }
}
