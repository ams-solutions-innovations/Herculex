# Release build of the web app (app.herculex.app) into build/web.
#
#   pwsh tool/web/build_web.ps1 [-DefinesFile tool/web/defines.prod.json]
#
# The defines file holds SUPABASE_URL, SUPABASE_ANON_KEY, WEB_APP_URL, ...
# (see defines.example.json). It is gitignored.

param([string]$DefinesFile = 'tool/web/defines.prod.json')

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Push-Location $root
try {
  if (-not (Test-Path $DefinesFile)) {
    throw "Missing $DefinesFile — copy tool/web/defines.example.json and fill it in."
  }

  pwsh -NoProfile -File tool/web/fetch_web_assets.ps1
  if ($LASTEXITCODE -ne 0) { throw 'fetch_web_assets failed' }

  # --no-web-resources-cdn: serve CanvasKit ourselves (no gstatic dependency
  # at startup, simpler CSP). --source-maps: readable stack traces in ErrorLog.
  flutter build web --release --no-web-resources-cdn --source-maps `
    --dart-define-from-file=$DefinesFile
  if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }

  # Cloudflare Pages rejects files over 25 MiB.
  $limit = 25MB
  $tooBig = Get-ChildItem build/web -Recurse -File | Where-Object { $_.Length -gt $limit }
  if ($tooBig) {
    $tooBig | ForEach-Object { Write-Host "$($_.FullName) $([math]::Round($_.Length / 1MB, 1)) MiB" }
    throw 'build/web has files over the Cloudflare Pages 25 MiB limit'
  }
  if (Get-ChildItem build/web -Recurse -File -Filter 'food_database_eu*') {
    throw 'The bundled food database leaked into the web build (check pubspec platforms:)'
  }

  $size = (Get-ChildItem build/web -Recurse -File | Measure-Object Length -Sum).Sum
  Write-Host ("build/web ready: {0:N1} MiB" -f ($size / 1MB))
} finally {
  Pop-Location
}
