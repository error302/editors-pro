[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ApkPath,
    [string]$AndroidSdkRoot = $env:ANDROID_HOME
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$archive = [IO.Compression.ZipFile]::OpenRead($apk)
$expectedAbis = @('arm64-v8a', 'x86_64')
$requiredLibraries = @('editors_pro_engine', 'avcodec', 'avdevice', 'avfilter', 'avformat', 'avutil', 'swresample', 'swscale')
$verified = @()
try {
    $entries = @($archive.Entries | Where-Object FullName -Match '^lib/[^/]+/[^/]+\.so$')
    if ($entries.Count -eq 0) { throw 'APK contains no native libraries.' }
    foreach ($abi in $expectedAbis) {
        foreach ($library in $requiredLibraries) {
            if (-not $archive.GetEntry("lib/$abi/lib$library.so")) { throw "Missing $abi/lib$library.so" }
        }
    }
    foreach ($entry in $entries) {
        $abi = $entry.FullName.Split('/')[1]
        if ($abi -notin $expectedAbis) { throw "Unsupported ABI packaged: $abi" }
        if ($entry.Name -like '*ffmpegkit*') { throw "Legacy FFmpegKit library packaged: $($entry.FullName)" }
        $memory = [IO.MemoryStream]::new()
        $source = $entry.Open()
        try { $source.CopyTo($memory) } finally { $source.Dispose() }
        $reader = [IO.BinaryReader]::new($memory)
        try {
            $memory.Position = 0
            if ($reader.ReadUInt32() -ne 0x464c457f -or $reader.ReadByte() -ne 2 -or $reader.ReadByte() -ne 1) {
                throw "Expected little-endian ELF64: $($entry.FullName)"
            }
            $memory.Position = 18
            $machine = $reader.ReadUInt16()
            if (($abi -eq 'arm64-v8a' -and $machine -ne 183) -or ($abi -eq 'x86_64' -and $machine -ne 62)) {
                throw "ELF architecture disagrees with directory: $($entry.FullName)"
            }
            $memory.Position = 32
            $headerOffset = $reader.ReadUInt64()
            $memory.Position = 54
            $headerSize = $reader.ReadUInt16()
            $headerCount = $reader.ReadUInt16()
            $loads = 0
            for ($index = 0; $index -lt $headerCount; $index++) {
                $memory.Position = $headerOffset + $index * $headerSize
                if ($reader.ReadUInt32() -ne 1) { continue }
                $loads++
                $memory.Position += 4
                $fileOffset = $reader.ReadUInt64()
                $virtualAddress = $reader.ReadUInt64()
                $memory.Position += 24
                $alignment = $reader.ReadUInt64()
                if ($alignment -lt 16384 -or ($fileOffset % 16384) -ne ($virtualAddress % 16384)) {
                    throw "Native library is not 16 KB aligned: $($entry.FullName)"
                }
            }
            if ($loads -eq 0) { throw "ELF has no loadable segments: $($entry.FullName)" }
            $verified += $entry.FullName
        } finally { $reader.Dispose(); $memory.Dispose() }
    }
    foreach ($font in @('Regular', 'Medium', 'SemiBold', 'Bold')) {
        $entry = $archive.GetEntry("assets/flutter_assets/assets/fonts/Inter-$font.ttf")
        if (-not $entry -or $entry.Length -lt 1000) { throw "Missing or invalid Inter-$font.ttf" }
    }
} finally { $archive.Dispose() }
if (-not $AndroidSdkRoot) { throw 'Pass -AndroidSdkRoot to verify ZIP alignment and signing.' }
$toolsRoot = Join-Path $AndroidSdkRoot 'build-tools'
$tools = Get-ChildItem -LiteralPath $toolsRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
if (-not $tools) { throw "Android build tools missing: $toolsRoot" }
$zipalign = Join-Path $tools.FullName $(if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'zipalign.exe' } else { 'zipalign' })
$apksigner = Join-Path $tools.FullName $(if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'apksigner.bat' } else { 'apksigner' })
& $zipalign -c -P 16 4 $apk
if ($LASTEXITCODE -ne 0) { throw 'APK ZIP alignment verification failed.' }
& $apksigner verify --verbose --print-certs $apk
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
[pscustomobject]@{
    Apk = $apk
    SHA256 = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash
    Abis = $expectedAbis
    NativeLibrariesVerified = $verified.Count
    Native16KBAlignment = $true
    Zip16KBAlignment = $true
    SignatureVerified = $true
} | ConvertTo-Json
Write-Warning 'Signature validity does not establish upload-key identity. Confirm the printed certificate before submission; debug keys are for testing only.'
