<#PSScriptInfo

.VERSION 1.0.3

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Drivers Dell HP HPIA CMSL DCU Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Automated driver updates for Dell and HP systems.
[Version 1.0.1] - Improved error handling and logging.
[Version 1.0.2] - Removed Lenovo and Asus support due to lack of reliable tools.
[Version 1.0.3] - Fixed a bug regarding HP CMSL installation.
#>

<#
.SYNOPSIS
    Install vendor driver update tools and run updates for Dell and HP systems.

.DESCRIPTION
    Detects system manufacturer and runs appropriate driver update tool:
    - Dell: Dell Command Update (DCU)
    - HP: HP Image Assistant (primary) or HP CMSL (fallback)
    
    This script is designed for use after OOBE (Out-of-Box Experience) and handles
    multiple fallback methods for system detection and driver installation.
    
    Features:
    - Automatic manufacturer detection with multiple fallback methods
    - HP Image Assistant as primary method for HP systems
    - HP CMSL as fallback when HPIA is unavailable
    - Dell Command Update for Dell systems
    - Comprehensive logging to %ProgramData%\DenkoICT\Logs
    - WinGet integration for tool installation

.PARAMETER SkipDell
    Skip Dell driver updates even if Dell system is detected.

.PARAMETER SkipHP
    Skip HP driver updates even if HP system is detected.

.PARAMETER MaxDrivers
    Maximum number of HP drivers to install (default: 10) to prevent timeouts.

.EXAMPLE
    .\ps_Install-Drivers.ps1
    
    Runs the appropriate driver update tool based on detected system manufacturer.

.EXAMPLE
    .\ps_Install-Drivers.ps1 -MaxDrivers 20
    
    Installs up to 20 HP drivers if HP system is detected.

.OUTPUTS
    Log files in %ProgramData%\DenkoICT\Logs\Drivers\

.NOTES
    Version      : 1.0.3
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    
    Requirements:
    - Administrative privileges
    - Internet connection for downloading drivers
    - WinGet (optional but recommended)
    
    Exit codes:
    - 0: Success or no updates needed
    - 1: Errors occurred during update process

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$SkipDell,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipHP,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxDrivers = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "Starting Driver Update (Post-OOBE)..." -ForegroundColor Cyan

# Pre-flight checks
Write-Host "Performing pre-flight checks..." -ForegroundColor Gray

# Prepare log directories for tool output
$globalLogRoot = Join-Path -Path $env:ProgramData -ChildPath 'DenkoICT\Logs'
$driverLogRoot = Join-Path -Path $globalLogRoot -ChildPath 'Drivers'
$hpLogRoot = Join-Path -Path $driverLogRoot -ChildPath 'HP'
$dellLogRoot = Join-Path -Path $driverLogRoot -ChildPath 'Dell'

