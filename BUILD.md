# EDITORS-PRO Android Build

## Full media build on Windows

Prerequisites: Flutter, Rust with `cargo-ndk`, Android Studio/SDK, and Docker Desktop. The FFmpeg build uses the official signed FFmpeg 7.1.5 source and the same Android NDK revision configured in Gradle.

```powershell
flutter pub get
.\scripts\build_ffmpeg_android.ps1
$env:FFMPEG_DIR = (Resolve-Path .\engine\ffmpeg-android-lgpl).Path
cargo ndk -t arm64-v8a -t x86_64 build --manifest-path engine/Cargo.toml --release --features ffmpeg
```

Copy the FFmpeg libraries and Rust engine into their ABI-specific Android folders:

```powershell
$root = (Get-Location).Path
foreach ($abi in @("arm64-v8a", "x86_64")) {
    $libDir = if ($abi -eq "arm64-v8a") { "arm64" } else { "amd64" }
    $jniDir = Join-Path $root "android/app/src/main/jniLibs/$abi"
    New-Item -ItemType Directory -Force $jniDir | Out-Null
    Copy-Item "engine/ffmpeg-android-lgpl/lib/$libDir/*.so" $jniDir -Force
    $triple = if ($abi -eq "arm64-v8a") { "aarch64" } else { "x86_64" }
    Copy-Item "engine/target/$triple-linux-android/release/libeditors_pro_engine.so" $jniDir -Force
}
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. If no upload keystore is configured, this is a debug-signed testing APK, not a Play-ready release. For an automated local build that backs up the old ignored FFmpeg binaries before replacing them, use `scripts/build_android_release.ps1`.

## Import-only or UI build

To build the Flutter interface without the Rust FFmpeg feature, use:

```powershell
flutter pub get
flutter build apk --release
```

Video decode, timeline composition, and export are incomplete without the native FFmpeg build. This mode is useful only for UI and gallery import checks.

## Licensing and release checks

Read [docs/FFMPEG-ANDROID.md](docs/FFMPEG-ANDROID.md) before distributing an APK or AAB. Never use the prior `ffmpeg-kit-full-gpl` package for a commercial build without a separate licensing decision.
