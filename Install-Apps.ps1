#requires -Version 5.1
<#
.SYNOPSIS
    Instalador automatico de aplicaciones (inventario Linux -> equivalente Windows).

.DESCRIPTION
    Lee app-catalog.json, detecta las particiones/volumenes del equipo, calcula el
    espacio libre y determina que aplicaciones se pueden instalar. Despues instala
    cada aplicacion con winget, Chocolatey o Scoop (en ese orden por defecto),
    omitiendo las que ya estan instaladas.

.PARAMETER CatalogPath
    Ruta al catalogo JSON. Por defecto app-catalog.json junto a este script.

.PARAMETER Drive
    Unidad a comprobar, por ejemplo C: o D:. Si se omite se usa la del catalogo
    y, si no existe, la unidad fija con mas espacio libre.

.PARAMETER Manager
    auto (por defecto), winget, choco o scoop.

.PARAMETER Category
    Filtra por categoria. Se puede repetir: -Category Navegacion,Multimedia

.PARAMETER ExcludeId
    Excluye ids concretos del catalogo.

.PARAMETER ListOnly
    Solo muestra el catalogo; no instala nada.

.PARAMETER DryRun
    Muestra el plan (incluido el calculo de espacio) sin instalar.

.PARAMETER Force
    Intenta reinstalar las aplicaciones detectadas como instaladas.

.PARAMETER Yes
    Responde automaticamente a las preguntas (omite las aplicaciones mas grandes
    si no cabe todo).

.PARAMETER SkipSpaceCheck
    Instala aunque el espacio estimado supere el disponible (no recomendado).

.PARAMETER ReserveGB
    GB que se reservan para el sistema. Por defecto 10.

.PARAMETER ReportPath
    Ruta del informe JSON. Por defecto no se escribe informe.

.EXAMPLE
    .\Install-Apps.ps1 -DryRun
    Muestra que se instalaria y si cabe en la unidad C:.

.EXAMPLE
    .\Install-Apps.ps1 -Drive D: -Category Productividad -Yes -ReportPath .\informe.json
    Instala el grupo de productividad en D: sin preguntas y guarda el informe.

.NOTES
    No elimina aplicaciones. Solo instala o informa. Requiere Windows 10/11 y
    conexion a Internet. winget se incluye en Microsoft Store / App Installer.
#>
[CmdletBinding()]
param(
    [string]$CatalogPath = (Join-Path -Path $PSScriptRoot -ChildPath 'app-catalog.json'),
    [string]$Drive,
    [ValidateSet('auto', 'winget', 'choco', 'scoop')][string]$Manager = 'auto',
    [string[]]$Category,
    [string[]]$ExcludeId,
    [switch]$ListOnly,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Yes,
    [switch]$SkipSpaceCheck,
    [ValidateRange(0, 1024)][int]$ReserveGB = 10,
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')][string]$Level = 'INFO'
    )
    $color = switch ($Level) {
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'OK'    { 'Green' }
        default { 'Gray' }
    }
    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $color
    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value ("{0} [{1}] {2}" -f (Get-Date).ToString('s'), $Level, $Message) -Encoding UTF8
    }
}

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------------------
# Disco: volumenes, particiones y espacio
# ---------------------------------------------------------------------------
function Get-DiskInfo {
    $volumes = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' | ForEach-Object {
        $sizeGB = if ($_.Size) { [math]::Round(($_.Size / 1GB), 2) } else { 0 }
        $freeGB = if ($_.FreeSpace) { [math]::Round(($_.FreeSpace / 1GB), 2) } else { 0 }
        [pscustomobject]@{
            Drive     = $_.DeviceID
            Label     = $_.VolumeName
            FileSystem = $_.FileSystem
            SizeGB    = $sizeGB
            FreeGB    = $freeGB
            UsedGB    = [math]::Round(($sizeGB - $freeGB), 2)
            Partitions = $null
        }
    }

    foreach ($v in $volumes) {
        $letter = $v.Drive.TrimEnd(':')
        try {
            $parts = @(Get-Partition -DriveLetter $letter -ErrorAction Stop)
            if ($parts.Count -gt 0) { $v.Partitions = $parts.Count }
        } catch {
            # Get-Partition no esta disponible en ediciones antiguas: no es fatal.
        }
    }
    return @($volumes)
}

