param(
  [ValidateSet('dev', 'pro')]
  [string]$Profile = 'dev'
)

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

$packageName = 'net.iozamudioa.singsync'
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$artifactsDir = Join-Path $projectRoot 'build\artifacts'

$buildMode = 'release'
$apkPath = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'

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

Write-Host "[B/6] Compilando APK $buildMode (perfil=$Profile)..." -ForegroundColor Cyan
Write-Host "Build timestamp (UTC): $($buildTimestampUtc.ToString('yyyy-MM-dd HH:mm:ss'))"
flutter build apk --$buildMode --dart-define=APP_PROFILE=$Profile
Assert-LastExitCode "[B/6] flutter build apk --$buildMode"

if (-not (Test-Path $apkPath)) {
  throw "No se encontró el APK generado en: $apkPath"
}

if (-not (Test-Path $artifactsDir)) {
  New-Item -ItemType Directory -Path $artifactsDir | Out-Null
}

$artifactApkPath = Join-Path $artifactsDir "app-$Profile-$buildMode-$buildTimestampCompact.apk"
Copy-Item -Path $apkPath -Destination $artifactApkPath -Force

Write-Host "[C/6] Verificando dispositivo ADB..." -ForegroundColor Cyan
adb start-server | Out-Null
Assert-LastExitCode '[C/6] adb start-server'
$adbDevices = adb devices -l | Out-String
Assert-LastExitCode '[C/6] adb devices -l'
$connectedDevices = @()
($adbDevices -split "`r?`n") |
  ForEach-Object { $_.Trim() } |
  ForEach-Object {
    if (-not $_) { return }
    if ($_ -match '^List of devices attached') { return }
    if ($_ -match '\bunauthorized\b|\boffline\b') { return }
    if ($_ -match '^(\S+)\s+device\b') {
      $connectedDevices += [pscustomobject]@{
        Serial = $Matches[1]
        Raw = $_
      }
    }
  }

if (-not $connectedDevices -or $connectedDevices.Count -eq 0) {
  throw 'No hay dispositivos ADB conectados (estado device).'
}

Write-Host "Dispositivos detectados:" -ForegroundColor DarkCyan
foreach ($device in $connectedDevices) {
  Write-Host " - $($device.Raw)"
}

Write-Host "[C.5/6] Verificando variante instalada (debug/release)..." -ForegroundColor Cyan
foreach ($device in $connectedDevices) {
  $serial = $device.Serial
  Write-Host "  -> [$serial] verificando variante instalada" -ForegroundColor DarkCyan
  $installedDump = adb -s $serial shell dumpsys package $packageName | Out-String
  Assert-LastExitCode "[C.5/6] adb -s $serial shell dumpsys package (pre-install)"

  $isInstalled = $installedDump -match 'versionName='
  if ($isInstalled) {
    $installedIsDebug = $installedDump -match '\bDEBUGGABLE\b'
    $targetIsDebug = $buildMode -eq 'debug'

    if ($installedIsDebug -ne $targetIsDebug) {
      $installedVariant = if ($installedIsDebug) { 'debug' } else { 'release' }
      Write-Host "  -> [$serial] variante instalada '$installedVariant' y build '$buildMode'. Desinstalando..." -ForegroundColor Yellow
      adb -s $serial uninstall $packageName | Out-Null
      Assert-LastExitCode "[C.5/6] adb -s $serial uninstall (mismatch debug/release)"
    }
  }
}

Write-Host "[D/6] Instalando APK con -r en todos los dispositivos..." -ForegroundColor Cyan
foreach ($device in $connectedDevices) {
  $serial = $device.Serial
  Write-Host "  -> [$serial] instalando APK" -ForegroundColor DarkCyan
  $installOutput = adb -s $serial install -r "$artifactApkPath" | Out-String
  if ($LASTEXITCODE -ne 0 -or $installOutput -notmatch 'Success') {
    if ($installOutput -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
      Write-Host "  -> [$serial] INSTALL_FAILED_UPDATE_INCOMPATIBLE. Desinstalando y reintentando..." -ForegroundColor Yellow
      adb -s $serial uninstall $packageName | Out-Null
      Assert-LastExitCode "[D/6] adb -s $serial uninstall (retry by INSTALL_FAILED_UPDATE_INCOMPATIBLE)"

      $installOutput = adb -s $serial install -r "$artifactApkPath" | Out-String
      if ($LASTEXITCODE -ne 0 -or $installOutput -notmatch 'Success') {
        throw "[$serial] Instalación falló tras retry. Salida:`n$installOutput"
      }
    } else {
      throw "[$serial] Instalación falló. Salida:`n$installOutput"
    }
  }
}

