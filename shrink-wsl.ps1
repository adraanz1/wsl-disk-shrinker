# Bypass del ExecutionPolicy de PS y UAC de Administrador
if ($wscript -eq $null) { $wscript = New-Object -ComObject WScript.Shell } 
if ((Get-ExecutionPolicy) -ne 'Bypass') { 
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit 
}

# Detección automática de idioma
$lang = (Get-Culture).TwoLetterISOLanguageName

# Diccionario de textos
$msg = @{
    en = @{
        Titulo       = "         WSL DYNAMIC DISK SHRINKER TOOL             "
        ErrorNoDiscos = "`nNo significant WSL or Docker virtual disks (.vhdx) were found to compact (all are under 0.5 GB)."
        PressExit    = "Press Enter to exit..."
        Estado       = "`nCurrent state of your distributions:"
        Detectadas   = "`nDetected distributions and their current size:"
        Seleccione   = "`nEnter the number of the distribution you want to compact (Press Enter with no input to continue/exit)"
        Saliendo     = "`nNo items selected. Exiting..."
        Carrito      = "`n[Currently selected: "
        YaExiste     = "This item is already in your selection list!"
        FueraRango   = "Number out of range. Try again."
        NoValido     = "Invalid input. Enter a number or press Enter to finish."
        Recomienda   = "`n  CRITICAL RECOMMENDATION:"
        ProcesarNum  = "You are about to process "
        Elementos    = " item(s)."
        CierraTodo   = "Please CLOSE Docker Desktop, VS Code, and any active WSL terminal to avoid corruption."
        Confirmar    = "`nDo you want to proceed with the automatic compaction of the selected items? (Y/N)"
        CerrandoWSL  = "`nShutting down all active WSL instances..."
        Cancelado    = "`nOperation cancelled by the user. Exiting..."
        OpNoValida   = "Invalid option. Enter 'Y' or 'N'."
        Iniciando    = "            STARTING COMPACTION PROCESS             "
        Procesando   = "`nProcessing: "
        Antes        = " -> Size BEFORE: "
        Despues      = " -> Size AFTER:  "
        Liberado     = " -> Space freed in this disk: "
        Completo     = "PROCESS COMPLETE"
        Enhorabuena  = "In total you have recovered: "
        GigaBytes    = " GB of hard drive space."
        Optimizado   = "The disks were already fully optimized. No space could be freed."
        PressClose   = "`nPress Enter to close this window..."
        DockerName   = "Docker - "
        Si           = "Y"
        No           = "N"
    }
    es = @{
        Titulo       = "         COMPACTADOR DINÁMICO DE DISCOS WSL        "
        ErrorNoDiscos = "`nNo se encontraron discos virtuales (.vhdx) significativos de WSL o Docker para compactar (todos pesan menos de 0.5 GB)."
        PressExit    = "Presiona Enter para salir..."
        Estado       = "`nEstado actual de tus distribuciones:"
        Detectadas   = "`nDistribuciones detectadas y su tamaño actual:"
        Seleccione   = "`nIntroduce el número de la distribución que deseas compactar (Pulse Enter sin introducir nada para continuar/salir)"
        Saliendo     = "`nNo seleccionaste ningún elemento. Saliendo..."
        Carrito      = "`n[Seleccionados actualmente: "
        YaExiste     = "¡Este elemento ya está en tu lista de selección!"
        FueraRango   = "Número fuera de rango. Inténtalo de nuevo."
        NoValido     = "Entrada no válida. Introduce un número o presiona Enter para terminar."
        Recomienda   = "`n  RECOMENDACIÓN CRÍTICA:"
        ProcesarNum  = "Se van a procesar "
        Elementos    = " elemento(s)."
        CierraTodo   = "Por favor, CIERRA Docker Desktop, VS Code y cualquier terminal WSL para evitar corrupción."
        Confirmar    = "`n¿Deseas proceder con la compactación automática de los seleccionados? (S/N)"
        CerrandoWSL  = "`nCerrando todas las instancias activas de WSL..."
        Cancelado    = "`nOperación cancelada por el usuario. Saliendo..."
        OpNoValida   = "Opción no válida. Introduce 'S' o 'N'."
        Iniciando    = "            INICIANDO PROCESO DE COMPACTACIÓN       "
        Procesando   = "`nProcesando: "
        Antes        = " -> Peso ANTES:   "
        Despues      = " -> Peso DESPUÉS: "
        Liberado     = " -> Espacio liberado en este disco: "
        Completo     = "PROCESO COMPLETADO"
        Enhorabuena  = "En total has recuperado: "
        GigaBytes    = " GB de espacio en tu disco duro."
        Optimizado   = "Los discos ya estaban optimizados. No se pudo encoger más."
        PressClose   = "`nPresiona Enter para cerrar esta ventana..."
        DockerName   = "Docker - "
        Si           = "S"
        No           = "N"
    }
}

