param(
    [string]$Flutter = '',
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$Config = 'config/local.json'
)
$ErrorActionPreference = 'Stop'
$mobileRoot = Split-Path $PSScriptRoot -Parent
$repositoryRoot = Split-Path $mobileRoot -Parent
if (-not $Flutter) {
    $bundled = Join-Path $repositoryRoot '.tooling/flutter/bin/flutter.bat'
    $Flutter = if (Test-Path -LiteralPath $bundled) { $bundled } else { (Get-Command flutter -ErrorAction Stop).Source }
}
if (-not $AndroidSdk) { $AndroidSdk = 'D:\Android\Sdk' }
if (-not $JavaHome) { $JavaHome = 'C:\Program Files\Android\Android Studio\jbr' }
$env:ANDROID_HOME = $AndroidSdk
$env:JAVA_HOME = $JavaHome
$env:PUB_CACHE = Join-Path $repositoryRoot '.tooling/pub-cache'
$env:GRADLE_USER_HOME = Join-Path $repositoryRoot '.tooling/gradle-cache'
$env:CI = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
Push-Location $mobileRoot
try {
    $versionText = & $Flutter --version --machine
    if ($LASTEXITCODE -ne 0) { throw 'Flutter 버전 확인 실패' }
    $version = ($versionText -join "`n" | ConvertFrom-Json).frameworkVersion
    if ($version -ne '3.47.5') { throw "Flutter 3.47.5가 필요합니다. 현재 버전: $version" }
    & (Join-Path $PSScriptRoot 'prepare-signing.ps1') -JavaHome $JavaHome
    if (-not (Test-Path -LiteralPath $Config)) {
        $Config = 'config/example.json'
        Write-Warning 'API 키가 없는 APK를 빌드합니다. 경보 이력은 동작하지만 지도·날씨에는 설정 안내가 표시됩니다.'
    }
    & $Flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw '의존성 설치 실패' }
    & $Flutter build apk --release --target-platform android-arm,android-arm64 "--dart-define-from-file=$Config"
    if ($LASTEXITCODE -ne 0) { throw 'APK 빌드 실패' }
    $outputDir = Join-Path $repositoryRoot '.artifacts'
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $output = Join-Path $outputDir 'sandeungseongi-android.apk'
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination $output -Force
    Get-FileHash -LiteralPath $output -Algorithm SHA256 | Format-List
    Write-Output "APK: $output"
} finally { Pop-Location }
