[CmdletBinding()]
param(
    [string]$Serial = 'R5CT62RY8LJ',
    [string]$AndroidSdkRoot = "$env:LOCALAPPDATA\Android\sdk",
    [string]$TestName = 'audio_channel_test',
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
if ($Serial -notmatch '^[A-Za-z0-9._:-]+$') { throw 'Invalid device serial.' }
if ($TestName -notmatch '^[A-Za-z0-9_]+$') { throw 'Invalid integration test name.' }
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$auditDir = Join-Path $projectRoot 'build\feature-audit'
New-Item -ItemType Directory -Force $auditDir | Out-Null
$adb = Join-Path $AndroidSdkRoot 'platform-tools\adb.exe'
$env:ANDROID_NDK_HOME = Join-Path $AndroidSdkRoot 'ndk\28.2.13676358'
$toolchain = Join-Path $env:ANDROID_NDK_HOME 'toolchains\llvm\prebuilt\windows-x86_64'
$env:LIBCLANG_PATH = Join-Path $projectRoot 'build\native-toolchain\libclang\clang\native'
$env:FFMPEG_DIR = Join-Path $projectRoot 'engine\ffmpeg-android-lgpl'
$env:CARGO_BUILD_JOBS = '4'
$resourceDir = (& (Join-Path $toolchain 'bin\clang.exe') --print-resource-dir).Trim()
$sysroot = (Join-Path $toolchain 'sysroot').Replace('\', '/')
$variable = 'BINDGEN_EXTRA_CLANG_ARGS_aarch64-linux-android'
$previous = [Environment]::GetEnvironmentVariable($variable, 'Process')
$arguments = "--target=aarch64-linux-android24 --sysroot=`"$sysroot`" -I`"$sysroot/usr/include/aarch64-linux-android`" -resource-dir=`"$resourceDir`""
[Environment]::SetEnvironmentVariable($variable, $arguments, 'Process')
$logName = if ($TestName -eq 'audio_channel_test') { 'audio' } else { $TestName }
$buildLog = Join-Path $auditDir "android-$logName-build.log"
Push-Location (Join-Path $projectRoot 'engine')
try {
    if (-not $SkipBuild) {
        & cargo ndk -t arm64-v8a --platform 24 test --release --test $TestName --features ffmpeg --locked --no-run *> $buildLog
        if ($LASTEXITCODE -ne 0) { throw "Android test compilation failed. See $buildLog." }
    }
} finally {
    Pop-Location
    [Environment]::SetEnvironmentVariable($variable, $previous, 'Process')
}
$binary = (Get-ChildItem (Join-Path $projectRoot 'engine\target\aarch64-linux-android\release\deps') |
    Where-Object { $_.Name -match ('^' + [regex]::Escape($TestName) + '-[a-f0-9]+$') -and $_.Length -gt 0 } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
if (-not $binary -or -not (Test-Path -LiteralPath $binary)) { throw 'Compiled test binary was not found.' }
$header = & (Join-Path $toolchain 'bin\llvm-readelf.exe') -h $binary
if ($LASTEXITCODE -ne 0 -or -not ($header -match 'Machine:\s+AArch64')) { throw 'Test executable is not a valid Android ARM64 ELF.' }
$remoteDir = "/data/local/tmp/editors-pro-$logName-qa-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
& $adb -s $Serial shell mkdir -p $remoteDir
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the owned Android test directory.' }
& $adb -s $Serial push $binary "$remoteDir/$TestName"
if ($LASTEXITCODE -ne 0) { throw 'Could not copy the integration test executable.' }
$libraries = @(Get-ChildItem (Join-Path $env:FFMPEG_DIR 'lib\arm64\*.so'))
$libraries += Get-Item (Join-Path $sysroot 'usr/lib/aarch64-linux-android/libc++_shared.so')
foreach ($library in $libraries) {
    & $adb -s $Serial push $library.FullName "$remoteDir/$($library.Name)"
    if ($LASTEXITCODE -ne 0) { throw "Could not copy $($library.Name)." }
}
& $adb -s $Serial shell chmod 700 "$remoteDir/$TestName"
& $adb -s $Serial shell mkdir -p "$remoteDir/native-output"
$deviceLog = Join-Path $auditDir "android-$logName-tests.log"
& $adb -s $Serial shell "TMPDIR=$remoteDir EDITORS_PRO_QA_OUTPUT_DIR=$remoteDir/native-output LD_LIBRARY_PATH=$remoteDir $remoteDir/$TestName --test-threads=1 --nocapture" *> $deviceLog
$testExit = $LASTEXITCODE
Get-Content $deviceLog
Write-Host "Android QA directory retained: $remoteDir"
if ($testExit -ne 0) { throw "Android $TestName tests failed ($testExit)." }
