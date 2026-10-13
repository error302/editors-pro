plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.editorspro.editors_pro"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Release signing configuration.
    // For Play Store distribution, set these environment variables or add them to local.properties:
    //   EDITORS_PRO_STORE_FILE=/path/to/keystore.jks
    //   EDITORS_PRO_KEY_ALIAS=upload
    //   EDITORS_PRO_STORE_PASSWORD=***
    //   EDITORS_PRO_KEY_PASSWORD=***
    // Never commit keystore files or passwords to version control.
    signingConfigs {
        create("release") {
            val storeFilePath = System.getenv("EDITORS_PRO_STORE_FILE")
                ?: findProperty("EDITORS_PRO_STORE_FILE") as? String
            val storePassword = System.getenv("EDITORS_PRO_STORE_PASSWORD")
                ?: findProperty("EDITORS_PRO_STORE_PASSWORD") as? String
            val keyAlias = System.getenv("EDITORS_PRO_KEY_ALIAS")
                ?: findProperty("EDITORS_PRO_KEY_ALIAS") as? String
            val keyPassword = System.getenv("EDITORS_PRO_KEY_PASSWORD")
                ?: findProperty("EDITORS_PRO_KEY_PASSWORD") as? String

            if (storeFilePath != null && storePassword != null && keyAlias != null && keyPassword != null) {
                storeFile = file(storeFilePath)
                this.storePassword = storePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "com.editorspro.editors_pro"
        // Video editing requires higher minSdk for MediaCodec and hardware acceleration
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appAuthRedirectScheme"] =
            "com.googleusercontent.apps.REPLACE_WITH_YOUR_CLIENT_ID"

        // Phase B.9: include x86_64 in addition to arm64-v8a so the app
        // runs on Android emulators for development. armeabi-v7a is
        // intentionally excluded — it covers <1% of modern devices and
        // doubles the Rust .so build time. Re-enable in a follow-up if
        // legacy 32-bit ARM support is needed.
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }

        // Rust library loading
        sourceSets {
            getByName("main") {
                jniLibs.srcDirs("src/main/jniLibs")
            }
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
            // Enable debug native symbols
            ndk {
                debugSymbolLevel = "FULL"
            }
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Use the release signing config if keystore is configured,
            // otherwise fall back to debug signing for development builds.
            signingConfig = if (signingConfigs.findByName("release")?.storeFile != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            excludes += setOf(
                "**/libffmpegkit.so",
                "**/libffmpegkit_abidetect.so",
            )
        }
    }

    // Lint options for video editor
    lint {
        disable += "MissingTranslation"
        abortOnError = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Phase B.9: Migrated from the deprecated `com.google.android.exoplayer`
    // artifact (last release June 2023) to its successor `androidx.media3`.
    // The ProGuard rules already referenced `androidx.media3.**`, so the
    // migration is now consistent end-to-end.
    // Media3 1.5.1 requires compileSdk 35+ (already set above) and
    // Java 17 (also already set in compileOptions).
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-ui:1.5.1")
    implementation("androidx.documentfile:documentfile:1.1.0")
}

flutter {
    source = "../.."
}