Write-Host "[E/6] Validando versión y timestamp instalados en todos los dispositivos..." -ForegroundColor Cyan
$installedSummary = @()
foreach ($device in $connectedDevices) {
  $serial = $device.Serial
  Write-Host "  -> [$serial] validando instalación" -ForegroundColor DarkCyan
  $dump = adb -s $serial shell dumpsys package $packageName | Out-String
  Assert-LastExitCode "[E/6] adb -s $serial shell dumpsys package"

  $installedVersionName = ([regex]::Match($dump, 'versionName=([^\s\r\n]+)')).Groups[1].Value
  $installedVersionCodeRaw = ([regex]::Match($dump, 'versionCode=([0-9]+)')).Groups[1].Value
  $installedUpdateTimeRaw = ([regex]::Match($dump, 'lastUpdateTime=([^\r\n]+)')).Groups[1].Value.Trim()

  if ([string]::IsNullOrWhiteSpace($installedVersionName) -or [string]::IsNullOrWhiteSpace($installedVersionCodeRaw)) {
    throw "[$serial] No se pudo leer versionName/versionCode desde dumpsys package."
  }

  if ([string]::IsNullOrWhiteSpace($installedUpdateTimeRaw)) {
    throw "[$serial] No se pudo leer lastUpdateTime desde dumpsys package."
  }

  $installedVersionCode = [int]$installedVersionCodeRaw

  try {
    $installedUpdateTimeUtc = (Get-Date $installedUpdateTimeRaw).ToUniversalTime()
  } catch {
    throw "[$serial] No se pudo parsear lastUpdateTime: '$installedUpdateTimeRaw'"
  }

  if ($installedVersionName -ne $expectedVersionName -or $installedVersionCode -ne $expectedVersionCode) {
    throw @"
[$serial] Versión instalada no coincide.
Esperada: versionName=$expectedVersionName versionCode=$expectedVersionCode
Instalada: versionName=$installedVersionName versionCode=$installedVersionCode
"@
  }

  if ($installedUpdateTimeUtc -lt $buildTimestampUtc.AddMinutes(-1)) {
    throw @"
[$serial] El timestamp instalado parece anterior al build actual.
Build UTC:      $($buildTimestampUtc.ToString('yyyy-MM-dd HH:mm:ss'))
lastUpdateTime: $installedUpdateTimeRaw
"@
  }

  $installedSummary += [pscustomobject]@{
    Serial = $serial
    VersionName = $installedVersionName
    VersionCode = $installedVersionCode
    LastUpdateTimeRaw = $installedUpdateTimeRaw
  }
}

Write-Host "[F/6] Lanzando app en todos los dispositivos..." -ForegroundColor Cyan
foreach ($device in $connectedDevices) {
  $serial = $device.Serial
  Write-Host "  -> [$serial] launch" -ForegroundColor DarkCyan
  adb -s $serial shell monkey -p $packageName -c android.intent.category.LAUNCHER 1 | Out-Null
  Assert-LastExitCode "[F/6] adb -s $serial shell monkey"
}

Write-Host "OK: analyze, build, install (-r), validación y launch completados en $($connectedDevices.Count) dispositivo(s)." -ForegroundColor Green
Write-Host "Perfil: $Profile"
Write-Host "Build mode: $buildMode"
Write-Host "Paquete: $packageName"
if ($installedSummary.Count -gt 0) {
  Write-Host "Dispositivos instalados:" -ForegroundColor DarkCyan
  foreach ($item in $installedSummary) {
    Write-Host " - $($item.Serial): $($item.VersionName)+$($item.VersionCode) | lastUpdateTime=$($item.LastUpdateTimeRaw)"
  }
}
Write-Host "Build timestamp (UTC): $($buildTimestampUtc.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "APK instalado: $artifactApkPath"
