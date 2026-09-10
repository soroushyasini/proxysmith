# Builds ARMv7, ARM64, and universal Android release APKs without editing project files.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$AppRoot = $PSScriptRoot
$OutputDir = Join-Path $AppRoot 'build\app\outputs\flutter-apk'
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

    $Artifacts = @(
        @{ Source = 'app-armeabi-v7a-release.apk'; Name = "proxysmith-$SafeVersion-armv7.apk" },
        @{ Source = 'app-arm64-v8a-release.apk'; Name = "proxysmith-$SafeVersion-arm64.apk" },
        @{ Source = 'app-release.apk'; Name = "proxysmith-$SafeVersion-universal.apk" }
    )
    foreach ($Artifact in $Artifacts) {
        $Source = Join-Path $OutputDir $Artifact.Source
        if (-not (Test-Path -LiteralPath $Source)) { throw "Expected artifact is missing: $Source" }
        Copy-Item -LiteralPath $Source -Destination (Join-Path $ReleaseDir $Artifact.Name) -Force
    }

    $ChecksumPath = Join-Path $ReleaseDir 'SHA256SUMS.txt'
    $Checksums = foreach ($Artifact in $Artifacts) {
        $Path = Join-Path $ReleaseDir $Artifact.Name
        $Hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        "$Hash  $($Artifact.Name)"
    }
    Set-Content -LiteralPath $ChecksumPath -Value $Checksums -Encoding utf8NoBOM
    Write-Host "Release APKs and checksums are ready in $ReleaseDir" -ForegroundColor Green
}
finally {
    Pop-Location
}
