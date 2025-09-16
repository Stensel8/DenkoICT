<#
.SYNOPSIS
    MDT Task Sequence Script to install vendor driver tools via WinGet and run driver updates.
.DESCRIPTION
    Detects system manufacturer and installs the appropriate vendor driver tool (Dell, HP, Lenovo) via WinGet, then runs a driver update.
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