# Cargar los textos correspondientes
$t = if ($lang -eq 'es') { $msg.es } else { $msg.en }

Write-Host "****************************************************" -ForegroundColor Cyan
Write-Host $t.Titulo -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor Cyan

# Lista dinámica
$listaDistros = New-Object System.Collections.Generic.List[PSCustomObject]

# Primera búsqueda en el Registro de Windows
$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
if (Test-Path $registryPath) {
    Get-ChildItem -Path $registryPath | ForEach-Object {
        try {
            $name = $_.GetValue("DistributionName", $null, "DoNotExpandEnvironmentNames")
            $basePath = $_.GetValue("BasePath", $null, "DoNotExpandEnvironmentNames")
            
            if ($name -and $basePath) {
                $basePathStr = $basePath.ToString().Trim()
                $posiblesDiscos = @("ext4.vhdx", "docker_data.vhdx")
                
                foreach ($disco in $posiblesDiscos) {
                    $rutaPrueba = Join-Path $basePathStr $disco -ErrorAction SilentlyContinue
                    if (Test-Path $rutaPrueba -ErrorAction SilentlyContinue) {
                        $sizeGb = [math]::Round((Get-Item $rutaPrueba).Length / 1GB, 2)
                        
                        # Filtro de peso mínimo: ignorar si pesa menos de 0.5 GB
                        if ($sizeGb -ge 0.5) {
                            $listaDistros.Add([PSCustomObject]@{
                                Nombre = $name
                                Ruta   = $rutaPrueba
                                PesoGB = $sizeGb
                            })
                        }
                        break
                    }
                }
            }
        } catch {}
    }
}

# Búsqueda forzada especial para Docker Desktop
$dockerWslPath = Join-Path $env:LOCALAPPDATA "Docker\wsl"
if (Test-Path $dockerWslPath) {
    Get-ChildItem -Path $dockerWslPath -Recurse -Filter "*.vhdx" -ErrorAction SilentlyContinue | ForEach-Object {
        $archivo = $_
        if ($listaDistros.Ruta -notcontains $archivo.FullName) {
            $sizeGb = [math]::Round($archivo.Length / 1GB, 2)
            
            # Filtro para que no seleccione el disco main de docker
            if ($sizeGb -ge 0.5) {
                $nombreFormateado = $t.DockerName + $archivo.Directory.Name + " (" + $archivo.Name + ")"
                $listaDistros.Add([PSCustomObject]@{
                    Nombre = $nombreFormateado
                    Ruta   = $archivo.FullName
                    PesoGB = $sizeGb
                })
            }
        }
    }
}

if ($listaDistros.Count -eq 0) {
    Write-Error $t.ErrorNoDiscos
    Read-Host $t.PressExit
    exit
}

# Mostrar el estado de los WSL según el sistema
Write-Host $t.Estado -ForegroundColor DarkCyan
wsl -l -v
Write-Host "----------------------------------------------------" -ForegroundColor DarkCyan

# Mostrar menú con los pesos en GB
Write-Host $t.Detectadas -ForegroundColor Yellow
$i = 1
foreach ($distro in $listaDistros) {
    Write-Host " [$i] $($distro.Nombre) -> $($distro.PesoGB) GB" -ForegroundColor Green
    $i++
}

