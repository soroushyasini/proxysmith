[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$BuildScript = Join-Path $RepoRoot 'app\build_all.ps1'
$Source = Get-Content -Raw -LiteralPath $BuildScript

if ($Source -match '(?i)-Encoding\s+["'']?utf8NoBOM') {
    throw 'build_all.ps1 uses the PowerShell 7-only utf8NoBOM encoding name.'
}

if ($Source -notmatch '\[System\.Text\.UTF8Encoding\].*\$false') {
    throw 'build_all.ps1 must explicitly write UTF-8 checksums without a BOM.'
}

Write-Host 'build_all.ps1 is compatible with Windows PowerShell 5.1.'
