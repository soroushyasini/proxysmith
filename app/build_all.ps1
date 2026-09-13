# Builds ARMv7, ARM64, and universal Android release APKs plus a Play bundle.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$AppRoot = $PSScriptRoot
$ApkOutputDir = Join-Path $AppRoot 'build\app\outputs\flutter-apk'
$BundleOutputDir = Join-Path $AppRoot 'build\app\outputs\bundle\release'
$ReleaseDir = Join-Path $AppRoot 'release'
$Pubspec = Join-Path $AppRoot 'pubspec.yaml'
$VersionLine = Select-String -LiteralPath $Pubspec -Pattern '^version:' | Select-Object -First 1
if (-not $VersionLine) { throw 'No version field was found in pubspec.yaml.' }
$Version = ($VersionLine.Line -split ':', 2)[1].Trim()
$SafeVersion = $Version -replace '\+', '-'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not available in PATH.'
}

New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null
Push-Location $AppRoot
try {
    Write-Host "ProxySmith Android builder v$Version" -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed.' }

    flutter test
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }

    flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
    if ($LASTEXITCODE -ne 0) { throw 'Split APK build failed.' }

    flutter build apk --release --target-platform android-arm,android-arm64
    if ($LASTEXITCODE -ne 0) { throw 'Universal APK build failed.' }

    flutter build appbundle --release --target-platform android-arm,android-arm64
    if ($LASTEXITCODE -ne 0) { throw 'Google Play App Bundle build failed.' }

    $Artifacts = @(
        @{ Source = (Join-Path $ApkOutputDir 'app-armeabi-v7a-release.apk'); Name = "proxysmith-$SafeVersion-armv7.apk" },
        @{ Source = (Join-Path $ApkOutputDir 'app-arm64-v8a-release.apk'); Name = "proxysmith-$SafeVersion-arm64.apk" },
        @{ Source = (Join-Path $ApkOutputDir 'app-release.apk'); Name = "proxysmith-$SafeVersion-universal.apk" },
        @{ Source = (Join-Path $BundleOutputDir 'app-release.aab'); Name = "proxysmith-$SafeVersion-play.aab" }
    )
    foreach ($Artifact in $Artifacts) {
        $Source = $Artifact.Source
        if (-not (Test-Path -LiteralPath $Source)) { throw "Expected artifact is missing: $Source" }
        Copy-Item -LiteralPath $Source -Destination (Join-Path $ReleaseDir $Artifact.Name) -Force
    }

    $ChecksumPath = Join-Path $ReleaseDir 'SHA256SUMS.txt'
    $Checksums = foreach ($Artifact in $Artifacts) {
        $Path = Join-Path $ReleaseDir $Artifact.Name
        $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        "$Hash  $($Artifact.Name)"
    }
    $Utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($ChecksumPath, [string[]]$Checksums, $Utf8WithoutBom)
    Write-Host "Release APKs, Play bundle, and checksums are ready in $ReleaseDir" -ForegroundColor Green
}
finally {
    Pop-Location
}
