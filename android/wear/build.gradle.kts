import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// wearApp(project(":wear")) in android/app/build.gradle.kts embeds this module's APK in
// the phone app, which requires the versionCode to match. Both derive from pubspec.yaml
// so they cannot drift apart the way they did before (see LESSONS.md).
val pubspecVersion = rootProject.file("../pubspec.yaml").readLines()
    .first { it.trim().startsWith("version:") }
    .substringAfter("version:")
    .trim()
val wearVersionName = pubspecVersion.substringBefore("+")
val wearVersionCode = pubspecVersion.substringAfter("+").toInt()

// Release signing must match the phone app's key for wearApp embedding — see
// android/app/build.gradle.kts and RELEASE.md. Absent on dev machines/CI, where we fall
// back to the debug keystore.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.ams.herculex"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.ams.herculex"
        minSdk = 30
        targetSdk = 33
        versionCode = wearVersionCode
        versionName = wearVersionName
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
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("com.google.android.gms:play-services-wearable:20.0.1")

    // Wear OS Compose
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.compose.ui:ui:1.5.4")
    implementation("androidx.compose.ui:ui-tooling-preview:1.5.4")
    implementation("androidx.wear.compose:compose-material:1.3.0")
    implementation("androidx.wear.compose:compose-foundation:1.3.0")
    
    // Wear OS Navigation
    implementation("androidx.wear.compose:compose-navigation:1.3.0")

    // ViewModel + Compose integration
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.7.0")

    // Tiles
    implementation("androidx.wear.tiles:tiles:1.3.0")
    implementation("androidx.wear.tiles:tiles-material:1.3.0")

    // Horologist for better Wear OS Compose support
    implementation("com.google.android.horologist:horologist-compose-layout:0.5.18")
    implementation("com.google.android.horologist:horologist-compose-material:0.5.18")
    implementation("com.google.android.horologist:horologist-tiles:0.5.18")

    // Complications
    implementation("androidx.wear.watchface:watchface-complications-data-source-ktx:1.2.0")

    // Ongoing Activity
    implementation("androidx.wear:wear-ongoing:1.0.0")

    // Tooling
    debugImplementation("androidx.compose.ui:ui-tooling:1.5.4")

    // Unit tests (JVM). Robolectric provides a Context for the
    // SharedPreferences-backed AppliedRevisionStore without an emulator.
    testImplementation("junit:junit:4.13.2")
    testImplementation("androidx.test:core:1.5.0")
    testImplementation("org.robolectric:robolectric:4.11.1")
}
