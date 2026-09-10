# Copies the pre-built Go pipeline binary into the Flutter Windows release
# bundle, at the path DesktopPipelineService expects (§7 of the desktop
# port handoff doc). Run this AFTER `flutter build windows --release`.
#
# Usage: .\scripts\bundle_desktop_binaries.ps1

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Src      = Join-Path $RepoRoot "app\windows\bin\proxysmith-pipeline-windows-amd64.exe"
$DestDir  = Join-Path $RepoRoot "app\build\windows\x64\runner\Release\bin"

if (-not (Test-Path $Src)) {
    Write-Error "$Src not found. Build it first (see app/windows/bin/README.md)."
    exit 1
}

$ReleaseDir = Split-Path -Parent $DestDir
if (-not (Test-Path $ReleaseDir)) {
    Write-Error "$ReleaseDir not found. Run 'flutter build windows --release' first."
    exit 1
}

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
Copy-Item $Src -Destination $DestDir -Force
Write-Host "Copied to $DestDir\proxysmith-pipeline-windows-amd64.exe"
