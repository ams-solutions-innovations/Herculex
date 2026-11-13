# Uploads build/web to the Cloudflare Pages project behind app.herculex.app.
# Run tool/web/build_web.ps1 first. Needs `npx wrangler login` once.
#
#   pwsh tool/web/deploy_web.ps1 [-Branch main]
#
# A branch other than the production one creates a preview deployment at
# <branch>.herculex-flutter-app.pages.dev.

param([string]$Branch = 'main', [string]$Project = 'herculex-flutter-app')

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$out = Join-Path $root 'build\web'
if (-not (Test-Path (Join-Path $out 'index.html'))) {
  throw 'build/web is missing — run tool/web/build_web.ps1 first.'
}

npx wrangler pages deploy $out --project-name $Project --branch $Branch
if ($LASTEXITCODE -ne 0) { throw 'wrangler pages deploy failed' }