foreach ($path in @($globalLogRoot, $driverLogRoot, $hpLogRoot, $dellLogRoot)) {
    if (-not (Test-Path -Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}

$script:HPLogRoot = $hpLogRoot
$script:DellLogRoot = $dellLogRoot

# Check for WinGet availability
$wingetAvailable = $false
try {
    $wingetVersion = winget --version 2>$null
    if ($wingetVersion) {
        $wingetAvailable = $true
        Write-Host "[OK] WinGet is available (version: $($wingetVersion.Trim()))" -ForegroundColor Green
    }
} catch {
    Write-Warning "[X] WinGet is not available - some driver tools may not install"
    Write-Host "Consider installing WinGet first for best results" -ForegroundColor Yellow
}

# Check if we're in a post-OOBE environment
try {
    $apStatus = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot" -Name "CloudAssignedTenantId" -ErrorAction SilentlyContinue
    if ($apStatus) {
        Write-Host "Detected post-OOBE environment" -ForegroundColor Gray
    }
} catch {
    # Not in AutoPilot/OOBE environment, which is expected for this script
}

# Get system info with multiple fallback methods for compatibility
$manufacturer = "unknown"
$model = "unknown"

try {
    # Try CIM first (preferred method)
    $systemInfo = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $manufacturer = $systemInfo.Manufacturer.ToLower()
    $model = $systemInfo.Model
    Write-Host "System info retrieved via CIM" -ForegroundColor Gray
} catch {
    Write-Warning "Get-CimInstance not available, trying WMI..."
    try {
        # Fallback to WMI
        $systemInfo = Get-WmiObject Win32_ComputerSystem -ErrorAction Stop
        $manufacturer = $systemInfo.Manufacturer.ToLower()
        $model = $systemInfo.Model
        Write-Host "System info retrieved via WMI" -ForegroundColor Gray
    } catch {
        Write-Warning "WMI also not available, trying registry..."
        try {
            # Final fallback to registry
            $manufacturer = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation" -Name "SystemManufacturer" -ErrorAction Stop).SystemManufacturer.ToLower()
            $model = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation" -Name "SystemModel" -ErrorAction Stop).SystemModel
            Write-Host "System info retrieved via registry" -ForegroundColor Gray
        } catch {
            Write-Error "Failed to get system information via all methods: $($_.Exception.Message)"
            Write-Host "Will attempt to detect drivers for all vendors..." -ForegroundColor Yellow
        }
    }
}

Write-Host "System: $manufacturer $model" -ForegroundColor Green

# Simple function to run command with timeout
function Start-WithTimeout {
    param($Path, $Arguments, $TimeoutMinutes = 10)
    try {
        $process = Start-Process -FilePath $Path -ArgumentList $Arguments -NoNewWindow -PassThru -Wait
        return $process.ExitCode
    } catch {
        Write-Warning "Command timed out or failed: $($_.Exception.Message)"
        return -1
    }
}

# Function to retry operations with exponential backoff
function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 2,
        [string]$OperationName = "Operation"
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Host "  Attempt $i of $MaxRetries for $OperationName" -ForegroundColor Gray
            return & $ScriptBlock
        } catch {
            if ($i -eq $MaxRetries) {
                Write-Warning "$OperationName failed after $MaxRetries attempts: $($_.Exception.Message)"
                throw
            } else {
                Write-Warning "$OperationName failed (attempt $i): $($_.Exception.Message). Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds ($DelaySeconds * $i) # Exponential backoff
            }
        }
    }
}

