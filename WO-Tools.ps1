# Importar ensamblados necesarios
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Funcion principal
function Main {
    # Crear formulario principal
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Script PowerShell para Mantenimiento de Sistemas Windows 10/11"
    $form.Size = New-Object System.Drawing.Size(1000, 780)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $form.Font = New-Object System.Drawing.Font("Arial", 10)

    # TabControl con estilo moderno
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Size = New-Object System.Drawing.Size(960, 690)
    $tabControl.Location = New-Object System.Drawing.Point(20, 20)
    $tabControl.Padding = New-Object System.Drawing.Point(12, 4)

    # Crear pestañas
    $tab1 = New-Object System.Windows.Forms.TabPage
    $tab1.Text = "Resumen del Sistema"
    
    $tab2 = New-Object System.Windows.Forms.TabPage
    $tab2.Text = "Remover Bloatware y Telemetria"
    
    $tab3 = New-Object System.Windows.Forms.TabPage
    $tab3.Text = "Herramientas de Mantenimiento"
    
    $tab4 = New-Object System.Windows.Forms.TabPage
    $tab4.Text = "Registro de Eventos"

    # Funcion para obtener informacion del sistema en formato HTML
    function Get-OfficeInfo {
        $officeInfo = "`n"
        
        # Buscar Office
#         $officeRegPaths= @(
#            "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration",
#            "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration\64",
#            "HKLM:\SOFTWARE\Microsoft\Office\16.0\Common\InstallRoot",
#            "HKLM:\SOFTWARE\Microsoft\Office\15.0\Common\InstallRoot",
#            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration",
#            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
#        )
    
        $officeFound = $false
        
        # Buscar en Office Click-to-Run
        try {
            $c2rVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
            if ($c2rVersion.VersionToReport) {
                $officeInfo += "- Microsoft 365 (Version: $($c2rVersion.VersionToReport))`n"
                $officeFound = $true
            }
        } catch {}
    
        # Buscar versiones instaladas por MSI
        $officeKeys = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
            Where-Object { $_.GetValue("DisplayName") -like "*Microsoft Office*" -or $_.GetValue("DisplayName") -like "*Microsoft 365*" }
    
        foreach ($key in $officeKeys) {
            $name = $key.GetValue("DisplayName")
            $version = $key.GetValue("DisplayVersion")
            if ($name -and $version) {
                $officeInfo += "- $name (Version: $version)`n"
                $officeFound = $true
            }
        }
    
        # Detectar Office 32-bit en sistemas 64-bit
        $officeKeys32 = Get-ChildItem "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
            Where-Object { $_.GetValue("DisplayName") -like "*Microsoft Office*" -or $_.GetValue("DisplayName") -like "*Microsoft 365*" }
    
        foreach ($key in $officeKeys32) {
            $name = $key.GetValue("DisplayName")
            $version = $key.GetValue("DisplayVersion")
            if ($name -and $version) {
                $officeInfo += "- $name (32-bit) (Version: $version)`n"
                $officeFound = $true
            }
        }
    
        # Verificar la ruta de instalación
        $officePaths = @(
            "${env:ProgramFiles}\Microsoft Office",
            "${env:ProgramFiles(x86)}\Microsoft Office"
        )
    
        foreach ($path in $officePaths) {
            if (Test-Path $path) {
                $officeExes = Get-ChildItem -Path $path -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -in @("WINWORD.EXE", "EXCEL.EXE", "POWERPNT.EXE") }
                
                foreach ($exe in $officeExes) {
                    $fileVersion = $exe.VersionInfo.FileVersion
                    if ($fileVersion -and -not $officeFound) {
                        $officeInfo += "- Microsoft Office (Ruta: $($exe.Directory.Parent.Name)) (Version: $fileVersion)`n"
                        $officeFound = $true
                        break
                    }
                }
            }
        }
    
        if (-not $officeFound) {
            $officeInfo += "- No se encontró Microsoft Office instalado`n"
        }
    
        return $officeInfo
    }

    function Get-SystemInfoHTML {
        # Información del sistema
        $computerInfo = Get-ComputerInfo -Property @(
            "WindowsVersion",
            "OsName",
            "OsVersion",
            "CsProcessors",
            "CsTotalPhysicalMemory"
        )
        
        # Obtención de IP
        $ipAddress = (Get-NetIPAddress | Where-Object {
            $_.AddressFamily -eq "IPv4" -and 
            $_.PrefixOrigin -eq "Dhcp"
        } | Select-Object -First 1).IPAddress

        # Antivirus
        try {
            $antivirusProducts = Get-WmiObject -Namespace "root\SecurityCenter2" -Class AntiVirusProduct -ErrorAction Stop
            $antivirusInfo = ($antivirusProducts | ForEach-Object {
                $state = switch ($_.productState % 16) {
                    0 {"Desactivado"}
                    1 {"Expirado"}
                    8 {"Activo"}
                    10 {"Actualizado"}
                    default {"Estado desconocido"}
                }
                "$($_.displayName) - $state"
            }) -join "<br>"
        } catch {
            $antivirusInfo = "No se pudo obtener información del antivirus"
            $txtLog.AppendText("Error al obtener información del antivirus: $($_.Exception.Message)`r`n")
        }

        # Firewall
        try {
            $firewall = Get-NetFirewallProfile -ErrorAction Stop
            $estados = @{
                "Domain" = "Inactivo"
                "Private" = "Inactivo"
                "Public" = "Inactivo"
            }
            
            foreach ($profile in $firewall) {
                if ($profile.Enabled) {
                    $estados[$profile.Name] = "Activo"
                }
            }
            
            $firewallStatus = @"
Windows Defender Firewall<br>
Dominio: $($estados.Domain)<br>
Privado: $($estados.Private)<br>
Publico: $($estados.Public)
"@
        } catch {
            $firewallStatus = "No se pudo obtener información del firewall"
            $txtLog.AppendText("Error al obtener información del firewall: $($_.Exception.Message)`r`n")
        }

        # Información de discos
        $disks = Get-WmiObject Win32_LogicalDisk -Filter "DriveType = 3" |
            Select-Object DeviceID, @{
                Name="FreeSpace";
                Expression={[math]::Round($_.FreeSpace/1GB, 2)}
            }, @{
                Name="TotalSize";
                Expression={[math]::Round($_.Size/1GB, 2)}
            }
        
        # Información de Office
        $officeInfo = Get-OfficeInfo

        $systemInfo = @"
<html>
<head>
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="0">
</head>
<style>
    body { 
        font-family: Arial; 
        font-size: 10pt; 
        margin: 20px;
        background-color: #f0f0f0;
    }
    .header { 
        background: #007ACC; 
        color: white; 
        padding: 15px;
        text-align: center; 
        font-weight: bold;
        border-radius: 5px;
        margin-bottom: 20px;
    }
    .section { 
        background: #007ACC;
        color: white;
        padding: 8px 15px;
        margin-top: 15px;
        font-weight: bold;
        border-radius: 3px;
    }
    .data { 
        background: white;
        padding: 15px;
        margin: 10px 0;
        border-radius: 3px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    .item { 
        display: grid;
        grid-template-columns: 180px auto;
        padding: 5px 0;
    }
    .label { 
        color: #007ACC;
        font-weight: bold;
    }
    .value { 
        color: #333333;
    }
    .disk-info {
        background: white;
        padding: 15px;
        margin: 10px 0;
        border-left: 4px solid #007ACC;
        border-radius: 3px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    .log-section {
        margin-top: 10px;
        white-space: pre-wrap;
        font-family: Consolas, monospace;
    }
    .timestamp {
        color: #666;
        font-size: 0.9em;
        margin-top: 20px;
        text-align: right;
    }
    .error-message {
        color: #cc0000;
        font-style: italic;
    }
</style>
<body>
<div class="header">RESUMEN DEL SISTEMA</div>

<div class="section">EQUIPO</div>
<div class="data">
    <div class="item">
        <span class="label">Nombre:</span>
        <span class="value">$env:COMPUTERNAME</span>
    </div>
    <div class="item">
        <span class="label">Dominio:</span>
        <span class="value">$env:USERDOMAIN</span>
    </div>
    <div class="item">
        <span class="label">Direccion IP:</span>
        <span class="value">$ipAddress</span>
    </div>
</div>

<div class="section">SISTEMA OPERATIVO</div>
<div class="data">
    <div class="item">
        <span class="label">Version Windows:</span>
        <span class="value">$($computerInfo.OSName) $($computerInfo.OsVersion))</span>
    </div>
</div>

<div class="section">SEGURIDAD</div>
<div class="data">
    <div class="item">
        <span class="label">Antivirus:</span>
        <span class="value">$antivirusInfo</span>
    </div>
    <div class="item">
        <span class="label">Firewall:</span>
        <span class="value">$firewallStatus</span>
    </div>
</div>

<div class="section">MICROSOFT OFFICE</div>
<div class="data">
    <div class="item">
        <span class="label">Paquetes Instalados:</span>
        <span class="value">$($officeInfo)</span>
    </div>
</div>

<div class="section">HARDWARE</div>
<div class="data">
    <div class="item">
        <span class="label">Procesador:</span>
        <span class="value">$($computerInfo.CsProcessors.Name)</span>
    </div>
    <div class="item">
        <span class="label">Memoria RAM:</span>
        <span class="value">$([math]::Round($computerInfo.CsTotalPhysicalMemory/1GB, 2)) GB utilizable</span>
    </div>
</div>

<div class="section">ALMACENAMIENTO</div>
"@ 
        foreach ($disk in $disks) {
            $freeSpace = $disk.FreeSpace
            $totalSpace = $disk.TotalSize
            $usedSpace = $totalSpace - $freeSpace
            $percentFree = [math]::Round(($freeSpace / $totalSpace) * 100, 1)
            
            $systemInfo += @"
<div class="disk-info">
    <div class="item">
        <span class="label">Unidad:</span>
        <span class="value">$($disk.DeviceID)</span>
    </div>
    <div class="item">
        <span class="label">Espacio total:</span>
        <span class="value">$totalSpace GB</span>
    </div>
    <div class="item">
        <span class="label">Espacio usado:</span>
        <span class="value">$usedSpace GB</span>
    </div>
    <div class="item">
        <span class="label">Espacio libre:</span>
        <span class="value">$freeSpace GB ($percentFree%)</span>
    </div>
</div>
"@
        }
        
        $systemInfo += @"
</body>
</html>
"@
        
        return $systemInfo
    }

    # Optimizar el WebBrowser
    $txtSystemInfo = New-Object System.Windows.Forms.WebBrowser
    $txtSystemInfo.ScriptErrorsSuppressed = $true
    $txtSystemInfo.Location = New-Object System.Drawing.Point(10, 10)
    $txtSystemInfo.Size = New-Object System.Drawing.Size(920, 620)
    $txtSystemInfo.DocumentText = Get-SystemInfoHTML
    $txtSystemInfo.IsWebBrowserContextMenuEnabled = $false
    $txtSystemInfo.AllowNavigation = $false
#    $txtSystemInfo.ScrollBarsEnabled = $true
#    $txtSystemInfo.Add_DocumentCompleted({
#        try {
#            $this.Document.Body.Style.SetAttribute("overflow", "auto")
#        } catch {
#            $txtLog.AppendText("Nota: No se pudo ajustar el scroll del resumen.`r`n")
#        }
#    })
    $tab1.Controls.Add($txtSystemInfo)

    # Remover Bloatware
    $panelBloatware = New-Object System.Windows.Forms.Panel
    $panelBloatware.Location = New-Object System.Drawing.Point(20, 60)
    $panelBloatware.Size = New-Object System.Drawing.Size(900, 400)
    $panelBloatware.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $lblBloatware = New-Object System.Windows.Forms.Label
    $lblBloatware.Text = "Seleccione las aplicaciones para desinstalar:"
    $lblBloatware.Location = New-Object System.Drawing.Point(10, 10)
    $lblBloatware.Size = New-Object System.Drawing.Size(300, 30)

    $listBloatware = New-Object System.Windows.Forms.CheckedListBox
    $listBloatware.Location = New-Object System.Drawing.Point(10, 40)
    $listBloatware.Size = New-Object System.Drawing.Size(870, 300)

    # Lista de apps Bloatware comunes
    $bloatwareApps = @(
        "Microsoft.3DBuilder",
        "Microsoft.BingWeather",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.MixedReality.Portal",
        "Microsoft.People",
        "Microsoft.SkypeApp",
        "Microsoft.WindowsAlarms",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.WindowsMaps",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxApp",
        "Microsoft.XboxGameOverlay",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxIdentityProvider",
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.YourPhone",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo"
    )

    foreach ($app in $bloatwareApps) {
        $listBloatware.Items.Add($app)
    }

    $btnRemoveBloatware = New-Object System.Windows.Forms.Button
    $btnRemoveBloatware.Text = "Desinstalar Seleccionados"
    $btnRemoveBloatware.Location = New-Object System.Drawing.Point(10, 350)
    $btnRemoveBloatware.Size = New-Object System.Drawing.Size(200, 35)
    $btnRemoveBloatware.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnRemoveBloatware.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnRemoveBloatware.ForeColor = [System.Drawing.Color]::White
    $btnRemoveBloatware.Add_Click({
        foreach ($item in $listBloatware.CheckedItems) {
            try {
                Get-AppxPackage $item | Remove-AppxPackage -ErrorAction SilentlyContinue
                $txtLog.AppendText("Desinstalando: $item`r`n")
            }
            catch {
                $txtLog.AppendText("Error al desinstalar: $item`r`n")
            }
        }
        [System.Windows.Forms.MessageBox]::Show("Proceso completado", "Informacion", [System.Windows.Forms.MessageBoxButtons]::OK)
    })

    $panelBloatware.Controls.AddRange(@($lblBloatware, $listBloatware, $btnRemoveBloatware))

    # Panel de Opciones Adicionales
    $panelOptions = New-Object System.Windows.Forms.Panel
    $panelOptions.Location = New-Object System.Drawing.Point(20, 420)
    $panelOptions.Size = New-Object System.Drawing.Size(900, 150)
    $panelOptions.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $lblOptions = New-Object System.Windows.Forms.Label
    $lblOptions.Text = "Opciones de Privacidad y Rendimiento:"
    $lblOptions.Location = New-Object System.Drawing.Point(10, 10)
    $lblOptions.Size = New-Object System.Drawing.Size(300, 20)

    $chkCortana = New-Object System.Windows.Forms.CheckBox
    $chkCortana.Text = "Deshabilitar Cortana"
    $chkCortana.Location = New-Object System.Drawing.Point(10, 40)
    $chkCortana.Size = New-Object System.Drawing.Size(200, 30)

    $chkTelemetry = New-Object System.Windows.Forms.CheckBox
    $chkTelemetry.Text = "Deshabilitar Telemetria"
    $chkTelemetry.Location = New-Object System.Drawing.Point(10, 70)
    $chkTelemetry.Size = New-Object System.Drawing.Size(200, 30)

    $btnApplyPrivacy = New-Object System.Windows.Forms.Button
    $btnApplyPrivacy.Text = "Aplicar Cambios"
    $btnApplyPrivacy.Location = New-Object System.Drawing.Point(10, 110)
    $btnApplyPrivacy.Size = New-Object System.Drawing.Size(150, 30)
    $btnApplyPrivacy.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnApplyPrivacy.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnApplyPrivacy.ForeColor = [System.Drawing.Color]::White
    $btnApplyPrivacy.Add_Click({
        if ($chkCortana.Checked) {
            try {
                # Deshabilitar Cortana
                New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Force | Out-Null
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Type DWord -Value 0
                $txtLog.AppendText("Cortana ha sido deshabilitada.`r`n")
            }
            catch {
                $txtLog.AppendText("Error al deshabilitar Cortana: $($_.Exception.Message)`r`n")
            }
        }

        if ($chkTelemetry.Checked) {
            try {
                # Deshabilitar Telemetria
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 0
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 0
                $txtLog.AppendText("Telemetria ha sido deshabilitada.`r`n")
            }
            catch {
                $txtLog.AppendText("Error al deshabilitar Telemetria: $($_.Exception.Message)`r`n")
            }
        }

        [System.Windows.Forms.MessageBox]::Show(
            "Los cambios se han aplicado. Algunos cambios pueden requerir reiniciar el sistema.",
            "Cambios Aplicados",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    })

    $panelOptions.Controls.AddRange(@($lblOptions, $chkCortana, $chkTelemetry, $btnApplyPrivacy))

    $tab2.Controls.AddRange(@($panelBloatware, $panelOptions))

    # Mantenimiento
    $panelRename = New-Object System.Windows.Forms.Panel
    $panelRename.Location = New-Object System.Drawing.Point(20, 20)
    $panelRename.Size = New-Object System.Drawing.Size(900, 80)
    $panelRename.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $lblNewName = New-Object System.Windows.Forms.Label
    $lblNewName.Text = "Nuevo nombre del equipo:"
    $lblNewName.Location = New-Object System.Drawing.Point(10, 20)
    $lblNewName.Size = New-Object System.Drawing.Size(200, 30)

    $txtNewName = New-Object System.Windows.Forms.TextBox
    $txtNewName.Location = New-Object System.Drawing.Point(220, 20)
    $txtNewName.Size = New-Object System.Drawing.Size(250, 30)

    $btnRename = New-Object System.Windows.Forms.Button
    $btnRename.Text = "Cambiar nombre"
    $btnRename.Location = New-Object System.Drawing.Point(480, 18)
    $btnRename.Size = New-Object System.Drawing.Size(150, 35)
    $btnRename.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnRename.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnRename.ForeColor = [System.Drawing.Color]::White

    $panelRename.Controls.AddRange(@($lblNewName, $txtNewName, $btnRename))

    $btnDefrag = New-Object System.Windows.Forms.Button
    $btnDefrag.Text = "Desfragmentar discos"
    $btnDefrag.Location = New-Object System.Drawing.Point(20, 120)
    $btnDefrag.Size = New-Object System.Drawing.Size(250, 40)
    $btnDefrag.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnDefrag.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnDefrag.ForeColor = [System.Drawing.Color]::White
    $btnDefrag.Add_Click({
        Start-Process "dfrgui.exe"
    })

    $btnCleanup = New-Object System.Windows.Forms.Button
    $btnCleanup.Text = "Limpieza de disco"
    $btnCleanup.Location = New-Object System.Drawing.Point(280, 120)
    $btnCleanup.Size = New-Object System.Drawing.Size(250, 40)
    $btnCleanup.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCleanup.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnCleanup.ForeColor = [System.Drawing.Color]::White
    $btnCleanup.Add_Click({
        Start-Process "cleanmgr.exe"
    })

    $tab3.Controls.AddRange(@($panelRename, $btnDefrag, $btnCleanup))

    # Registro
    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Multiline = $true
    $txtLog.ReadOnly = $true
    $txtLog.Location = New-Object System.Drawing.Point(10, 10)
    $txtLog.Size = New-Object System.Drawing.Size(750, 450)

    $btnSaveLog = New-Object System.Windows.Forms.Button
    $btnSaveLog.Text = "Guardar registro"
    $btnSaveLog.Location = New-Object System.Drawing.Point(10, 470)
    $btnSaveLog.Size = New-Object System.Drawing.Size(200, 40)
    $btnSaveLog.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSaveLog.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnSaveLog.ForeColor = [System.Drawing.Color]::White
    $btnSaveLog.Add_Click({
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $defaultFileName = "$env:COMPUTERNAME`_$timestamp.html"
        
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Filter = "Archivo HTML|*.html"
        $saveDialog.Title = "Guardar registro"
        $saveDialog.FileName = $defaultFileName
        
        if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $systemInfo = Get-SystemInfoHTML
            
            # Agregar el registro de eventos al HTML
            $htmlContent = $systemInfo + @"
<div class="section">REGISTRO DE EVENTOS</div>
<div class="data">
    <div class="log-section">$($txtLog.Text)</div>
</div>
<div class="timestamp">Generado el: $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")</div>
</body>
</html>
"@
            
            # Guardar el archivo HTML
            $htmlContent | Out-File $saveDialog.FileName -Encoding UTF8
            
            [System.Windows.Forms.MessageBox]::Show(
                "Registro guardado exitosamente en:`n$($saveDialog.FileName)",
                "Guardado Completado",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
    })

    $tab4.Controls.AddRange(@($txtLog, $btnSaveLog))

    # Agregar pestañas al control
    $tabControl.Controls.AddRange(@($tab1, $tab2, $tab3, $tab4))
    $form.Controls.Add($tabControl)

    # Mostrar el formulario
    $form.ShowDialog()
}

# Ejecutar la funcion principal
Main

