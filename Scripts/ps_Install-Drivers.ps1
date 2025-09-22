<#
.SYNOPSIS
    Task Script to install vendor driver tools and run driver updates.
.DESCRIPTION
    Detects system manufacturer and installs the appropriate vendor driver tool:
    - Dell: Dell Command Update via WinGet
    - HP Enterprise: HP CMSL via PowerShell 7
    - HP Consumer: Can be run manually via HP Supprt Assistant
    - Lenovo: Lenovo System Update via WinGet
    
    For HP systems, detects if it's enterprise (supports HPCMSL) or consumer (uses HPIA)
.NOTES
    HP Enterprise systems use HP CMSL via PowerShell 7
    HP Consumer systems use HP Image Assistant
#>

Write-Host "Starting Driver Update via Vendor Tools..." -ForegroundColor Cyan

# Get Manufacturer and Model
$manufacturer = (Get-WmiObject Win32_ComputerSystem).Manufacturer
$model = (Get-WmiObject Win32_ComputerSystem).Model

Write-Host "Detected Manufacturer: $manufacturer"
Write-Host "Model: $model"

# Normalize manufacturer string
$manufacturer = $manufacturer.ToLower()

function Test-HPEnterprise {
    # Check if this is an HP Enterprise system that supports HPCMSL/HPIA
    # Based on HP's official platform list: https://ftp.ext.hp.com/pub/caps-softpaq/cmit/imagepal/ref/platformList.html
    
    $model = (Get-WmiObject Win32_ComputerSystem).Model.ToLower()
    
    # HP Enterprise/Business model prefixes that support HPCMSL/HPIA
    $enterpriseKeywords = @(
        "elitebook", "elitedesk", "eliteone", "elite",
        "zbook", "z1", "z2", "z4", "z6", "z8", "z420", "z440", "z640", "z840",
        "prodesk", "probook", "proone",
        "workstation", "server",
        "ml", "dl", "bl"  # Server models
    )
    
    # Consumer model prefixes that do NOT support HPCMSL/HPIA
    $consumerKeywords = @(
        "pavilion", "envy", "omen", "spectre", "stream", "laptop-", "notebook-"
    )
    
    # First check if it's explicitly a consumer model
    foreach ($keyword in $consumerKeywords) {
        if ($model -match $keyword) {
            Write-Warning "Consumer HP model detected: $model"
            Write-Warning "HP CMSL and HP HPIA are not supported on consumer devices."
            Write-Host "Consumer devices should use HP Support Assistant instead." -ForegroundColor Yellow
            return $false
        }
    }
    
    # Then check if it's an enterprise model
    foreach ($keyword in $enterpriseKeywords) {
        if ($model -match $keyword) {
            Write-Host "HP Enterprise/Business model detected: $model" -ForegroundColor Green
            return $true
        }
    }
    
    # If model doesn't match known patterns, check BIOS/additional indicators
    try {
        $bios = Get-WmiObject Win32_BIOS
        if ($bios.Manufacturer -like "*HP*" -and ($bios.SMBIOSBIOSVersion -match "Pro|Elite|Z\d+")) {
            Write-Host "HP Business system detected via BIOS version" -ForegroundColor Green
            return $true
        }
    } catch {
        # If WMI fails, continue to final check
    }
    
    # Unknown HP model - warn and skip
    Write-Warning "Unknown HP model: $model"
    Write-Warning "Cannot determine if this system supports HP CMSL/HPIA"
    Write-Host "Please verify system compatibility at: https://ftp.ext.hp.com/pub/caps-softpaq/cmit/imagepal/ref/platformList.html" -ForegroundColor Yellow
    return $false
}

