[CmdletBinding()]
param(
    [string]$FlutterCommand = "flutter"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ffmpegRoot = Join-Path $projectRoot "engine\ffmpeg-android-lgpl"
$ffmpegLibs = @("avcodec", "avdevice", "avfilter", "avformat", "avutil", "swresample", "swscale")
$abiMap = @{
    "arm64-v8a" = @{ Lib = "arm64"; Triple = "aarch64" }
    "x86_64" = @{ Lib = "amd64"; Triple = "x86_64" }
}

# Match android/app/build.gradle.kts when no NDK is selected by the caller.
if (-not $env:ANDROID_NDK_HOME) {
    $androidSdkRoot = $env:ANDROID_HOME
    if (-not $androidSdkRoot) { $androidSdkRoot = $env:ANDROID_SDK_ROOT }
    if (-not $androidSdkRoot) { $androidSdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
    $env:ANDROID_NDK_HOME = Join-Path $androidSdkRoot "ndk\28.2.13676358"
}
$ndkToolchain = Join-Path $env:ANDROID_NDK_HOME "toolchains\llvm\prebuilt\windows-x86_64"
$ndkClang = Join-Path $ndkToolchain "bin\clang.exe"
if (-not (Test-Path $ndkClang)) {
    throw "Android NDK clang.exe was not found. Install NDK 28.2.13676358 or set ANDROID_NDK_HOME."
}
$clangResourceDirectory = (& $ndkClang --print-resource-dir).Trim()
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $clangResourceDirectory "include\stddef.h"))) {
    throw "The selected NDK does not provide Clang's standard headers."
}
$ndkSysroot = (Join-Path $ndkToolchain "sysroot").Replace('\', '/')
if (-not $env:LIBCLANG_PATH) {
    $localLibClang = Join-Path $projectRoot "build\native-toolchain\libclang\clang\native"
    if (Test-Path (Join-Path $localLibClang "libclang.dll")) {
        $env:LIBCLANG_PATH = $localLibClang
    } else {
        throw "Set LIBCLANG_PATH, or install the project-local binding generator: python -m pip install --target build/native-toolchain/libclang --no-deps libclang==18.1.1"
    }
}

$missingFfmpegBuildInputs = @()
foreach ($abi in $abiMap.Keys) {
    $libDir = Join-Path $ffmpegRoot "lib\$($abiMap[$abi].Lib)"
    foreach ($lib in $ffmpegLibs) {
        if (-not (Test-Path (Join-Path $libDir "lib$lib.so"))) {
            $missingFfmpegBuildInputs += "${abi}: lib$lib.so"
        }
    }
}
$sharedFfmpegInputs = @(
    (Join-Path $ffmpegRoot "include\libavcodec\avcodec.h"),
    (Join-Path $ffmpegRoot "BUILDINFO.txt"),
    (Join-Path $ffmpegRoot "COPYING.LGPLv2.1")
)
foreach ($input in $sharedFfmpegInputs) {
    if (-not (Test-Path $input)) {
        $missingFfmpegBuildInputs += $input
    }
}

if ($missingFfmpegBuildInputs.Count -gt 0) {
    Write-Host "Building missing LGPL FFmpeg Android libraries before packaging."
    $ffmpegBuildScript = Join-Path $PSScriptRoot "build_ffmpeg_android.ps1"
    & $ffmpegBuildScript
    if ($LASTEXITCODE -ne 0) {
        throw "The pinned LGPL FFmpeg Android build failed. See engine\ffmpeg-android-lgpl\.build\ffmpeg-build.log."
    }
}

foreach ($abi in $abiMap.Keys) {
    $libDir = Join-Path $ffmpegRoot "lib\$($abiMap[$abi].Lib)"
    foreach ($lib in $ffmpegLibs) {
        if (-not (Test-Path (Join-Path $libDir "lib$lib.so"))) {
            throw "FFmpeg is not built for $abi. Run scripts/build_ffmpeg_android.ps1 first."
        }
    }
}

$env:FFMPEG_DIR = $ffmpegRoot
$legacyBackup = Join-Path $ffmpegRoot "legacy-prebuilt-backup"
foreach ($abi in $abiMap.Keys) {
    $jniDir = Join-Path $projectRoot "android\app\src\main\jniLibs\$abi"
    $backupDir = Join-Path $legacyBackup $abi
    New-Item -ItemType Directory -Force $jniDir | Out-Null

    if (Test-Path $jniDir) {
        foreach ($lib in ($ffmpegLibs + @("editors_pro_engine", "c++_shared"))) {
            $oldLibrary = Join-Path $jniDir "lib$lib.so"
            if ((Test-Path $oldLibrary) -and -not (Test-Path (Join-Path $backupDir "lib$lib.so"))) {
                New-Item -ItemType Directory -Force $backupDir | Out-Null
                Copy-Item $oldLibrary $backupDir
            }
        }
    }

    $sourceLibDir = Join-Path $ffmpegRoot "lib\$($abiMap[$abi].Lib)"
    Copy-Item (Join-Path $sourceLibDir "*.so") $jniDir -Force
    $triple = $abiMap[$abi].Triple
    $cppRuntime = Join-Path $ndkSysroot "usr/lib/$triple-linux-android/libc++_shared.so"
    if (-not (Test-Path $cppRuntime)) {
        throw "The selected NDK does not provide the C++ runtime for $abi."
    }
    Copy-Item $cppRuntime $jniDir -Force
    $engineLibrary = Join-Path $projectRoot "engine\target\$triple-linux-android\release\libeditors_pro_engine.so"

    # cargo-ndk reads metadata from its working directory before forwarding
    # Cargo arguments, so --manifest-path alone cannot select the engine.
    # cargo-ndk replaces the underscore form of this variable on Windows.
    # bindgen prefers the hyphenated target form, preserving our resource dir.
    $bindgenVariable = "BINDGEN_EXTRA_CLANG_ARGS_$triple-linux-android"
    $previousBindgenArgs = [Environment]::GetEnvironmentVariable($bindgenVariable, "Process")
    $bindgenArgs = @(
        "--target=$triple-linux-android24",
        "--sysroot=`"$ndkSysroot`"",
        "-I`"$ndkSysroot/usr/include/$triple-linux-android`"",
        "-resource-dir=`"$clangResourceDirectory`""
    ) -join " "
    [Environment]::SetEnvironmentVariable($bindgenVariable, $bindgenArgs, "Process")
    Push-Location (Join-Path $projectRoot "engine")
    try {
        & cargo ndk -t $abi --platform 24 build --release --features ffmpeg --locked
        if ($LASTEXITCODE -ne 0) {
            throw "Rust engine build failed for $abi with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
        [Environment]::SetEnvironmentVariable($bindgenVariable, $previousBindgenArgs, "Process")
    }
    Copy-Item $engineLibrary $jniDir -Force
}

Push-Location $projectRoot
$debugSigningOverride = "ORG_GRADLE_PROJECT_EDITORS_PRO_ALLOW_DEBUG_SIGNED_RELEASE"
$previousDebugSigningOverride = [Environment]::GetEnvironmentVariable(
    $debugSigningOverride,
    [EnvironmentVariableTarget]::Process
)
try {
    [Environment]::SetEnvironmentVariable(
        $debugSigningOverride,
        "true",
        [EnvironmentVariableTarget]::Process
    )
    & $FlutterCommand pub get
    if ($LASTEXITCODE -ne 0) { throw "Flutter dependency resolution failed." }
    & $FlutterCommand build apk --release --target-platform android-arm64,android-x64 -Pdisable-abi-filtering=true --dart-define=FFMPEG_LICENSE_PROFILE=lgpl-2.1
    if ($LASTEXITCODE -ne 0) { throw "Flutter APK build failed." }
} finally {
    [Environment]::SetEnvironmentVariable(
        $debugSigningOverride,
        $previousDebugSigningOverride,
        [EnvironmentVariableTarget]::Process
    )
    Pop-Location
}

Write-Host "Built testing APK: $projectRoot\build\app\outputs\flutter-apk\app-release.apk"
Write-Warning "Without an upload keystore, the APK is debug-signed and is not ready for Play submission."
