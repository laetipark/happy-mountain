param([string]$JavaHome = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
$mobileRoot = Split-Path $PSScriptRoot -Parent
$propertiesPath = Join-Path $mobileRoot 'android/key.properties'
if (-not (Test-Path -LiteralPath $propertiesPath)) { throw '먼저 prepare-signing.ps1을 실행해 주세요.' }
if (-not $JavaHome) { $JavaHome = 'C:\Program Files\Android\Android Studio\jbr' }
$properties = @{}
foreach ($line in Get-Content -LiteralPath $propertiesPath) {
    $pair = $line -split '=', 2
    if ($pair.Length -eq 2) { $properties[$pair[0]] = $pair[1] }
}
$keystore = Join-Path $mobileRoot ('android/app/' + $properties['storeFile'])
$certificateDirectory = Join-Path $mobileRoot '.dart_tool/signing'
New-Item -ItemType Directory -Force -Path $certificateDirectory | Out-Null
$certificate = Join-Path $certificateDirectory 'personal-test.der'
$env:HAPPY_MOUNTAIN_SIGNING_PASSWORD = $properties['storePassword']
try {
    & (Join-Path $JavaHome 'bin/keytool.exe') -exportcert -keystore $keystore -alias $properties['keyAlias'] -storepass:env HAPPY_MOUNTAIN_SIGNING_PASSWORD -file $certificate
    if ($LASTEXITCODE -ne 0) { throw '인증서 조회 실패' }
} finally {
    Remove-Item Env:HAPPY_MOUNTAIN_SIGNING_PASSWORD -ErrorAction SilentlyContinue
}
$sha1 = [System.Security.Cryptography.SHA1]::Create()
try { $hash = [Convert]::ToBase64String($sha1.ComputeHash([System.IO.File]::ReadAllBytes($certificate))) }
finally { $sha1.Dispose() }
Write-Output '카카오 Android 패키지: com.example.happy_mountain.mobile'
Write-Output "카카오 Android 키 해시: $hash"
