[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$BuildScript = Join-Path $RepoRoot 'app\build_all.ps1'
$Source = Get-Content -Raw -LiteralPath $BuildScript

if ($Source -notmatch 'flutter\s+build\s+appbundle\s+--release') {
    throw 'build_all.ps1 must build a release Android App Bundle for Google Play.'
}

if ($Source -notmatch 'app-release\.aab') {
    throw 'build_all.ps1 must package the generated Android App Bundle.'
}

if ($Source -notmatch 'play\.aab') {
    throw 'build_all.ps1 must give the Play bundle a release-specific name.'
}

Write-Host 'build_all.ps1 packages a Google Play Android App Bundle.'
