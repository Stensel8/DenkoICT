<#
.SYNOPSIS
    Task Script to install vendor driver tools and run driver updates.
.DESCRIPTION
    Detects system manufacturer and installs the appropriate vendor driver tool:
    - Dell: Dell Command Update via WinGet
    - HP: HPDrivers PowerShell module / HP Image Assistant via WinGet / HP CMSL/HPIA
    - Lenovo: Lenovo System Update via WinGet
    
    For HP systems, this script uses the HPDrivers module from PowerShell Gallery which provides:
    - Better reliability than HP CMSL/HPIA
    - Automatic driver detection and installation
    - BIOS update capabilities
    - Automatic cleanup of installation files
    - No dependency on WinGet for HP driver updates
.NOTES
    HP driver updates now use the HPDrivers module: https://github.com/UsefulScripts01/HPDrivers
#>

# Ensure script is running with admin privileges
# If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
# {
#     Write-Warning "This script must be run as Administrator."
#     Exit 1
# }

Write-Host "Starting Driver Update via Vendor Tools..." -ForegroundColor Cyan

# Get Manufacturer and Model
$manufacturer = (Get-WmiObject Win32_ComputerSystem).Manufacturer
$model = (Get-WmiObject Win32_ComputerSystem).Model

Write-Host "Detected Manufacturer: $manufacturer"
Write-Host "Model: $model"

# Normalize manufacturer string
$manufacturer = $manufacturer.ToLower()

function Install-And-RunDell {
    Write-Host "Installing Dell System Update via WinGet..."
    winget install --id Dell.CommandUpdate --accept-source-agreements --accept-package-agreements -e -h
    $dcuPath = "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe"

    if (Test-Path $dcuPath) {
        Write-Host "Running Dell Command Update Scan..."
            & $dcuPath /scan -silent
        Write-Host "Running Dell Command Update Install..."
            & $dcuPath /applyUpdates -silent
    } else {
        Write-Warning "Dell DCU not found at expected path."
    }
}

function Install-And-RunHP {
    Write-Host "Installing HP drivers using HPDrivers PowerShell module..." -ForegroundColor Yellow
    
    try {
        # Ensure NuGet provider is installed
        Write-Host "Installing NuGet package provider..."
        Install-PackageProvider -Name NuGet -MinimumVersion 3.0.0.1 -Force -ErrorAction Stop
        
        # Install HPDrivers module from PowerShell Gallery
        Write-Host "Installing HPDrivers module from PowerShell Gallery..."
        Install-Module -Name HPDrivers -Force -ErrorAction Stop
        
        # Import the module
        Import-Module HPDrivers -Force -ErrorAction Stop
        
        Write-Host "Running HP driver update with HPDrivers module..."
        # Use -NoPrompt for automated installation, -BIOS for BIOS updates, -DeleteInstallationFiles for cleanup
        Get-HPDrivers -NoPrompt -BIOS -DeleteInstallationFiles
        
        Write-Host "HP driver update completed successfully." -ForegroundColor Green
        
    } catch {
        Write-Warning "Failed to install or run HPDrivers module: $($_.Exception.Message)"
        Write-Host "Falling back to HP Image Assistant method..."
        
        # Fallback to original method
        Write-Host "Installing HP Image Assistant via WinGet..."
        winget install --id HP.ImageAssistant -e --accept-source-agreements --accept-package-agreements

        Write-Host "Running HP Image Assistant..."
        $HPIAPath = "C:\SWSetup\HPImageAssistant\HPImageAssistant.exe"
        if (Test-Path $HPIAPath) {
            $downloadPath = "C:\SWSetup"
            New-Item -ItemType Directory -Path $downloadPath -Force | Out-Null

            & $HPIAPath /Operation:Analyze /Category:Driver /Action:Install /Silent /ReportFolder:$downloadPath
        } else {
            Write-Warning "HP Image Assistant not found at expected path."
        }
    }
}

function Install-And-RunLenovo {
    Write-Host "Installing Lenovo System Update (Thin Installer) via WinGet..."
    winget install --id Lenovo.ThinkVantageSystemUpdate -e --accept-source-agreements --accept-package-agreements

    $thinInstallerPath = "C:\Program Files (x86)\Lenovo\System Update\tvsu.exe"

    if (Test-Path $thinInstallerPath) {
        Write-Host "Running Lenovo System Update..."
        & $thinInstallerPath /CM -search A -action INSTALL -noicon -noreboot
    } else {
        Write-Warning "Lenovo System Update not found at expected path."
    }
}

switch -Wildcard ($manufacturer) {
    "*dell*"    { Install-And-RunDell }
    "*hewlett*" { Install-And-RunHP }
    "*hp*"      { Install-And-RunHP }
    "*lenovo*"  { Install-And-RunLenovo }
    default {
        Write-Warning "Unsupported manufacturer: $manufacturer. Skipping driver update."
    }
}

Write-Host "Driver update process completed." -ForegroundColor Green