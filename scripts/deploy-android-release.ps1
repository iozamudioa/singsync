$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
chcp 65001 | Out-Null

function Assert-LastExitCode([string]$stepLabel) {
  if ($LASTEXITCODE -ne 0) {
    throw "$stepLabel falló con código de salida $LASTEXITCODE"
  }
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $projectRoot

$packageName = 'net.iozamudioa.lyric_notifier'
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$apkPath = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
$artifactsDir = Join-Path $projectRoot 'build\artifacts'

if (-not (Test-Path $pubspecPath)) {
  throw "No se encontró pubspec.yaml en: $pubspecPath"
}

$versionLine = Select-String -Path $pubspecPath -Pattern '^\s*version:\s*([^\s]+)' | Select-Object -First 1
if (-not $versionLine) {
  throw 'No se pudo leer la versión desde pubspec.yaml'
}

$rawVersion = $versionLine.Matches[0].Groups[1].Value.Trim()
if ($rawVersion -notmatch '^([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?$') {
  throw "Formato de versión no soportado en pubspec: $rawVersion"
}

$expectedVersionName = $Matches[1]
$expectedVersionCode = if ($Matches[2]) { [int]$Matches[2] } else { 1 }

Write-Host "[A/6] Análisis estático (flutter analyze)..." -ForegroundColor Cyan
flutter analyze --no-fatal-infos --no-fatal-warnings
Assert-LastExitCode '[A/6] flutter analyze'

$buildTimestampUtc = (Get-Date).ToUniversalTime()
$buildTimestampCompact = $buildTimestampUtc.ToString('yyyyMMdd-HHmmss')

Write-Host "[B/6] Compilando APK release..." -ForegroundColor Cyan
Write-Host "Build timestamp (UTC): $($buildTimestampUtc.ToString('yyyy-MM-dd HH:mm:ss'))"
flutter build apk --release
Assert-LastExitCode '[B/6] flutter build apk --release'

if (-not (Test-Path $apkPath)) {
  throw "No se encontró el APK generado en: $apkPath"
}

if (-not (Test-Path $artifactsDir)) {
  New-Item -ItemType Directory -Path $artifactsDir | Out-Null
}

$artifactApkPath = Join-Path $artifactsDir "app-release-$buildTimestampCompact.apk"
Copy-Item -Path $apkPath -Destination $artifactApkPath -Force

Write-Host "[C/6] Verificando dispositivo ADB..." -ForegroundColor Cyan
adb start-server | Out-Null
Assert-LastExitCode '[C/6] adb start-server'
$adbDevices = adb devices -l | Out-String
Assert-LastExitCode '[C/6] adb devices -l'
$connected = ($adbDevices -split "`r?`n") |
  ForEach-Object { $_.Trim() } |
  Where-Object {
    $_ -and
    $_ -notmatch '^List of devices attached' -and
    $_ -match '\bdevice\b' -and
    $_ -notmatch '\bunauthorized\b|\boffline\b'
  }
if (-not $connected) {
  throw 'No hay dispositivos ADB conectados (estado device).'
}

Write-Host "[D/6] Instalando APK con -r..." -ForegroundColor Cyan
$installOutput = adb install -r "$artifactApkPath" | Out-String
Assert-LastExitCode '[D/6] adb install -r'
if ($installOutput -notmatch 'Success') {
  throw "Instalación falló. Salida:`n$installOutput"
}

Write-Host "[E/6] Validando versión y timestamp instalados..." -ForegroundColor Cyan
$dump = adb shell dumpsys package $packageName | Out-String
Assert-LastExitCode '[E/6] adb shell dumpsys package'

$installedVersionName = ([regex]::Match($dump, 'versionName=([^\s\r\n]+)')).Groups[1].Value
$installedVersionCodeRaw = ([regex]::Match($dump, 'versionCode=([0-9]+)')).Groups[1].Value
$installedUpdateTimeRaw = ([regex]::Match($dump, 'lastUpdateTime=([^\r\n]+)')).Groups[1].Value.Trim()

if ([string]::IsNullOrWhiteSpace($installedVersionName) -or [string]::IsNullOrWhiteSpace($installedVersionCodeRaw)) {
  throw 'No se pudo leer versionName/versionCode desde dumpsys package.'
}

if ([string]::IsNullOrWhiteSpace($installedUpdateTimeRaw)) {
  throw 'No se pudo leer lastUpdateTime desde dumpsys package.'
}

$installedVersionCode = [int]$installedVersionCodeRaw

try {
  $installedUpdateTimeUtc = (Get-Date $installedUpdateTimeRaw).ToUniversalTime()
} catch {
  throw "No se pudo parsear lastUpdateTime: '$installedUpdateTimeRaw'"
}

if ($installedVersionName -ne $expectedVersionName -or $installedVersionCode -ne $expectedVersionCode) {
  throw @"
Versión instalada no coincide.
Esperada: versionName=$expectedVersionName versionCode=$expectedVersionCode
Instalada: versionName=$installedVersionName versionCode=$installedVersionCode
"@
}

if ($installedUpdateTimeUtc -lt $buildTimestampUtc.AddMinutes(-1)) {
  throw @"
El timestamp instalado parece anterior al build actual.
Build UTC:      $($buildTimestampUtc.ToString('yyyy-MM-dd HH:mm:ss'))
lastUpdateTime: $installedUpdateTimeRaw
"@
}

Write-Host "[F/6] Lanzando app..." -ForegroundColor Cyan
adb shell monkey -p $packageName -c android.intent.category.LAUNCHER 1 | Out-Null
Assert-LastExitCode '[F/6] adb shell monkey'

Write-Host "OK: analyze, build, install (-r), validación y launch completados." -ForegroundColor Green
Write-Host "Paquete: $packageName"
Write-Host "Versión: $installedVersionName+$installedVersionCode"
Write-Host "Build timestamp (UTC): $($buildTimestampUtc.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "APK instalado: $artifactApkPath"
Write-Host "lastUpdateTime (device): $installedUpdateTimeRaw"
