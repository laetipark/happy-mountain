param([string]$Flutter = '')
$ErrorActionPreference = 'Stop'
$mobileRoot = Split-Path $PSScriptRoot -Parent
$repositoryRoot = Split-Path $mobileRoot -Parent
if (-not $Flutter) {
    $bundled = Join-Path $repositoryRoot '.tooling/flutter/bin/flutter.bat'
    $Flutter = if (Test-Path -LiteralPath $bundled) { $bundled } else { (Get-Command flutter -ErrorAction Stop).Source }
}
$env:PUB_CACHE = Join-Path $repositoryRoot '.tooling/pub-cache'
$env:CI = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
Push-Location $mobileRoot
try {
    $versionText = & $Flutter --version --machine
    if ($LASTEXITCODE -ne 0) { throw 'Flutter 버전 확인 실패' }
    $version = ($versionText -join "`n" | ConvertFrom-Json).frameworkVersion
    if ($version -ne '3.47.5') { throw "Flutter 3.47.5가 필요합니다. 현재 버전: $version" }
    & $Flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw '의존성 설치 실패' }
    # Web configuration is loaded at runtime. Never pass native config/local.json here.
    & $Flutter build web --release --no-pub --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw '웹 빌드 실패' }

    $artifactRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot '.artifacts'))
    $bundleRoot = [IO.Path]::GetFullPath((Join-Path $artifactRoot 'sandeungseongi-web'))
    if (-not $bundleRoot.StartsWith($artifactRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw '웹 산출물 경로가 올바르지 않습니다.'
    }
    if (Test-Path -LiteralPath $bundleRoot) {
        $resolvedBundle = (Resolve-Path -LiteralPath $bundleRoot).Path
        if ($resolvedBundle -ne $bundleRoot -or ((Get-Item -LiteralPath $resolvedBundle).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw '웹 산출물 경로에 링크를 사용할 수 없습니다.'
        }
        Remove-Item -LiteralPath $resolvedBundle -Recurse -Force
    }
    $bundleWeb = Join-Path $bundleRoot 'mobile/build/web'
    $bundleServer = Join-Path $bundleRoot 'server'
    New-Item -ItemType Directory -Force -Path $bundleWeb, $bundleServer | Out-Null
    Get-ChildItem -LiteralPath 'build/web' -Force | Copy-Item -Destination $bundleWeb -Recurse -Force
    foreach ($sourceName in @('src', 'test', 'package.json', '.node-version', '.env.example', 'README.md')) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot "server/$sourceName") -Destination $bundleServer -Recurse -Force
    }
    Copy-Item -LiteralPath 'docs/web.md' -Destination (Join-Path $bundleRoot 'WEB-README.md')
    Copy-Item -LiteralPath 'docs/verification.md' -Destination (Join-Path $bundleRoot 'VERIFICATION.md')
    $archive = Join-Path $artifactRoot 'sandeungseongi-web.zip'
    Compress-Archive -Path $bundleRoot -DestinationPath $archive -Force
    Get-FileHash -LiteralPath $archive -Algorithm SHA256 | Format-List
    Write-Output "웹 패키지: $archive"
    Write-Output '로컬 실행: mobile/scripts/serve-web.ps1'
} finally { Pop-Location }
