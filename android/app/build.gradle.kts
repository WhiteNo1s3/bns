import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The person's own release certificate ("certified" APK): generated ONCE by
// scripts/make-keystore.ps1, which writes android/key.properties + the .jks.
// Both are gitignored — a signing identity never enters the repo. Without
// them the release still builds (debug-signed) so `flutter run --release`
// keeps working on any machine.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.whiteno1se.bns"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires core library desugaring
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.whiteno1se.bns"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            // The dev copy installs NEXT TO the real app, never over it —
            // the person's data on the phone is not a build artifact.
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-dev"
        }
        release {
            // Real certificate when the keystore exists (scripts/make-keystore.ps1),
            // debug keys otherwise so a fresh clone still runs.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Ship builds, not source: R8 shrinks + obfuscates the JVM side.
            // (Dart side is AOT + --obfuscate via scripts/build.ps1.)
            // Diagnostic escape hatch: set env ORG_GRADLE_PROJECT_bnsNoMinify=true
            // to build a release WITHOUT R8 — lets a device test bisect
            // "R8 broke it" from everything else in minutes.
            val noMinify = (project.findProperty("bnsNoMinify") as String?) == "true"
            isMinifyEnabled = !noMinify
            isShrinkResources = !noMinify
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
