param([string]$JavaHome = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
$mobileRoot = Split-Path $PSScriptRoot -Parent
$propertiesPath = Join-Path $mobileRoot 'android/key.properties'
$keystorePath = Join-Path $mobileRoot 'android/app/test-signing.jks'
if ((Test-Path -LiteralPath $propertiesPath) -and (Test-Path -LiteralPath $keystorePath)) {
    Write-Output '기존 테스트 서명키를 사용합니다.'
    exit 0
}
if ((Test-Path -LiteralPath $propertiesPath) -or (Test-Path -LiteralPath $keystorePath)) {
    throw '서명키와 key.properties 중 하나만 있습니다. 기존 서명 파일을 복구해 주세요. 자동 덮어쓰기는 하지 않습니다.'
}
if (-not $JavaHome) { $JavaHome = 'C:\Program Files\Android\Android Studio\jbr' }
$keytool = Join-Path $JavaHome 'bin/keytool.exe'
if (-not (Test-Path -LiteralPath $keytool)) { throw 'JDK 17 이상 경로를 -JavaHome으로 지정해 주세요.' }
$randomBytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($randomBytes) } finally { $rng.Dispose() }
$password = [Convert]::ToBase64String($randomBytes)
# Environment-based keytool password input avoids passwords in process arguments.
$env:HAPPY_MOUNTAIN_SIGNING_PASSWORD = $password
try {
    & $keytool -genkeypair -noprompt -keystore $keystorePath -storetype JKS -alias personal-test -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Happy Mountain Personal Test' -storepass:env HAPPY_MOUNTAIN_SIGNING_PASSWORD -keypass:env HAPPY_MOUNTAIN_SIGNING_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw '테스트 서명키 생성 실패' }
    @("storeFile=test-signing.jks", "storePassword=$password", "keyPassword=$password", 'keyAlias=personal-test') | Set-Content -LiteralPath $propertiesPath -Encoding ascii
} finally {
    Remove-Item Env:HAPPY_MOUNTAIN_SIGNING_PASSWORD -ErrorAction SilentlyContinue
}
Write-Output '테스트 서명키를 생성했습니다. android/key.properties와 android/app/test-signing.jks를 함께 보관하세요.'
