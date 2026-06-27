# build_all.ps1
# Run from: F:\codebase\proxysmith\android

$env:PUB_HOSTED_URL          = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"

$OutputDir = "build\app\outputs\flutter-apk"

# Read version straight from pubspec.yaml  (e.g. "1.1.0+2")
$Version = (Select-String -Path "pubspec.yaml" -Pattern "^version:").Line.Split(":")[1].Trim()

Write-Host "`n=== ProxySmith APK Builder v$Version ===" -ForegroundColor Cyan

Write-Host "`n[1/2] Cleaning..." -ForegroundColor Yellow
flutter clean

Write-Host "`n[2/2] Getting dependencies..." -ForegroundColor Yellow
flutter pub get

# ── Build targets ─────────────────────────────────────────────────────────
# Filename convention: proxysmith-<version>-<arch>.apk
#   armv8   = arm64-v8a   → modern phones (2015+)
#   armv7   = armeabi-v7a → older / budget phones
#   universal              → fat APK, both ABIs, largest file
$builds = @(
    @{
        label    = "ARMv8 (arm64-v8a)"          # shown in console
        filename = "proxysmith-$Version-armv8.apk"
        platform = "android-arm64"
        exclude  = "armeabi-v7a,x86,x86_64"
    },
    @{
        label    = "ARMv7 (armeabi-v7a)"
        filename = "proxysmith-$Version-armv7.apk"
        platform = "android-arm"
        exclude  = "arm64-v8a,x86,x86_64"
    },
    @{
        label    = "universal (armv8 + armv7)"
        filename = "proxysmith-$Version-universal.apk"
        platform = "android-arm64,android-arm"
        exclude  = "x86,x86_64"
    }
)

# ── Build loop ─────────────────────────────────────────────────────────────
$results     = @()
$gradleProps = "android\gradle.properties"
$step        = 1

foreach ($build in $builds) {
    Write-Host "`n[Build $step/3] $($build.label)..." -ForegroundColor Yellow

    # Temporarily append excludeAbis to gradle.properties, restore after build
    $originalContent = Get-Content $gradleProps -Raw -ErrorAction SilentlyContinue
    "`nexcludeAbis=$($build.exclude)" | Add-Content $gradleProps

    flutter build apk --release --target-platform $build.platform
    $exitCode = $LASTEXITCODE

    # Always restore gradle.properties, even if the build failed
    if ($originalContent) {
        Set-Content $gradleProps $originalContent
    } else {
        $content = Get-Content $gradleProps
        $content | Where-Object { $_ -notmatch "^excludeAbis=" } | Set-Content $gradleProps
    }

    if ($exitCode -eq 0) {
        $src  = "$OutputDir\app-release.apk"
        $dest = "$OutputDir\$($build.filename)"
        Copy-Item $src $dest -Force
        $size = [math]::Round((Get-Item $dest).Length / 1MB, 1)
        Write-Host "  v $($build.filename) ($size MB)" -ForegroundColor Green
        $results += [PSCustomObject]@{ Status = "OK"; File = $build.filename; Size = "$size MB" }
    } else {
        Write-Host "  x $($build.label) FAILED" -ForegroundColor Red
        $results += [PSCustomObject]@{ Status = "FAIL"; File = $build.label; Size = "-" }
    }

    $step++
}

# ── Summary ────────────────────────────────────────────────────────────────
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Host "APKs in: F:\codebase\proxysmith\android\$OutputDir`n" -ForegroundColor Cyan