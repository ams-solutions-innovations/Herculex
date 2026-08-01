plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.ams.herculex"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.ams.herculex"
        minSdk = 30
        targetSdk = 33
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
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
}
