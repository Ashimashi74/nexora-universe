// NEXORA · Godot v2 Android plugin (AAR) wrapping LiveKit.
// Build:  gradle assembleRelease   ->  build/outputs/aar/nexora-livekit-release.aar
// Versions are kept in sync with the Godot 4.5.1 Android build template (AGP 8.6.1, Kotlin 2.1.20,
// compileSdk 35, minSdk 24, Java 17) and with addons/nexora_livekit/export_plugin.gd.
plugins {
    id("com.android.library") version "8.6.1"
    id("org.jetbrains.kotlin.android") version "2.1.20"
}

val godotVersion = "4.5.1.stable"
val livekitVersion = "2.30.0"
val coroutinesVersion = "1.9.0"

android {
    namespace = "com.nexora.livekit"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release { isMinifyEnabled = false }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    // Provided by the Godot app at runtime (the build template ships godot-lib).
    compileOnly("org.godotengine:godot:$godotVersion")
    // NOTE: a local AAR carries no POM, so these are re-declared as maven dependencies by the
    // Godot EditorExportPlugin (addons/nexora_livekit/export_plugin.gd). Keep the versions equal.
    implementation("io.livekit:livekit-android:$livekitVersion")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:$coroutinesVersion")
}
