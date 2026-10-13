import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties().apply {
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.isFile) {
        propertiesFile.inputStream().use { load(it) }
    }
}

fun signingValue(name: String): String? =
    System.getenv(name)?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: (findProperty(name) as? String)?.takeIf { it.isNotBlank() }

val releaseStoreFilePath = signingValue("EDITORS_PRO_STORE_FILE") ?: signingValue("storeFile")
val releaseStorePassword = signingValue("EDITORS_PRO_STORE_PASSWORD") ?: signingValue("storePassword")
val releaseKeyAlias = signingValue("EDITORS_PRO_KEY_ALIAS") ?: signingValue("keyAlias")
val releaseKeyPassword = signingValue("EDITORS_PRO_KEY_PASSWORD") ?: signingValue("keyPassword")
val hasReleaseSigningCredentials = listOf(
    releaseStoreFilePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val allowDebugSignedRelease =
    providers.gradleProperty("EDITORS_PRO_ALLOW_DEBUG_SIGNED_RELEASE").orNull == "true"

android {
    namespace = "com.editorspro.editors_pro"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Release signing configuration.
    // For Play Store distribution, set these environment variables or add them to key.properties:
    //   EDITORS_PRO_STORE_FILE=/path/to/keystore.jks
    //   EDITORS_PRO_KEY_ALIAS=upload
    //   EDITORS_PRO_STORE_PASSWORD=***
    //   EDITORS_PRO_KEY_PASSWORD=***
    // Never commit keystore files or passwords to version control.
    signingConfigs {
        create("release") {
            if (hasReleaseSigningCredentials) {
                storeFile = rootProject.file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
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
            abiFilters.clear()
            abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
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
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Gradle requires a signing config at configuration time. Release tasks
            // are guarded below so this fallback is only used by explicit test builds.
            signingConfig = if (signingConfigs.findByName("release")?.storeFile != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    gradle.taskGraph.whenReady {
        val releaseBuildRequested = allTasks.any { task ->
            task.project == project && task.name.contains("release", ignoreCase = true)
        }
        if (releaseBuildRequested && !hasReleaseSigningCredentials && !allowDebugSignedRelease) {
            throw GradleException(
                "Release builds require a complete upload key in android/key.properties or " +
                    "EDITORS_PRO_* environment variables. Debug signing is only allowed for " +
                    "test artifacts with -PEDITORS_PRO_ALLOW_DEBUG_SIGNED_RELEASE=true."
            )
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

val rustEngineRoot = rootProject.projectDir.resolve("../engine").canonicalFile
val rustEngineLibraries = listOf("arm64-v8a", "x86_64").map { abi ->
    file("src/main/jniLibs/$abi/libeditors_pro_engine.so")
}
val verifyRustEngineFreshness = tasks.register("verifyRustEngineFreshness") {
    doLast {
        val rustSources = fileTree(rustEngineRoot) {
            include("Cargo.toml", "Cargo.lock", "build.rs", "src/**/*.rs")
        }.files
        if (rustSources.isEmpty()) {
            throw GradleException("Rust engine sources were not found at $rustEngineRoot.")
        }

        val newestSourceTime = rustSources.maxOf { it.lastModified() }
        val missingLibraries = rustEngineLibraries.filterNot { it.isFile }
        if (missingLibraries.isNotEmpty()) {
            throw GradleException(
                "Android Rust engine libraries are missing for: " +
                    missingLibraries.joinToString { it.parentFile.name } +
                    ". Run .\\scripts\\build_android_release.ps1 to build the native engine and APK."
            )
        }

        val staleLibraries = rustEngineLibraries.filter { it.lastModified() < newestSourceTime }
        if (staleLibraries.isNotEmpty()) {
            throw GradleException(
                "The Android Rust engine is older than its source for: " +
                    staleLibraries.joinToString { it.parentFile.name } +
                    ". Run .\\scripts\\build_android_release.ps1 before building in Android Studio."
            )
        }
    }
}

tasks.named("preBuild") {
    dependsOn(verifyRustEngineFreshness)
}