function Show-DiskTable {
    param([Parameter(Mandatory = $true)][object[]]$Disks)
    Write-Host ''
    Write-Host ('{0,-7} {1,-18} {2,-10} {3,10} {4,10} {5,10} {6,10}' -f 'Unidad', 'Etiqueta', 'Sist.arch', 'Tamano GB', 'Libres GB', 'Usados GB', 'Partic.')
    Write-Host ('-' * 82)
    foreach ($d in $Disks) {
        Write-Host ('{0,-7} {1,-18} {2,-10} {3,10} {4,10} {5,10} {6,10}' -f $d.Drive, $d.Label, $d.FileSystem, $d.SizeGB, $d.FreeGB, $d.UsedGB, $(if ($null -eq $d.Partitions) { '-' } else { $d.Partitions }))
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Deteccion de lo ya instalado
# ---------------------------------------------------------------------------
function Get-WingetInstalledIds {
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-CommandExists 'winget')) { return ,$ids }
    $tempRoot = if ($env:TEMP) { $env:TEMP } else { [IO.Path]::GetTempPath() }
    $tmp = Join-Path -Path $tempRoot -ChildPath ("winget_export_{0}.json" -f $PID)
    try {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        $null = & winget export --output $tmp --accept-source-agreements 2>&1
        if (Test-Path -LiteralPath $tmp) {
            $export = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($source in @($export.Sources)) {
                foreach ($pkg in @($source.Packages)) {
                    if ($pkg.PackageIdentifier) { $null = $ids.Add([string]$pkg.PackageIdentifier) }
                }
            }
        }
    } catch {
        Write-Log ("No se pudo consultar el inventario de winget: {0}" -f $_.Exception.Message) 'WARN'
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    return ,$ids
}

function Get-InstalledDisplayNames {
    $names = @()
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $keys) {
        try {
            $items = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($item.DisplayName) { $names += [string]$item.DisplayName }
            }
        } catch { }
    }
    return $names
}