function Install-And-RunDell {
    Write-Host "Installing Dell System Update via WinGet..."
    winget install --id Dell.CommandUpdate --accept-source-agreements --accept-package-agreements --silent --disable-interactivity -e -h
    $dcuPath = "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe"

    if (Test-Path $dcuPath) {
        Write-Host "Running Dell Command Update Scan..."
        try {
            & $dcuPath /scan -silent -autoSuspendBitLocker=enable
            Write-Host "Running Dell Command Update Install..."
            & $dcuPath /applyUpdates -silent -autoSuspendBitLocker=enable -reboot=disable
            Write-Host "Dell Command Update completed successfully" -ForegroundColor Green
        } catch {
            Write-Warning "Dell Command Update execution failed: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Dell DCU not found at expected path."
    }
}

function Install-And-RunHP-Enterprise {
    Write-Host "HP Enterprise system - installing HP HPIA and running HP CMSL..." -ForegroundColor Yellow
    
    # First install HP HPIA to default SWSetup location for manual use
    Write-Host "Installing HP Image Assistant to SWSetup for manual use..."
    winget install --id HP.ImageAssistant -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
    
    # Check if PowerShell 7 is available for HP CMSL
    $pwsh7Path = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh7Path) {
        Write-Warning "PowerShell 7 not found. Installing via WinGet..."
        winget install --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements --silent --disable-interactivity -e -h
        
        # Refresh PATH or find pwsh
        $pwsh7Path = Get-Command pwsh -ErrorAction SilentlyContinue
        if (-not $pwsh7Path) {
            $pwsh7Path = "${env:ProgramFiles}\PowerShell\7\pwsh.exe"
        }
    }
    
    if (Test-Path $pwsh7Path.Source -ErrorAction SilentlyContinue) {
        Write-Host "Using PowerShell 7 to install and run HP CMSL for automatic updates..."
        
        # Create a PowerShell 7 script to handle HP CMSL
        $hpcmslScript = @"
# Set execution policy and security settings for silent operation
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host 'Installing HP CMSL (Client Management Script Library)...' -ForegroundColor Cyan
try {
    Install-Module -Name HPCMSL -Force -Scope CurrentUser -AllowClobber -Confirm:`$false -AcceptLicense -SkipPublisherCheck
    
    # Import and use HP CMSL
    Import-Module HPCMSL -Force
    Write-Host 'HP CMSL loaded successfully' -ForegroundColor Green

    Write-Host 'Scanning for available driver and BIOS updates...' -ForegroundColor Yellow
    `$updates = Get-SoftpaqList | Where-Object {(`$_.Category -eq 'Driver' -or `$_.Category -eq 'BIOS') -and `$_.IsInstalled -eq `$false}
    Write-Host "Found `$(`$updates.Count) available updates" -ForegroundColor Cyan
    
    if (`$updates.Count -gt 0) {
        Write-Host 'Installing updates via HP CMSL...' -ForegroundColor Yellow
        `$downloadPath = 'C:\SWSetup\HPDrivers'
        New-Item -ItemType Directory -Path `$downloadPath -Force | Out-Null
        
        `$updates | Install-Softpaq -Yes -DownloadPath `$downloadPath -Offline -Silent
        Write-Host 'HP CMSL driver and BIOS updates completed successfully.' -ForegroundColor Green
    } else {
        Write-Host 'No driver or BIOS updates available.' -ForegroundColor Green
    }
} catch {
    Write-Warning "HP CMSL execution failed: `$(`$_.Exception.Message)"
    Write-Host 'Continuing with HP Image Assistant fallback...' -ForegroundColor Yellow
}
"@
        
        # Save script to temp file and execute with PowerShell 7
        $tempScript = "$env:TEMP\hpcmsl_update.ps1"
        $hpcmslScript | Out-File -FilePath $tempScript -Encoding UTF8
        
        Write-Host "Executing HP CMSL via PowerShell 7..." -ForegroundColor Cyan
        & $pwsh7Path.Source -ExecutionPolicy Bypass -File $tempScript
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
        
    } else {
        Write-Warning "PowerShell 7 installation failed."
        Write-Host "HP Image Assistant has been installed to C:\SWSetup\HPImageAssistant\ for manual use." -ForegroundColor Yellow
    }
    
    # Always inform about HPIA availability
    Write-Host ""
    Write-Host "HP Image Assistant is available for manual driver updates at:" -ForegroundColor Cyan
    Write-Host "C:\SWSetup\HPImageAssistant\HPImageAssistant.exe" -ForegroundColor White
}

function Install-And-RunHP-HPIA {
    Write-Host "HP Enterprise system - using HP Image Assistant..." -ForegroundColor Yellow
    
    # Install HP Image Assistant via WinGet
    Write-Host "Installing HP Image Assistant via WinGet..."
    winget install --id HP.ImageAssistant -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity

    # Find HP Image Assistant executable
    $HPIAPaths = @(
        "C:\Program Files\HP\HPIA\HPImageAssistant.exe",
        "C:\SWSetup\HPImageAssistant\HPImageAssistant.exe",
        "${env:ProgramFiles}\HP\HPIA\HPImageAssistant.exe"
    )
    
    $HPIAPath = $null
    foreach ($path in $HPIAPaths) {
        if (Test-Path $path) {
            $HPIAPath = $path
            break
        }
    }
    
    if ($HPIAPath) {
        Write-Host "Running HP Image Assistant from: $HPIAPath"
        $downloadPath = "C:\Temp\HPDrivers"
        New-Item -ItemType Directory -Path $downloadPath -Force | Out-Null

        try {
            & $HPIAPath /Operation:Analyze /Category:Driver,BIOS /Action:Install /Silent /ReportFolder:$downloadPath /SoftpaqDownloadFolder:$downloadPath /NonInteractive
            Write-Host "HP Image Assistant update completed." -ForegroundColor Green
        } catch {
            Write-Warning "HP Image Assistant execution failed: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "HP Image Assistant not found at expected paths."
    }
}

function Install-And-RunLenovo {
    Write-Host "Installing Lenovo System Update (Thin Installer) via WinGet..."
    winget install --id Lenovo.ThinkVantageSystemUpdate -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity

    $thinInstallerPath = "C:\Program Files (x86)\Lenovo\System Update\tvsu.exe"

    if (Test-Path $thinInstallerPath) {
        Write-Host "Running Lenovo System Update..."
        try {
            & $thinInstallerPath /CM -search A -action INSTALL -noicon -noreboot -includerebootpackages 3 -exporttowmi -packagetypes 1,2,3,4
            Write-Host "Lenovo System Update completed successfully" -ForegroundColor Green
        } catch {
            Write-Warning "Lenovo System Update execution failed: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Lenovo System Update not found at expected path."
    }
}

# Main logic with error handling
try {
    if ($manufacturer -like "*dell*") {
        try {
            Install-And-RunDell
        } catch {
            Write-Warning "Dell driver update failed: $($_.Exception.Message)"
            Write-Host "Continuing script execution..." -ForegroundColor Yellow
        }
    } elseif ($manufacturer -like "*hewlett*" -or $manufacturer -like "*hp*") {
        try {
            if (Test-HPEnterprise) {
                Install-And-RunHP-Enterprise  # Installs HPIA + runs HP CMSL automatically
            } else {
                Write-Warning "HP Consumer system or unsupported model detected."
                Write-Warning "HP CMSL and HP HPIA are not supported on this device."
                Write-Host "For consumer HP devices, please use HP Support Assistant manually." -ForegroundColor Yellow
            }
        } catch {
            Write-Warning "HP driver update failed: $($_.Exception.Message)"
            Write-Host "Continuing script execution..." -ForegroundColor Yellow
        }
    } elseif ($manufacturer -like "*lenovo*") {
        try {
            Install-And-RunLenovo
        } catch {
            Write-Warning "Lenovo driver update failed: $($_.Exception.Message)"
            Write-Host "Continuing script execution..." -ForegroundColor Yellow
        }
    } else {
        Write-Warning "Unsupported manufacturer: $manufacturer. Skipping driver update."
    }
} catch {
    Write-Warning "Driver update process encountered an error: $($_.Exception.Message)"
    Write-Host "Script execution completed with errors." -ForegroundColor Yellow
    exit 0  # Exit with success code to not fail auto-unattend
}

Write-Host "Driver update process completed." -ForegroundColor Green
