param([int]$Port = 8080)
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot 'mobile/build/web/index.html'))) {
    throw '먼저 mobile/scripts/build-web.ps1로 웹을 빌드해 주세요.'
}
$nodeVersion = & node --version
if ($LASTEXITCODE -ne 0 -or [Version]($nodeVersion.TrimStart('v')) -lt [Version]'22.22.0') {
    throw 'Node.js 22.22.0 이상이 필요합니다.'
}
$previousPort = $env:PORT
$env:PORT = "$Port"
Push-Location (Join-Path $repositoryRoot 'server')
try {
    & node --env-file-if-exists=.env.local src/index.mjs
    if ($LASTEXITCODE -ne 0) { throw '웹 서버 실행 실패' }
} finally {
    Pop-Location
    $env:PORT = $previousPort
}
