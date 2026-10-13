[CmdletBinding()]
param(
    [string[]]$Abis = @("arm64-v8a", "x86_64")
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    $dockerPath = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
    if (-not (Test-Path $dockerPath)) {
        throw "Docker Desktop is required to build the Android FFmpeg libraries on Windows."
    }
} else {
    $dockerPath = $docker.Source
}

$builderImage = "editors-pro/ffmpeg-android-builder:1"
$dockerfile = Join-Path $PSScriptRoot "ffmpeg-android-builder.Dockerfile"
$networkHosts = @("archive.ubuntu.com", "security.ubuntu.com", "dl.google.com", "ffmpeg.org")
$dockerHostArgs = foreach ($hostName in $networkHosts) {
    $address = [System.Net.Dns]::GetHostAddresses($hostName) |
        Where-Object AddressFamily -eq ([System.Net.Sockets.AddressFamily]::InterNetwork) |
        Select-Object -First 1
    if (-not $address) {
        throw "Could not resolve $hostName on Windows for the isolated build container."
    }
    "--add-host=$('{0}:{1}' -f $hostName, $address.IPAddressToString)"
}

& $dockerPath build @dockerHostArgs --tag $builderImage --file $dockerfile $PSScriptRoot
if ($LASTEXITCODE -ne 0) {
    throw "Could not prepare the FFmpeg Android build container."
}

$buildRoot = Join-Path $projectRoot "engine\ffmpeg-android-lgpl\.build"
$logPath = Join-Path $buildRoot "ffmpeg-build.log"
New-Item -ItemType Directory -Force $buildRoot | Out-Null
$containerName = "editors-pro-ffmpeg-" + [guid]::NewGuid().ToString("N")
$abiList = $Abis -join ","

$buildCommand = @'
set -euo pipefail
mkdir -p /workspace/engine/ffmpeg-android-lgpl/.build
exec > /workspace/engine/ffmpeg-android-lgpl/.build/ffmpeg-build.log 2>&1
export DEBIAN_FRONTEND=noninteractive
NDK_HOME=/opt/android-ndk-cache/android-ndk-r28c
if [ ! -x "$NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]; then
  archive=/tmp/android-ndk-r28c-linux.zip
  curl --fail --location --retry 3 https://dl.google.com/android/repository/android-ndk-r28c-linux.zip -o "$archive"
  echo 'a7b54a5de87fecd125a17d54f73c446199e72a64  /tmp/android-ndk-r28c-linux.zip' | sha1sum --check -
  mkdir -p /opt/android-ndk-cache
  unzip -q "$archive" -d /opt/android-ndk-cache
  rm -f "$archive"
fi
export ANDROID_NDK_HOME="$NDK_HOME"
export FFMPEG_BUILD_ROOT=/workspace/engine/ffmpeg-android-lgpl/.build
IFS=',' read -r -a requested_abis <<< "$FFMPEG_ABIS"
bash /workspace/scripts/build_ffmpeg_android.sh "${requested_abis[@]}"
'@

$containerId = & $dockerPath run --detach `
    @dockerHostArgs `
    --name $containerName `
    --mount "type=bind,source=$projectRoot,target=/workspace" `
    --mount "type=volume,source=editors-pro-android-ndk-r28c,target=/opt/android-ndk-cache" `
    --workdir /workspace `
    --cpus 4 `
    --memory 4g `
    --env "FFMPEG_ABIS=$abiList" `
    --env "FFMPEG_JOBS=4" `
    $builderImage bash -lc $buildCommand
if ($LASTEXITCODE -ne 0) {
    throw "Could not start the FFmpeg build container."
}

$start = Get-Date
do {
    Start-Sleep -Seconds 10
    $state = & $dockerPath inspect --format "{{.State.Status}}" $containerName
    if ($LASTEXITCODE -ne 0) {
        throw "Lost contact with the FFmpeg build container; inspect $logPath for progress."
    }
    if ($state.Trim() -eq "running" -and ((Get-Date) - $start).TotalSeconds -ge 30) {
        Write-Host "FFmpeg build is running. Latest build output:"
        if (Test-Path $logPath) { Get-Content $logPath -Tail 6 }
        $start = Get-Date
    }
} while ($state.Trim() -eq "running")

$exitCode = & $dockerPath inspect --format "{{.State.ExitCode}}" $containerName
$null = & $dockerPath rm $containerName
if (Test-Path $logPath) { Get-Content $logPath -Tail 70 }
if ([int]$exitCode -ne 0) {
    throw "FFmpeg Android build failed with exit code $exitCode. Full log: $logPath"
}
