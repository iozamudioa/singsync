Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-AdbAvailable {
    $adb = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adb) {
        Write-Host "No se encontró 'adb' en PATH." -ForegroundColor Red
        Write-Host "Instala Android Platform Tools o abre una terminal con adb disponible." -ForegroundColor Yellow
        exit 1
    }
}

function Get-ConnectedDevices {
    $lines = adb devices | Select-Object -Skip 1
    $devices = @()

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($trimmed -match '^(\S+)\s+(\S+)$') {
            $serial = $Matches[1]
            $state = $Matches[2]
            $model = ''

            if ($state -eq 'device') {
                try {
                    $model = (adb -s $serial shell getprop ro.product.model 2>$null).Trim()
                } catch {
                    $model = ''
                }
            }

            $devices += [PSCustomObject]@{
                Serial = $serial
                State  = $state
                Model  = $model
            }
        }
    }

    return $devices
}

function Select-Device([array]$devices) {
    $ready = @($devices | Where-Object { $_.State -eq 'device' })

    if ($ready.Count -eq 0) {
        Write-Host "No hay dispositivos en estado 'device'." -ForegroundColor Red
        if ($devices.Count -gt 0) {
            Write-Host "Estados detectados:" -ForegroundColor Yellow
            $devices | ForEach-Object {
                Write-Host "- $($_.Serial) [$($_.State)]"
            }
        }
        exit 1
    }

    Write-Host "Dispositivos disponibles:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $ready.Count; $i++) {
        $n = $i + 1
        $modelText = if ([string]::IsNullOrWhiteSpace($ready[$i].Model)) { 'modelo desconocido' } else { $ready[$i].Model }
        Write-Host ("[{0}] {1} ({2})" -f $n, $ready[$i].Serial, $modelText)
    }

    while ($true) {
        $inputValue = Read-Host "Elige el número del dispositivo"
        $selectedIndex = 0
        if ([int]::TryParse($inputValue, [ref]$selectedIndex)) {
            if ($selectedIndex -ge 1 -and $selectedIndex -le $ready.Count) {
                return $ready[$selectedIndex - 1]
            }
        }
        Write-Host "Selección inválida. Intenta de nuevo." -ForegroundColor Yellow
    }
}

function Get-SessionSnapshotFlagPath([string]$packageName) {
    return "/sdcard/Android/data/$packageName/files/debug_session_snapshot.flag"
}

function Get-SessionSnapshotFlagEnabled([string]$serial, [string]$packageName) {
    $flagPath = Get-SessionSnapshotFlagPath -packageName $packageName
    try {
        $existsRaw = (adb -s $serial shell "if [ -f '$flagPath' ]; then echo 1; else echo 0; fi" 2>$null).Trim()
        return $existsRaw -eq '1'
    } catch {
        return $false
    }
}

function Select-SessionSnapshotFlagAction([bool]$isCurrentlyEnabled) {
    $currentLabel = if ($isCurrentlyEnabled) { 'ACTIVADO' } else { 'DESACTIVADO' }
    Write-Host "`nFlag SESSION_SNAPSHOT actual: $currentLabel" -ForegroundColor Cyan
    Write-Host "[1] Activar flag (más logs de SESSION_SNAPSHOT_JSON)"
    Write-Host "[2] Desactivar flag"
    Write-Host "[3] Dejar como está"

    while ($true) {
        $inputValue = Read-Host "Elige una opción para el flag"
        switch ($inputValue.Trim()) {
            '1' { return 'enable' }
            '2' { return 'disable' }
            '3' { return 'keep' }
            default {
                Write-Host "Selección inválida. Intenta de nuevo." -ForegroundColor Yellow
            }
        }
    }
}

function Set-SessionSnapshotFlag([string]$serial, [string]$packageName, [string]$action) {
    $flagPath = Get-SessionSnapshotFlagPath -packageName $packageName
    switch ($action) {
        'enable' {
            adb -s $serial shell "mkdir -p '/sdcard/Android/data/$packageName/files'; touch '$flagPath'" | Out-Null
            Write-Host "Flag SESSION_SNAPSHOT activado." -ForegroundColor Green
        }
        'disable' {
            adb -s $serial shell "rm -f '$flagPath'" | Out-Null
            Write-Host "Flag SESSION_SNAPSHOT desactivado." -ForegroundColor Green
        }
        default {
            Write-Host "Flag SESSION_SNAPSHOT sin cambios." -ForegroundColor DarkGray
        }
    }
}

function Get-AppPid([string]$serial, [string]$packageName) {
    try {
        $appPid = (adb -s $serial shell pidof -s $packageName 2>$null).Trim()
        if ([string]::IsNullOrWhiteSpace($appPid)) {
            return $null
        }
        return $appPid
    } catch {
        return $null
    }
}

function Wait-ForAppPid([string]$serial, [string]$packageName) {
    while ($true) {
        $appPid = Get-AppPid -serial $serial -packageName $packageName
        if ($appPid) {
            return $appPid
        }

        Write-Host "Abre SingSync en el dispositivo para comenzar a ver logs..." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
}

Test-AdbAvailable
$devices = Get-ConnectedDevices
$selected = Select-Device -devices $devices

$packageName = 'net.iozamudioa.singsync'
$flagIsEnabled = Get-SessionSnapshotFlagEnabled -serial $selected.Serial -packageName $packageName
$flagAction = Select-SessionSnapshotFlagAction -isCurrentlyEnabled $flagIsEnabled
Set-SessionSnapshotFlag -serial $selected.Serial -packageName $packageName -action $flagAction

$appPid = Wait-ForAppPid -serial $selected.Serial -packageName $packageName

Write-Host "`nDispositivo seleccionado: $($selected.Serial)" -ForegroundColor Green
Write-Host "Paquete filtrado: $packageName" -ForegroundColor Green
Write-Host "PID actual: $appPid" -ForegroundColor Green
Write-Host "Presiona Ctrl + C para salir." -ForegroundColor DarkGray

adb -s $selected.Serial logcat -c | Out-Null

adb -s $selected.Serial logcat --pid=$appPid -v time
exit $LASTEXITCODE