function Test-AppInstalled {
    param(
        [Parameter(Mandatory = $true)][object]$App,
        [Parameter(Mandatory = $true)][object]$WingetIds,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$DisplayNames
    )
    if ($App.winget -and $WingetIds.Contains([string]$App.winget)) { return $true }
    if ($App.windowsName) {
        $wanted = [string]$App.windowsName
        foreach ($name in $DisplayNames) {
            if ($name.IndexOf($wanted, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        }
    }
    # Herramientas que suelen estar presentes aunque no figuren en winget export.
    $exeHints = @{
        git = 'git.exe'; gh = 'gh.exe'; glab = 'glab.exe'; curl = 'curl.exe';
        jq = 'jq.exe'; powershell = 'pwsh.exe'; python = 'python.exe';
        ffmpeg = 'ffmpeg.exe'; '7zip' = '7z.exe'; vlc = 'vlc.exe'
    }
    if ($exeHints.ContainsKey([string]$App.id)) {
        $exe = $exeHints[[string]$App.id]
        if (Test-CommandExists $exe) { return $true }
        $alt = Get-Command ([string]$App.id) -ErrorAction SilentlyContinue
        if ($alt) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Instalacion
# ---------------------------------------------------------------------------
function Invoke-AppInstall {
    param(
        [Parameter(Mandatory = $true)][object]$App,
        [Parameter(Mandatory = $true)][string]$ManagerName,
        [Parameter(Mandatory = $true)][string]$LogDir
    )
    $out = Join-Path -Path $LogDir -ChildPath ("{0}-{1}.out.log" -f $App.id, $ManagerName)
    $err = Join-Path -Path $LogDir -ChildPath ("{0}-{1}.err.log" -f $App.id, $ManagerName)

    switch ($ManagerName) {
        'winget' {
            $exe = (Get-Command -Name winget -ErrorAction Stop).Source
             = @('install', '--id', [string]$App.winget, '--exact', '--source', 'winget',
                      '--accept-source-agreements', '--accept-package-agreements',
                      '--disable-interactivity', '--silent')
        }
        'choco' {
            $exe = (Get-Command -Name choco -ErrorAction Stop).Source
             = @('install', [string]$App.choco, '-y', '--no-progress', '--limit-output')
        }
        'scoop' {
            $scoopCmd = Get-Command -Name scoop.cmd -ErrorAction SilentlyContinue
            if ($scoopCmd) {
                $exe = $scoopCmd.Source
                 = @('install', [string]$App.scoop)
            } else {
                $exe = 'cmd.exe'
                 = @('/c', 'scoop', 'install', [string]$App.scoop)
            }
        }
        default { throw ("Gestor desconocido: {0}" -f $ManagerName) }
    }

    try {
        Write-Log ("  -> {0}" -f ($procArgs -join ' ')) 'INFO'
        $proc = Start-Process -FilePath $exe -ArgumentList $procArgs -Wait -PassThru -NoNewWindow `
                              -RedirectStandardOutput $out -RedirectStandardError $err
        if ($proc.ExitCode -ne 0) {
            Write-Log ("    stderr: {0}" -f ((Get-Content -LiteralPath $err -Tail 3 -ErrorAction SilentlyContinue) -join ' | ')) 'WARN'
        }
        return $proc.ExitCode
    } catch {
        Write-Log ("Fallo al ejecutar {0}: {1}" -f $ManagerName, $_.Exception.Message) 'ERROR'
        return 1
    }
}

# ---------------------------------------------------------------------------
# Inicio
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $CatalogPath)) {
    throw ("No se encuentra el catalogo: {0}" -f $CatalogPath)
}
$catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($catalog.schemaVersion -ne 1) { throw "Version de catalogo no soportada." }

$script:LogFile = $null
if ($ReportPath) {
    $script:LogFile = [IO.Path]::ChangeExtension($ReportPath, '.log')
    $dir = Split-Path -Parent $script:LogFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    "LOG iniciado {0}" -f (Get-Date).ToString('o') | Set-Content -LiteralPath $script:LogFile -Encoding UTF8
}

Write-Log ("Catalogo v{0} - {1} aplicaciones" -f $catalog.version, @($catalog.apps).Count)
Write-Log ("Sistema origen: {0}" -f $catalog.sourceSystem.os)

Write-Host ''
Write-Host '=== Particiones y unidades detectadas ===' -ForegroundColor Cyan
$disks = @(Get-DiskInfo)
if ($disks.Count -eq 0) { throw "No se han detectado unidades fijas." }
Show-DiskTable -Disks $disks

if (-not $Drive) { $Drive = [string]$catalog.defaults.drive }
$target = @($disks | Where-Object { $_.Drive -eq $Drive })
if ($target.Count -eq 0) {
    Write-Log ("La unidad {0} no existe; se usa la que tiene mas espacio libre." -f $Drive) 'WARN'
    $target = @($disks | Sort-Object -Property FreeGB -Descending | Select-Object -First 1)
}
$target = $target[0]
Write-Log ("Unidad seleccionada: {0} ({1} GB totales, {2} GB libres)" -f $target.Drive, $target.SizeGB, $target.FreeGB)

$available = @{}
foreach ($m in @('winget', 'choco', 'scoop')) { $available[$m] = Test-CommandExists $m }
Write-Log ("Gestores: winget={0} choco={1} scoop={2}" -f $available['winget'], $available['choco'], $available['scoop'])
if ($Manager -ne 'auto' -and -not $available[$Manager]) {
    throw ("El gestor {0} no esta instalado." -f $Manager)
}
if (-not ($available['winget'] -or $available['choco'] -or $available['scoop'])) {
    throw "No hay ningun gestor de paquetes. Instala winget, Chocolatey o Scoop."
}

$apps = @($catalog.apps)
if ($Category) { $apps = @($apps | Where-Object { $Category -contains [string]$_.category }) }
if ($ExcludeId) { $apps = @($apps | Where-Object { $ExcludeId -notcontains [string]$_.id }) }
Write-Log ("Aplicaciones seleccionadas: {0}" -f $apps.Count)

if ($ListOnly) {
    Write-Host ''
    Write-Host ('{0,-22} {1,-36} {2,-14} {3,8} {4}' -f 'ID', 'Nombre Windows', 'Categoria', 'MB', 'Accion')
    Write-Host ('-' * 110)
    foreach ($a in $apps) {
        Write-Host ('{0,-22} {1,-36} {2,-14} {3,8} {4}' -f $a.id, $a.windowsName, $a.category, $a.sizeMB, $a.action)
    }
    return
}

$wingetIds = Get-WingetInstalledIds
$displayNames = @(Get-InstalledDisplayNames)

$managerOrder = @($catalog.defaults.managerOrder)
if ($Manager -ne 'auto') { $managerOrder = @($Manager) }

$plan = @()
foreach ($app in $apps) {
    $item = [ordered]@{
        id           = [string]$app.id
        name         = [string]$app.windowsName
        origin       = [string]$app.origin
        category     = [string]$app.category
        sizeMB       = [int]$app.sizeMB
        action       = [string]$app.action
        status       = 'pending'
        managers     = @()
        manager      = $null
        winget       = [string]$app.winget
        choco        = [string]$app.choco
        scoop        = [string]$app.scoop
        notes        = [string]$app.notes
    }

    if ($app.action -ne 'install') {
        $item.status = [string]$app.action
        $plan += [pscustomobject]$item
        continue
    }
    if ((Test-AppInstalled -App $app -WingetIds $wingetIds -DisplayNames $displayNames) -and -not $Force) {
        $item.status = 'already-installed'
        $plan += [pscustomobject]$item
        continue
    }

    $candidates = @()
    foreach ($m in $managerOrder) {
        if (-not $available[$m]) { continue }
        $packageId = [string]$app.$m
        if ($packageId) { $candidates += $m }
    }
    if ($candidates.Count -eq 0) {
        $item.status = 'no-manager'
        $item.notes = ($item.notes + ' Sin gestor disponible para esta aplicacion.').Trim()
    } else {
        $item.managers = $candidates
        $item.manager = $candidates[0]
    }
    $plan += [pscustomobject]$item
}

$pending = @($plan | Where-Object { $_.status -eq 'pending' })
$requiredMB = 0
foreach ($p in $pending) { $requiredMB += $p.sizeMB }
$requiredGB = [math]::Round(($requiredMB / 1024), 2)
$usableGB = [math]::Round(($target.FreeGB - $ReserveGB), 2)
Write-Log ("Espacio estimado a instalar: {0} GB | Reserva: {1} GB | Utilizable: {2} GB" -f $requiredGB, $ReserveGB, $usableGB)

if ($requiredGB -gt $usableGB -and -not $SkipSpaceCheck) {
    Write-Log ("No caben todas las aplicaciones en {0} ({1} GB necesarios, {2} GB utiles)." -f $target.Drive, $requiredGB, $usableGB) 'WARN'
    $choice = '1'
    if (-not $Yes) {
        Write-Host '  1) Omitir automaticamente las aplicaciones mas grandes'
        Write-Host '  2) Continuar de todos modos'
        Write-Host '  3) Abortar'
        $choice = Read-Host '  Elija una opcion [1]'
        if (-not $choice) { $choice = '1' }
    } else {
        Write-Log "Modo -Yes: se omitiran las aplicaciones mas grandes." 'WARN'
    }
    switch ($choice) {
        '2' { Write-Log "Se ignora la comprobacion de espacio." 'WARN' }
        '3' { throw "Operacion cancelada por falta de espacio." }
        default {
            $currentGB = $requiredGB
            foreach ($p in @($pending | Sort-Object -Property sizeMB -Descending)) {
                if ($currentGB -le $usableGB) { break }
                $p.status = 'skipped-space'
                $p.notes = ("Omitida por espacio ({0} MB). {1}" -f $p.sizeMB, $p.notes).Trim()
                $currentGB = [math]::Round(($currentGB - ($p.sizeMB / 1024)), 2)
                Write-Log ("Omitida por espacio: {0} ({1} MB)" -f $p.id, $p.sizeMB) 'WARN'
            }
            $requiredGB = $currentGB
        }
    }
}

Write-Host ''
Write-Host '=== Plan ===' -ForegroundColor Cyan
Write-Host ('{0,-22} {1,-20} {2,9} {3}' -f 'ID', 'Estado', 'MB', 'Gestor')
Write-Host ('-' * 80)
foreach ($p in $plan) {
    Write-Host ('{0,-22} {1,-20} {2,9} {3}' -f $p.id, $p.status, $p.sizeMB, $(if ($p.manager) { $p.manager } else { '-' }))
}

if ($DryRun) {
    Write-Log "Simulacion terminada; no se ha instalado nada." 'OK'
    return
}

Write-Host ''
Write-Host '=== Instalacion ===' -ForegroundColor Cyan
$tempRoot = if ($env:TEMP) { $env:TEMP } else { [IO.Path]::GetTempPath() }
$logDir = Join-Path -Path $tempRoot -ChildPath ("autoinstall-logs-{0}" -f $PID)
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

foreach ($p in @($plan | Where-Object { $_.status -eq 'pending' })) {
    Write-Log ("Instalando {0} ({1})" -f $p.id, $p.name)
    $exitCode = 1
    foreach ($m in $p.managers) {
        $exitCode = Invoke-AppInstall -App $p -ManagerName $m -LogDir $logDir
        if ($exitCode -eq 0) {
            $p.manager = $m
            $p.status = 'installed'
            Write-Log ("{0} instalado con {1}" -f $p.id, $m) 'OK'
            break
        }
        Write-Log ("{0} fallo con {1} (codigo {2}); se prueba el siguiente gestor." -f $p.id, $m, $exitCode) 'WARN'
    }
    if ($exitCode -ne 0) {
        $p.status = 'failed'
        $p.notes = ("Codigo de salida {0}. {1}" -f $exitCode, $p.notes).Trim()
        Write-Log ("No se pudo instalar {0}" -f $p.id) 'ERROR'
    }
}

$counts = @{}
foreach ($p in $plan) {
    if (-not $counts.ContainsKey($p.status)) { $counts[$p.status] = 0 }
    $counts[$p.status]++
}

Write-Host ''
Write-Host '=== Resumen ===' -ForegroundColor Cyan
foreach ($k in ($counts.Keys | Sort-Object)) { Write-Host ("  {0,-20} {1}" -f $k, $counts[$k]) }

if ($ReportPath) {
    $resultados = @($plan | ForEach-Object {
        [ordered]@{
            id = $_.id; name = $_.name; origin = $_.origin; category = $_.category
            sizeMB = $_.sizeMB; action = $_.action; status = $_.status
            manager = $_.manager; notes = $_.notes
        }
    })
    $report = [ordered]@{
        generatedAt    = (Get-Date).ToString('o')
        catalogVersion = [string]$catalog.version
        sourceSystem   = [string]$catalog.sourceSystem.os
        drive          = $target.Drive
        disk           = $target
        reserveGB      = $ReserveGB
        requiredGB     = $requiredGB
        usableGB       = $usableGB
        managers       = $available
        summary        = $counts
        results        = $resultados
        logDir         = $logDir
    }
    $jsonPath = [IO.Path]::ChangeExtension($ReportPath, '.json')
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    Write-Log ("Informe: {0}" -f $jsonPath) 'OK'
    Write-Log ("Logs: {0}" -f $logDir)
}

$failed = 0
if ($counts.ContainsKey('failed')) { $failed = [int]$counts['failed'] }
Write-Log ("Finalizado. Fallos: {0}" -f $failed)
if ($failed -gt 0) { exit 2 }
