import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Release signing is read from android/key.properties when present (see RELEASE.md).
// The file is git-ignored and absent on dev machines/CI, where we fall back to the
// debug keystore so `flutter run --release` still works locally.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.ams.herculex"
    // Android 16 QPR1 (API 36.1) is the first platform to expose
    // Notification.Builder.setRequestPromotedOngoing — the Live Update / Now Bar
    // promotion request used by the nowbar renderer. flutter.compileSdkVersion is
    // still 36, which lacks it, so pin the platform hash for this module.
    compileSdkVersion("android-36.1")
    ndkVersion = flutter.ndkVersion

    androidResources {
        noCompress += listOf("tflite", "binarypb", "pb", "bincfg", "conv_model", "lstm_model", "fb", "json", "bin")
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Reverse-domain application ID. Confirm/replace with your registered
        // domain before the first Play Store upload — it cannot change afterward.
        applicationId = "com.ams.herculex"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // Local fallback only — a debug-signed APK cannot be published.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

// Flutter builds only ever assemble :app, so the watch module used to go stale silently
// (see LESSONS.md). `wearApp(project(":wear"))` would be the normal Gradle way to embed
// it, but that configuration is deprecated in AGP and slated for removal in 9.0, and it
// only ever supported the legacy Wear 1.x auto-push-install model anyway — it does
// nothing useful for this standalone Wear OS 3+ app. Instead, force the watch module to
// build alongside the phone app so a stale APK can no longer hide; installing it onto the
// watch is still a separate `adb install` step (see LESSONS.md).
afterEvaluate {
    tasks.named("assembleDebug") { dependsOn(":wear:assembleDebug") }
    tasks.named("assembleRelease") { dependsOn(":wear:assembleRelease") }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("com.google.android.gms:play-services-auth:21.4.0")
    implementation("com.google.android.gms:play-services-wearable:20.0.1")

    // Unit tests (JVM). This module had no test dependencies at all before
    // Phase 4 of docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md
    // — mirrors the wear module's Phase 0 setup. Robolectric provides a
    // Context for the SharedPreferences-backed queue store.
    testImplementation("junit:junit:4.13.2")
    testImplementation("androidx.test:core:1.5.0")
    testImplementation("org.robolectric:robolectric:4.11.1")
}
