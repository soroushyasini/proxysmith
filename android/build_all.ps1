# build_all.ps1
# Run from: F:\codebase\proxysmith\android

$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
$OutputDir = "build\app\outputs\flutter-apk"
$Version = (Select-String -Path "pubspec.yaml" -Pattern "^version:").Line.Split(":")[1].Trim()

Write-Host "`n=== ProxySmith APK Builder v$Version ===" -ForegroundColor Cyan

Write-Host "`n[1/2] Cleaning..." -ForegroundColor Yellow
flutter clean
Write-Host "`n[2/2] Getting dependencies..." -ForegroundColor Yellow
flutter pub get

$builds = @(
    @{
        name     = "arm64"
        platform = "android-arm64"
        out      = "proxysmith-$Version-arm64.apk"
        exclude  = "armeabi-v7a,x86,x86_64"
    },
    @{
        name     = "arm32"
        platform = "android-arm"
        out      = "proxysmith-$Version-arm32.apk"
        exclude  = "arm64-v8a,x86,x86_64"
    },
    @{
        name     = "universal"
        platform = "android-arm64,android-arm"
        out      = "proxysmith-$Version-universal.apk"
        exclude  = "x86,x86_64"
    }
)

$results = @()
$step = 1

foreach ($build in $builds) {
    Write-Host "`n[Build $step/3] $($build.name)..." -ForegroundColor Yellow

    # Write a temporary gradle.properties with the excludeAbis value
    $gradleProps = "android\gradle.properties"
    $originalContent = Get-Content $gradleProps -Raw -ErrorAction SilentlyContinue
    
    # Append our property
    "`nexcludeAbis=$($build.exclude)" | Add-Content $gradleProps

    flutter build apk --release --target-platform $build.platform

    $exitCode = $LASTEXITCODE

    # Restore gradle.properties
    if ($originalContent) {
        Set-Content $gradleProps $originalContent
    } else {
        # Remove the line we added
        $content = Get-Content $gradleProps
        $content | Where-Object { $_ -notmatch "^excludeAbis=" } | Set-Content $gradleProps
    }

    if ($exitCode -eq 0) {
        $src  = "$OutputDir\app-release.apk"
        $dest = "$OutputDir\$($build.out)"
        Copy-Item $src $dest -Force
        $size = [math]::Round((Get-Item $dest).Length / 1MB, 1)
        Write-Host "  v $($build.out) ($size MB)" -ForegroundColor Green
        $results += "v $($build.name.PadRight(10)) $size MB"
    } else {
        Write-Host "  x $($build.name) FAILED" -ForegroundColor Red
        $results += "x $($build.name.PadRight(10)) FAILED"
    }

    $step++
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
$results | ForEach-Object { Write-Host $_ }
Write-Host "`nAPKs in: F:\codebase\proxysmith\android\$OutputDir" -ForegroundColor Cyan