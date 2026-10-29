# Puts the two files drift needs on the web into web/:
#   web/sqlite3.wasm     — from the sqlite3.dart release matching pubspec.lock
#   web/drift_worker.js  — compiled from tool/web/drift_worker.dart
# Both are generated (gitignored). Re-run after bumping drift or sqlite3.
#
#   pwsh tool/web/fetch_web_assets.ps1 [-Force]

param([switch]$Force)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$web = Join-Path $root 'web'

function Get-LockedVersion([string]$package) {
  $lock = Get-Content (Join-Path $root 'pubspec.lock') -Raw
  $match = [regex]::Match($lock, "(?ms)^  ${package}:\s*\n.*?^    version: ""([^""]+)""")
  if (-not $match.Success) { throw "$package not found in pubspec.lock" }
  return $match.Groups[1].Value
}

$sqliteVersion = Get-LockedVersion 'sqlite3'
$driftVersion = Get-LockedVersion 'drift'
$stamp = Join-Path $web '.web-assets-version'
$expected = "sqlite3=$sqliteVersion drift=$driftVersion"

if (-not $Force -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $expected) `
    -and (Test-Path (Join-Path $web 'sqlite3.wasm')) -and (Test-Path (Join-Path $web 'drift_worker.js'))) {
  Write-Host "web assets up to date ($expected)"
  exit 0
}

$wasmUrl = "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$sqliteVersion/sqlite3.wasm"
Write-Host "Downloading $wasmUrl"
Invoke-WebRequest -Uri $wasmUrl -OutFile (Join-Path $web 'sqlite3.wasm')
$hash = (Get-FileHash (Join-Path $web 'sqlite3.wasm') -Algorithm SHA256).Hash
Write-Host "sqlite3.wasm sha256 $hash"

Write-Host "Compiling drift_worker.js (drift $driftVersion)"
Push-Location $root
try {
  dart compile js -O4 tool/web/drift_worker.dart -o web/drift_worker.js
  if ($LASTEXITCODE -ne 0) { throw 'dart compile js failed' }
} finally {
  Pop-Location
}
# dart2js leaves these next to the output.
Remove-Item (Join-Path $web 'drift_worker.js.deps') -ErrorAction SilentlyContinue
Remove-Item (Join-Path $web 'drift_worker.js.map') -ErrorAction SilentlyContinue

Set-Content -Path $stamp -Value $expected
Write-Host "web assets ready ($expected)"