# Preguntar al usuario en bucle el disco que desea compactar
$elementosACompactar = New-Object System.Collections.Generic.List[PSCustomObject]

while ($true) {
    if ($elementosACompactar.Count -gt 0) {
        $seleccionadosTexto = ($elementosACompactar | ForEach-Object { $_.Nombre }) -join ', '
        Write-Host "$($t.Carrito)$seleccionadosTexto]" -ForegroundColor Magenta
    }

    $inputUser = Read-Host $t.Seleccione
    
    if ([string]::IsNullOrEmpty($inputUser)) {
        if ($elementosACompactar.Count -eq 0) {
            Write-Host $t.Saliendo -ForegroundColor Red
            Start-Sleep -s 2
            exit
        }
        break 
    }

    if ($inputUser -match '^\d+$') {
        $indice = [int]$inputUser - 1
        if ($indice -ge 0 -and $indice -lt $listaDistros.Count) {
            $elegido = $listaDistros[$indice]
            
            if ($elementosACompactar.Ruta -contains $elegido.Ruta) {
                Write-Host $t.YaExiste -ForegroundColor DarkYellow
            } else {
                $elementosACompactar.Add($elegido)
                Write-Host "$($t.Anadido) $($elegido.Nombre)" -ForegroundColor Cyan
            }
        } else {
            Write-Host $t.FueraRango -ForegroundColor DarkYellow
        }
    } else {
        Write-Host $t.NoValido -ForegroundColor DarkYellow
    }
}

# Advertencia y confirmación general
Write-Host $t.Recomienda -ForegroundColor Yellow
Write-Host "$($t.ProcesarNum)$($elementosACompactar.Count)$($t.Elementos)"
Write-Host $t.CierraTodo

while ($true) {
    $confirmacion = Read-Host $t.Confirmar
    if ($confirmacion -eq $t.Si -or $confirmacion -eq $t.Si.ToLower()) {
        Write-Host $t.CerrandoWSL -ForegroundColor Yellow
        wsl --shutdown
        Start-Sleep -s 3 
        break
    } 
    elseif ($confirmacion -eq $t.No -or $confirmacion -eq $t.No.ToLower()) {
        Write-Host $t.Cancelado -ForegroundColor Red
        Start-Sleep -s 2
        exit
    } 
    else {
        Write-Host $t.OpNoValida -ForegroundColor DarkYellow
    }
}

# BUCLE DE EJECUCIÓN
Write-Host "`n****************************************************" -ForegroundColor Cyan
Write-Host $t.Iniciando -ForegroundColor Cyan
Write-Host "****************************************************" -ForegroundColor Cyan

$totalRecuperado = 0

foreach ($elemento in $elementosACompactar) {
    $vdisk = $elemento.Ruta
    $pesoInicial = $elemento.PesoGB
    
    Write-Host "$($t.Procesando)$($elemento.Nombre)..." -ForegroundColor Cyan
    
    $comandos = @"
select vdisk file="$vdisk"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@

    $comandos | diskpart

    $pesoFinal = [math]::Round((Get-Item $vdisk).Length / 1GB, 2)
    $diferencia = [math]::Round($pesoInicial - $pesoFinal, 2)
    $totalRecuperado += $diferencia

    Write-Host "$($t.Antes)$pesoInicial GB" -ForegroundColor Gray
    Write-Host "$($t.Despues)$pesoFinal GB" -ForegroundColor Green
    Write-Host "$($t.Liberado)$diferencia GB" -ForegroundColor Green
}

# Resumen final total
Write-Host "`n****************************************************" -ForegroundColor Cyan
Write-Host $t.Completo -ForegroundColor Yellow
if ($totalRecuperado -gt 0) {
    Write-Host "$($t.Enhorabuena)$totalRecuperado$($t.GigaBytes)" -ForegroundColor Green
} else {
    Write-Host $t.Optimizado -ForegroundColor White
}
Write-Host "****************************************************" -ForegroundColor Cyan

Read-Host $t.PressClose