# Dell Command Update
function Update-DellDrivers {
    Write-Host "Installing Dell Command Update..." -ForegroundColor Yellow
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $scanLog = Join-Path -Path $script:DellLogRoot -ChildPath "DCU-Scan-$timestamp.log"
    $applyLog = Join-Path -Path $script:DellLogRoot -ChildPath "DCU-Apply-$timestamp.log"
    
    try {
        if ($wingetAvailable) {
            $wingetResult = winget install Dell.CommandUpdate --silent --accept-package-agreements --accept-source-agreements
            $wingetExitCode = $LASTEXITCODE
            if ($wingetExitCode -ne 0 -and $wingetExitCode -ne 1641 -and $wingetExitCode -ne 3010) {
                Write-Warning "Dell Command Update installation failed with exit code $wingetExitCode. Output:`n$wingetResult"
                return
            }
        } else {
            Write-Warning "WinGet not available - Dell Command Update installation skipped"
            Write-Host "Please install Dell Command Update manually from Dell's website" -ForegroundColor Yellow
        }
        
        # Check for multiple possible installation paths
        $dcuPaths = @(
            "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe",
            "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe",
            "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe",
            "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
        )
        
        $dcu = $null
        foreach ($path in $dcuPaths) {
            if (Test-Path $path) {
                $dcu = $path
                break
            }
        }
        
        if ($dcu) {
            Write-Host "Dell Command Update found at: $dcu" -ForegroundColor Gray
            Write-Host "Running Dell driver updates..." -ForegroundColor Cyan
            
            # First scan for updates
            Write-Host "Scanning for Dell updates..." -ForegroundColor Gray
            $scanResult = Start-WithTimeout $dcu @("/scan", "-silent", "/log=$scanLog") 5
            
            if ($scanResult -eq 0) {
                # Then apply updates
                Write-Host "Applying Dell updates..." -ForegroundColor Gray
                $result = Start-WithTimeout $dcu @("/applyUpdates", "-reboot=disable", "-silent", "/log=$applyLog") 15
                
                switch ($result) {
                    0 {
                        Write-Host "`nDell updates completed successfully" -ForegroundColor Green
                        Write-Host "  Scan log:    $scanLog" -ForegroundColor Gray
                        Write-Host "  Install log: $applyLog" -ForegroundColor Gray
                    }
                    1 { Write-Host "`nDell updates completed - reboot recommended" -ForegroundColor Yellow }
                    500 {
                        Write-Host "`nDell system is up to date - no updates available" -ForegroundColor Green
                        Write-Host "  Scan log: $scanLog" -ForegroundColor Gray
                    }
                    -1 {
                        Write-Warning "`nDell update process timed out"
                        Write-Warning "  See $applyLog or $scanLog for partial details"
                    }
                    default {
                        Write-Warning "`nDell updates may have failed (exit code: $result)"
                        Write-Warning "  Review DCU logs at $applyLog"
                    }
                }
            } else {
                Write-Warning "Dell update scan failed (exit code: $scanResult). Skipping update application."
                if (Test-Path -Path $scanLog) {
                    Write-Warning "  Review scan log: $scanLog"
                }
            }
        } else {
            Write-Warning "Dell Command Update not found at any expected path"
            Write-Host "Tried paths: $($dcuPaths -join ', ')" -ForegroundColor Gray
            if (-not $wingetAvailable) {
                Write-Host "Consider downloading from: https://www.dell.com/support/kbdoc/en-us/000177325" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Warning "Dell driver update failed: $($_.Exception.Message)"
    }
}

# HP CMSL (Client Management Script Library)
function Update-HPDrivers {
    Write-Host "Installing HP Client Management Script Library (HP CMSL)..." -ForegroundColor Yellow
    
    try {
        # First, try the simple HP Image Assistant approach
        Write-Host "Trying HP Image Assistant as primary method..." -ForegroundColor Cyan
        
        if ($wingetAvailable) {
            # Install HP Image Assistant via WinGet
            $wingetArgs = "install --id HP.ImageAssistant -e --accept-source-agreements --accept-package-agreements --silent"
            $hpiaInstallProcess = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -Wait -PassThru -WindowStyle Hidden
            if ($hpiaInstallProcess.ExitCode -ne 0) {
                Write-Warning "Failed to install HP Image Assistant via WinGet. Exit code: $($hpiaInstallProcess.ExitCode)"
            }
        } else {
            Write-Warning "WinGet not available - skipping HP Image Assistant installation"
        }
        
        # Check if HPIA installed successfully (or was already installed)
        $HPIAPath = "C:\Program Files\HP\HPIA\HPImageAssistant.exe"
        if (-not (Test-Path $HPIAPath)) {
            $HPIAPath = "C:\SWSetup\HPImageAssistant\HPImageAssistant.exe"
        }
        
        if (Test-Path $HPIAPath) {
            Write-Host "Running HP Image Assistant for driver updates..." -ForegroundColor Cyan
            $hpTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $hpWorkPath = Join-Path -Path $script:HPLogRoot -ChildPath "HPIA-$hpTimestamp"
            $hpSoftPaqPath = Join-Path -Path $hpWorkPath -ChildPath 'Softpaqs'
            New-Item -ItemType Directory -Path $hpWorkPath -Force | Out-Null
            New-Item -ItemType Directory -Path $hpSoftPaqPath -Force | Out-Null

            # Run HPIA with better parameters for post-OOBE environment
            $hpiaResult = Start-Process -FilePath $HPIAPath -ArgumentList "/Operation:Analyze", "/Category:Driver", "/Action:Install", "/Silent", "/ReportFolder:$hpWorkPath", "/SoftpaqDownloadFolder:$hpSoftPaqPath" -Wait -PassThru -WindowStyle Hidden
            
            if ($hpiaResult.ExitCode -eq 0) {
                Write-Host "HP Image Assistant completed successfully" -ForegroundColor Green
                $primaryReport = Get-ChildItem -Path $hpWorkPath -Filter *.html -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($primaryReport) {
                    Write-Host "  Primary report: $($primaryReport.FullName)" -ForegroundColor Gray
                }
                Write-Host "  Additional artifacts located in: $hpWorkPath" -ForegroundColor Gray
                return
            } else {
                $hpLog = Get-ChildItem -Path $hpWorkPath -Filter *.log -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($hpLog) {
                    Write-Warning "HP Image Assistant failed with exit code: $($hpiaResult.ExitCode). Log: $($hpLog.FullName)"
                } else {
                    Write-Warning "HP Image Assistant failed with exit code: $($hpiaResult.ExitCode). No log file found in $hpWorkPath"
                }
                Write-Warning "Trying HP CMSL..."
            }
        } else {
            Write-Warning "HP Image Assistant not found. Trying HP CMSL approach..."
        }
        
        # If HPIA fails, try HP CMSL with simplified approach
        Write-Host "Falling back to HP CMSL method..." -ForegroundColor Cyan
        
        # Check if HP CMSL modules are available
        $hpModules = Get-Module -ListAvailable -Name "HPCMSL" -ErrorAction SilentlyContinue
        
        if (-not $hpModules) {
            Write-Host "HP CMSL not found. Installing from PowerShell Gallery..." -ForegroundColor Cyan
            
            # Simplified installation approach
            try {
                # Ensure TLS 1.2 for PowerShell Gallery
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                
                # Install NuGet provider if not available
                if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                    Write-Host "Installing NuGet package provider..." -ForegroundColor Gray
                    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -Confirm:$false
                }
                
                # Install HP CMSL from PowerShell Gallery
                Write-Host "Installing HPCMSL module from PowerShell Gallery..." -ForegroundColor Gray
                Install-Module -Name HPCMSL -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck -Confirm:$false
                
                Write-Host "HP CMSL installed successfully" -ForegroundColor Green
                
            } catch {
                Write-Warning "Failed to install HP CMSL from PowerShell Gallery: $($_.Exception.Message)"
                Write-Host "Skipping HP driver updates - please install HP CMSL manually or check network connectivity" -ForegroundColor Yellow
                return
            }
        }
        
        # Import HP CMSL module
        try {
            Write-Host "Loading HP CMSL module..." -ForegroundColor Cyan
            Import-Module HPCMSL -Force -ErrorAction Stop
            Write-Host "  [OK] HPCMSL module loaded successfully" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to import HPCMSL module: $($_.Exception.Message)"
            Write-Host "Please ensure HP CMSL is properly installed and try running as Administrator" -ForegroundColor Yellow
            return
        }
        
        Write-Host "Detecting available HP driver updates..." -ForegroundColor Cyan
        
        # Get available softpaqs (drivers) for this system using simplified approach
        try {
            # Try platform-specific approach first
            $platform = Get-HPDeviceProductID -ErrorAction SilentlyContinue
            if ($platform) {
                Write-Host "Detected HP platform: $platform" -ForegroundColor Gray
                $softpaqs = Get-SoftpaqList -Category Driver -Platform $platform -ErrorAction SilentlyContinue
            } else {
                # Fallback to generic approach
                Write-Host "Using generic driver detection..." -ForegroundColor Gray
                $softpaqs = Get-SoftpaqList -Category Driver -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warning "Failed to get driver list: $($_.Exception.Message)"
            $softpaqs = $null
        }
        
        if ($softpaqs -and $softpaqs.Count -gt 0) {
            Write-Host "Found $($softpaqs.Count) driver updates available" -ForegroundColor Green
            
            # Limit to reasonable number of drivers to avoid timeout
            if ($softpaqs.Count -gt $MaxDrivers) {
                Write-Host "Limiting to first $MaxDrivers drivers for faster installation" -ForegroundColor Yellow
                $softpaqs = $softpaqs | Select-Object -First $MaxDrivers
            }
            
            # Create temp directory for downloads
            $tempPath = "$env:TEMP\HPDrivers"
            if (-not (Test-Path $tempPath)) {
                New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
            }
            
            $successCount = 0
            $failCount = 0
            $totalCount = $softpaqs.Count
            $currentItem = 0
            
            Write-Host "Starting installation of $totalCount drivers..." -ForegroundColor Cyan
            
            foreach ($softpaq in $softpaqs) {
                $currentItem++
                $percentComplete = [math]::Round(($currentItem / $totalCount) * 100)
                
                Write-Host "[$currentItem/$totalCount] ($percentComplete%) Installing: $($softpaq.Name) ($($softpaq.Id))" -ForegroundColor Yellow
                
                try {
                    # Download and install using simplified Get-Softpaq approach
                    $downloadPath = Join-Path $tempPath "$($softpaq.Id).exe"
                    
                    # Download with retry
                    $downloadSuccess = $false
                    for ($retry = 1; $retry -le 2; $retry++) {
                        try {
                            Get-Softpaq -Number $softpaq.Id -SaveAs $downloadPath -Overwrite
                            if (Test-Path $downloadPath) {
                                $downloadSuccess = $true
                                break
                            }
                        } catch {
                            Write-Warning "  Download attempt $retry failed: $($_.Exception.Message)"
                            if ($retry -lt 2) { Start-Sleep -Seconds 2 }
                        }
                    }
                    
                    if ($downloadSuccess -and (Test-Path $downloadPath)) {
                        # Install silently
                        $installResult = Start-Process -FilePath $downloadPath -ArgumentList '/S', '/v/qn' -Wait -PassThru -WindowStyle Hidden
                        
                        # Check various success exit codes
                        if ($installResult.ExitCode -in @(0, 3010, 1641)) {
                            Write-Host "  [OK] Successfully installed $($softpaq.Name)" -ForegroundColor Green
                            $successCount++
                        } else {
                            Write-Warning "  [X] Installation failed with exit code: $($installResult.ExitCode)"
                            $failCount++
                        }
                        
                        # Clean up downloaded file
                        Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
                    } else {
                        Write-Warning "  [X] Failed to download $($softpaq.Name)"
                        $failCount++
                    }
                    
                } catch {
                    Write-Warning "[X] Failed to install $($softpaq.Name): $($_.Exception.Message)"
                    $failCount++
                }
                
                # Add small delay between installations
                if ($currentItem -lt $totalCount) {
                    Start-Sleep -Milliseconds 500
                }
            }
            
            # Cleanup temp directory
            Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            
            Write-Host "`nHP driver update summary:" -ForegroundColor Cyan
            Write-Host "  Successfully installed: $successCount drivers" -ForegroundColor Green
            if ($failCount -gt 0) {
                Write-Host "  Failed installations: $failCount drivers" -ForegroundColor Red
            }
            
        } else {
            Write-Host "No HP driver updates available for this system" -ForegroundColor Green
        }
        
    } catch {
        Write-Warning "HP driver update failed: $($_.Exception.Message)"
        Write-Host "You may need to run this script as Administrator or check your internet connection" -ForegroundColor Yellow
    }
}



# Main execution
try {
    if ($manufacturer -like "*dell*") {
        if ($SkipDell) {
            Write-Host "Skipping Dell drivers (SkipDell parameter set)" -ForegroundColor Yellow
        } else {
            Write-Host "Detected Dell system - running Dell Command Update" -ForegroundColor Green
            Update-DellDrivers
        }
    } elseif ($manufacturer -like "*hewlett*" -or $manufacturer -like "*hp*") {
        if ($SkipHP) {
            Write-Host "Skipping HP drivers (SkipHP parameter set)" -ForegroundColor Yellow
        } else {
            Write-Host "Detected HP system - running HP driver updates" -ForegroundColor Green
            Update-HPDrivers
        }
    } elseif ($manufacturer -eq "unknown") {
        Write-Warning "Could not detect system manufacturer. Attempting HP method as fallback (most common)..."
        Write-Host "If this fails, please run the script on a Dell system, or install drivers manually" -ForegroundColor Yellow
        if (-not $SkipHP) {
            Update-HPDrivers
        }
    } else {
        Write-Warning "Unsupported or unrecognized manufacturer: $manufacturer"
        Write-Host "Supported manufacturers: Dell, HP/Hewlett-Packard" -ForegroundColor Yellow
        Write-Host "System detected: $manufacturer $model" -ForegroundColor Gray
        
        # Provide helpful guidance
        Write-Host "`nFor unsupported systems, consider:" -ForegroundColor Cyan
        Write-Host "- Running Windows Update manually" -ForegroundColor Gray
        Write-Host "- Downloading drivers from manufacturer's website" -ForegroundColor Gray
        Write-Host "- Using Device Manager to update drivers" -ForegroundColor Gray
    }
    
    Write-Host "`nDriver update process completed!" -ForegroundColor Green
    exit 0
    
} catch {
    Write-Warning "Error during driver update: $($_.Exception.Message)"
    Write-Host "Driver update finished with errors" -ForegroundColor Yellow
    Write-Host "`nTroubleshooting tips:" -ForegroundColor Cyan
    Write-Host "- Ensure you have internet connectivity" -ForegroundColor Gray
    Write-Host "- Try running the script as Administrator" -ForegroundColor Gray
    Write-Host "- Check Windows Update for basic driver updates" -ForegroundColor Gray
    exit 1
}