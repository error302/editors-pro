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
        foreach ($lib in $ffmpegLibs) {
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
    $engineLibrary = Join-Path $projectRoot "engine\target\$triple-linux-android\release\libeditors_pro_engine.so"

    & cargo ndk -t $abi build --manifest-path (Join-Path $projectRoot "engine\Cargo.toml") --release --features ffmpeg
    if ($LASTEXITCODE -ne 0) {
        throw "Rust engine build failed for $abi with exit code $LASTEXITCODE."
    }
    Copy-Item $engineLibrary $jniDir -Force
}

Push-Location $projectRoot
try {
    & $FlutterCommand pub get
    if ($LASTEXITCODE -ne 0) { throw "Flutter dependency resolution failed." }
    & $FlutterCommand build apk --release --dart-define=FFMPEG_LICENSE_PROFILE=lgpl-2.1
    if ($LASTEXITCODE -ne 0) { throw "Flutter APK build failed." }
} finally {
    Pop-Location
}

Write-Host "Built testing APK: $projectRoot\build\app\outputs\flutter-apk\app-release.apk"
Write-Warning "Without an upload keystore, the APK is debug-signed and is not ready for Play submission."
