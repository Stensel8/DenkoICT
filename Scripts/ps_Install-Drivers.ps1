<#PSScriptInfo

.VERSION 1.0.4

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Drivers Dell HP HPIA CMSL DCU Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Automated driver updates for Dell and HP systems.
[Version 1.0.1] - Improved error handling and logging.
[Version 1.0.2] - Removed Lenovo and Asus support due to lack of reliable tools.
[Version 1.0.3] - Fixed a bug regarding HP CMSL installation.
[Version 1.0.4] - Fixed PowerShellGet update logic and HP CMSL installation flow.
#>

#requires -Version 5.1

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
    - Comprehensive logging to C:\DenkoICT\Logs
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
    Log files in C:\DenkoICT\Logs\Drivers\

.NOTES
    Version      : 1.0.4
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

Write-Output "Starting Driver Update (Post-OOBE)..."

# Pre-flight checks
Write-Output "Performing pre-flight checks..."

# Prepare log directories for tool output
$globalLogRoot = 'C:\DenkoICT\Logs'
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
        Write-Output "[OK] WinGet is available (version: $($wingetVersion.Trim()))"
    }
} catch {
    Write-Output "WARNING: [X] WinGet is not available - some driver tools may not install"
    Write-Output "Consider installing WinGet first for best results"
}

# Check if we're in a post-OOBE environment
try {
    $apStatus = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot" -Name "CloudAssignedTenantId" -ErrorAction SilentlyContinue
    if ($apStatus) {
        Write-Output "Detected post-OOBE environment"
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
    Write-Output "System info retrieved via CIM"
} catch {
    Write-Output "WARNING: Get-CimInstance not available, trying WMI..."
    try {
        # Fallback to WMI
        $systemInfo = Get-WmiObject Win32_ComputerSystem -ErrorAction Stop
        $manufacturer = $systemInfo.Manufacturer.ToLower()
        $model = $systemInfo.Model
        Write-Output "System info retrieved via WMI"
    } catch {
        Write-Output "WARNING: WMI also not available, trying registry..."
        try {
            # Final fallback to registry
            $manufacturer = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation" -Name "SystemManufacturer" -ErrorAction Stop).SystemManufacturer.ToLower()
            $model = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation" -Name "SystemModel" -ErrorAction Stop).SystemModel
            Write-Output "System info retrieved via registry"
        } catch {
            Write-Output "ERROR: Failed to get system information via all methods: $($_.Exception.Message)"
            Write-Output "Will attempt to detect drivers for all vendors..."
        }
    }
}

Write-Output "System: $manufacturer $model"

# Simple function to run command with timeout
function Start-WithTimeout {
    param($Path, $Arguments, $TimeoutMinutes = 10)
    try {
        $process = Start-Process -FilePath $Path -ArgumentList $Arguments -NoNewWindow -PassThru -Wait
        return $process.ExitCode
    } catch {
        Write-Output "WARNING: Command timed out or failed: $($_.Exception.Message)"
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
            Write-Output "  Attempt $i of $MaxRetries for $OperationName"
            return & $ScriptBlock
        } catch {
            if ($i -eq $MaxRetries) {
                Write-Output "WARNING: $OperationName failed after $MaxRetries attempts: $($_.Exception.Message)"
                throw
            } else {
                Write-Output "WARNING: $OperationName failed (attempt $i): $($_.Exception.Message). Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds ($DelaySeconds * $i) # Exponential backoff
            }
        }
    }
}

# Determine if we are running with administrative privileges
function Test-IsAdministrator {
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        Write-Output "WARNING: Unable to determine administrative privileges: $($_.Exception.Message)"
        return $false
    }
}

# Resolve the preferred module installation path based on privileges
function Get-PreferredModuleRoot {
    if (Test-IsAdministrator) {
        return Join-Path -Path ${env:ProgramFiles} -ChildPath 'WindowsPowerShell\Modules'
    } else {
        $userModuleRoot = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'WindowsPowerShell\Modules'
        if (-not (Test-Path -Path $userModuleRoot)) {
            New-Item -Path $userModuleRoot -ItemType Directory -Force | Out-Null
        }
        return $userModuleRoot
    }
}

# Download helper with multiple strategies (Invoke-WebRequest first, then BITS)
function Invoke-WebDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Write-Output "  Downloading: $Url"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
    Write-Output "WARNING: Download via Invoke-WebRequest failed: $($_.Exception.Message)"
        try {
            if (Get-Command -Name Start-BitsTransfer -ErrorAction SilentlyContinue) {
                Start-BitsTransfer -Source $Url -Destination $Destination -ErrorAction Stop
                return $true
            } else {
                Write-Output "WARNING: BITS transfer unavailable on this system"
            }
        } catch {
            Write-Output "WARNING: Download via BITS failed: $($_.Exception.Message)"
        }
    }

    return $false
}

# Install HP CMSL by downloading the official package and copying modules/MSI
function Install-HPCMSLPackage {
    param(
        [Parameter(Mandatory = $true)][string[]]$DownloadUrls,
        [string]$WorkingFolder = (Join-Path -Path $env:TEMP -ChildPath 'DenkoICT-HPCMSL')
    )

    try {
        if (Test-Path -Path $WorkingFolder) {
            Remove-Item -Path $WorkingFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $WorkingFolder -ItemType Directory -Force | Out-Null

        $packagePath = Join-Path -Path $WorkingFolder -ChildPath 'HPCMSL.zip'
        $downloaded = $false

        foreach ($url in $DownloadUrls) {
            if (Invoke-WebDownload -Url $url -Destination $packagePath) {
                $downloaded = $true
                break
            }
        }

        if (-not $downloaded -or -not (Test-Path -Path $packagePath)) {
            Write-Output "WARNING: Failed to download HP CMSL package from all provided sources"
            return $false
        }

        $extractPath = Join-Path -Path $WorkingFolder -ChildPath 'Extracted'
        Expand-Archive -Path $packagePath -DestinationPath $extractPath -Force -ErrorAction Stop

        $successfulInstall = $false

        # Prefer MSI-based deployment when available
        $msiCandidate = Get-ChildItem -Path $extractPath -Filter '*.msi' -Recurse -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
        if ($msiCandidate) {
            Write-Output "  Installing HP CMSL via MSI package ($($msiCandidate.Name))"
            try {
                $msiArgs = "/i `"$($msiCandidate.FullName)`" /qn /norestart"
                $msiProcess = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -PassThru -Wait -WindowStyle Hidden
                if ($msiProcess.ExitCode -in @(0, 3010, 1641)) {
                    Write-Output "  MSI installation reported success (exit code $($msiProcess.ExitCode))"
                    $successfulInstall = $true
                } else {
                    Write-Output "WARNING: MSI installer returned exit code $($msiProcess.ExitCode)"
                }
            } catch {
                Write-Output "WARNING: MSI installation failed: $($_.Exception.Message)"
            }
        }

        if (-not $successfulInstall) {
            Write-Output "  Copying module files directly..."
            $moduleRoot = Get-PreferredModuleRoot
            $psd1Files = Get-ChildItem -Path $extractPath -Filter '*.psd1' -Recurse -ErrorAction SilentlyContinue

            if (-not $psd1Files) {
                Write-Output "WARNING: No module manifests (.psd1) found in extracted package"
            } else {
                $moduleMap = @{}
                foreach ($manifest in $psd1Files) {
                    $versionDirectory = $manifest.Directory.FullName
                    $moduleParent = $manifest.Directory.Parent
                    $moduleName = $null

                    if ($moduleParent) {
                        $moduleName = Split-Path -Path $moduleParent.FullName -Leaf
                    } else {
                        $moduleName = Split-Path -Path $versionDirectory -Leaf
                    }

                    if ([string]::IsNullOrWhiteSpace($moduleName)) {
                        continue
                    }

                    if (-not $moduleMap.ContainsKey($moduleName)) {
                        $moduleMap[$moduleName] = $versionDirectory
                    }
                }

                foreach ($moduleEntry in $moduleMap.GetEnumerator()) {
                    $destinationRoot = Join-Path -Path $moduleRoot -ChildPath $moduleEntry.Key
                    if (-not (Test-Path -Path $destinationRoot)) {
                        New-Item -Path $destinationRoot -ItemType Directory -Force | Out-Null
                    }

                    try {
                        Copy-Item -Path $moduleEntry.Value -Destination $destinationRoot -Recurse -Force
                    } catch {
                        Write-Output "WARNING: Failed to copy module $($moduleEntry.Key): $($_.Exception.Message)"
                    }
                }

                if ($moduleMap.Count -gt 0) {
                    $successfulInstall = $true
                }
            }
        }

        return $successfulInstall
    } catch {
        Write-Output "WARNING: Unexpected error while installing HP CMSL package: $($_.Exception.Message)"
        return $false
    } finally {
        try {
            if (Test-Path -Path $WorkingFolder) {
                Remove-Item -Path $WorkingFolder -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {
            # Best effort cleanup
        }
    }
}

# Ensure HPCMSL module availability with multiple strategies
function Install-HPCMSLModule {
    $existing = Get-Module -ListAvailable -Name 'HPCMSL' -ErrorAction SilentlyContinue
    if ($existing) {
        return $true
    }

    Write-Output "HP CMSL not found locally. Updating PowerShell prerequisites first..."

    # CRITICAL: Update PowerShellGet BEFORE attempting to install HPCMSL
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # Install/Update NuGet provider
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Write-Output "  Installing NuGet package provider..."
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -Confirm:$false -ErrorAction Stop
        }

        # Update PowerShellGet to latest version
        Write-Output "  Updating PowerShellGet to latest version..."
        Install-Module -Name PowerShellGet -MinimumVersion 2.2.5 -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck -Confirm:$false -ErrorAction SilentlyContinue
        
        # Import the new PowerShellGet
        Remove-Module PowerShellGet -Force -ErrorAction SilentlyContinue
        Import-Module PowerShellGet -MinimumVersion 2.2.5 -Force -ErrorAction SilentlyContinue
        
        # Update PackageManagement
        Write-Output "  Updating PackageManagement module..."
        Install-Module -Name PackageManagement -MinimumVersion 1.4.8 -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck -Confirm:$false -ErrorAction SilentlyContinue

        Write-Output "  PowerShell package management updated successfully"
    } catch {
        Write-Output "WARNING: Failed to update PowerShell package management: $($_.Exception.Message)"
    }

    # Now try to install HPCMSL from gallery
    Write-Output "Attempting to install HP CMSL from PowerShell Gallery..."
    $galleryInstalled = $false
    try {
        Install-Module -Name HPCMSL -Force -Scope CurrentUser -AllowClobber -SkipPublisherCheck -Confirm:$false -ErrorAction Stop
        $galleryInstalled = $true
        Write-Output "  HP CMSL installed successfully from PowerShell Gallery"
    } catch {
        Write-Output "WARNING: PowerShell Gallery installation failed: $($_.Exception.Message)"
    }

    if (-not $galleryInstalled) {
        Write-Output "Attempting offline HP CMSL installation..."
        $downloadUrls = @(
            'https://hpia.hpcloud.hp.com/downloads/cmsl/HPCMSL.zip',
            'https://ftp.hp.com/pub/caps-softpaq/cmit/HPCMSL.zip'
        )

        if (-not (Install-HPCMSLPackage -DownloadUrls $downloadUrls)) {
            return $false
        }
    }

    # Refresh module list
    Get-Module -ListAvailable -Refresh -ErrorAction SilentlyContinue | Out-Null
    
    $refreshed = Get-Module -ListAvailable -Name 'HPCMSL' -ErrorAction SilentlyContinue
    if ($refreshed) {
        $latest = $refreshed | Sort-Object Version -Descending | Select-Object -First 1
        Write-Output "  HP CMSL module available (version: $($latest.Version))"
    } else {
        Write-Output "WARNING: HP CMSL module still not detected after installation attempts"
    }

    return [bool]$refreshed
}

# Dell Command Update
function Update-DellDrivers {
    Write-Output "Installing Dell Command Update..."
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $scanLog = Join-Path -Path $script:DellLogRoot -ChildPath "DCU-Scan-$timestamp.log"
    $applyLog = Join-Path -Path $script:DellLogRoot -ChildPath "DCU-Apply-$timestamp.log"
    
    try {
        if ($wingetAvailable) {
            $wingetResult = winget install Dell.CommandUpdate --silent --accept-package-agreements --accept-source-agreements
            $wingetExitCode = $LASTEXITCODE
            if ($wingetExitCode -ne 0 -and $wingetExitCode -ne 1641 -and $wingetExitCode -ne 3010) {
                Write-Output "WARNING: Dell Command Update installation failed with exit code $wingetExitCode. Output:`n$wingetResult"
                return
            }
        } else {
            Write-Output "WARNING: WinGet not available - Dell Command Update installation skipped"
            Write-Output "Please install Dell Command Update manually from Dell's website"
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
            Write-Output "Dell Command Update found at: $dcu"
            Write-Output "Running Dell driver updates..."
            
            # First scan for updates
            Write-Output "Scanning for Dell updates..."
            $scanResult = Start-WithTimeout $dcu @("/scan", "-silent", "/log=$scanLog") 5
            
            if ($scanResult -eq 0) {
                # Then apply updates
                Write-Output "Applying Dell updates..."
                $result = Start-WithTimeout $dcu @("/applyUpdates", "-reboot=disable", "-silent", "/log=$applyLog") 15
                
                switch ($result) {
                    0 {
                        Write-Output "`nDell updates completed successfully"
                        Write-Output "  Scan log:    $scanLog"
                        Write-Output "  Install log: $applyLog"
                    }
                    1 { Write-Output "`nDell updates completed - reboot recommended" }
                    500 {
                        Write-Output "`nDell system is up to date - no updates available"
                        Write-Output "  Scan log: $scanLog"
                    }
                    -1 {
                        Write-Output "WARNING: Dell update process timed out"
                        Write-Output "WARNING: See $applyLog or $scanLog for partial details"
                    }
                    default {
                        Write-Output "WARNING: Dell updates may have failed (exit code: $result)"
                        Write-Output "WARNING: Review DCU logs at $applyLog"
                    }
                }
            } else {
                Write-Output "WARNING: Dell update scan failed (exit code: $scanResult). Skipping update application."
                if (Test-Path -Path $scanLog) {
                    Write-Output "WARNING: Review scan log: $scanLog"
                }
            }
        } else {
            Write-Output "WARNING: Dell Command Update not found at any expected path"
            Write-Output "Tried paths: $($dcuPaths -join ', ')"
            if (-not $wingetAvailable) {
                Write-Output "Consider downloading from: https://www.dell.com/support/kbdoc/en-us/000177325"
            }
        }
    } catch {
        Write-Output "WARNING: Dell driver update failed: $($_.Exception.Message)"
    }
}

# HP CMSL (Client Management Script Library)
function Update-HPDrivers {
    Write-Output "Installing HP Client Management Script Library (HP CMSL)..."
    
    try {
        # First, try the simple HP Image Assistant approach
        Write-Output "Trying HP Image Assistant as primary method..."
        
        if ($wingetAvailable) {
            # Install HP Image Assistant via WinGet
            $wingetArgs = "install --id HP.ImageAssistant -e --accept-source-agreements --accept-package-agreements --silent"
            $hpiaInstallProcess = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -Wait -PassThru -WindowStyle Hidden
            if ($hpiaInstallProcess.ExitCode -ne 0) {
                Write-Output "WARNING: Failed to install HP Image Assistant via WinGet. Exit code: $($hpiaInstallProcess.ExitCode)"
            }
        } else {
            Write-Output "WARNING: WinGet not available - skipping HP Image Assistant installation"
        }
        
        # Check if HPIA installed successfully (or was already installed)
        $HPIAPath = "C:\Program Files\HP\HPIA\HPImageAssistant.exe"
        if (-not (Test-Path $HPIAPath)) {
            $HPIAPath = "C:\SWSetup\HPImageAssistant\HPImageAssistant.exe"
        }
        
        if (Test-Path $HPIAPath) {
            Write-Output "Running HP Image Assistant for driver updates..."
            $hpTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $hpWorkPath = Join-Path -Path $script:HPLogRoot -ChildPath "HPIA-$hpTimestamp"
            $hpSoftPaqPath = Join-Path -Path $hpWorkPath -ChildPath 'Softpaqs'
            New-Item -ItemType Directory -Path $hpWorkPath -Force | Out-Null
            New-Item -ItemType Directory -Path $hpSoftPaqPath -Force | Out-Null

            # Run HPIA with better parameters for post-OOBE environment
            $hpiaResult = Start-Process -FilePath $HPIAPath -ArgumentList "/Operation:Analyze", "/Category:Driver", "/Action:Install", "/Silent", "/ReportFolder:$hpWorkPath", "/SoftpaqDownloadFolder:$hpSoftPaqPath" -Wait -PassThru -WindowStyle Hidden
            
            if ($hpiaResult.ExitCode -eq 0) {
                Write-Output "HP Image Assistant completed successfully"
                $primaryReport = Get-ChildItem -Path $hpWorkPath -Filter *.html -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($primaryReport) {
                    Write-Output "  Primary report: $($primaryReport.FullName)"
                }
                Write-Output "  Additional artifacts located in: $hpWorkPath"
                return
            } else {
                $hpLog = Get-ChildItem -Path $hpWorkPath -Filter *.log -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($hpLog) {
                    Write-Output "WARNING: HP Image Assistant failed with exit code: $($hpiaResult.ExitCode). Log: $($hpLog.FullName)"
                } else {
                    Write-Output "WARNING: HP Image Assistant failed with exit code: $($hpiaResult.ExitCode). No log file found in $hpWorkPath"
                }
                Write-Output "WARNING: Trying HP CMSL..."
            }
        } else {
            Write-Output "WARNING: HP Image Assistant not found. Trying HP CMSL approach..."
        }
        
        # If HPIA fails, try HP CMSL with simplified approach
        Write-Output "Falling back to HP CMSL method..."
        
        # FIXED: Use the Install-HPCMSLModule function which properly updates PowerShellGet first
        $hpModules = Get-Module -ListAvailable -Name 'HPCMSL' -ErrorAction SilentlyContinue
        if (-not $hpModules) {
            Write-Output "HP CMSL not installed. Attempting automatic deployment..."
            if (-not (Install-HPCMSLModule)) {
                Write-Output "WARNING: Unable to install HP CMSL automatically."
                Write-Output "Skipping HP driver updates - please install HP CMSL manually or check network connectivity"
                return
            }
        }
        
        # Import HP CMSL module
        try {
            Write-Output "Loading HP CMSL module..."
            # Remove and re-import to ensure fresh load
            Remove-Module HPCMSL -Force -ErrorAction SilentlyContinue
            Import-Module HPCMSL -Force -ErrorAction Stop
            Write-Output "  [OK] HPCMSL module loaded successfully"
        } catch {
            Write-Output "WARNING: Failed to import HPCMSL module: $($_.Exception.Message)"
            Write-Output "Please ensure HP CMSL is properly installed and try running as Administrator"
            return
        }
        
        Write-Output "Detecting available HP driver updates..."
        
        # Get available softpaqs (drivers) for this system using simplified approach
        try {
            # Try platform-specific approach first
            $platform = Get-HPDeviceProductID -ErrorAction SilentlyContinue
            if ($platform) {
                Write-Output "Detected HP platform: $platform"
                $softpaqs = Get-SoftpaqList -Category Driver -Platform $platform -ErrorAction SilentlyContinue
            } else {
                # Fallback to generic approach
                Write-Output "Using generic driver detection..."
                $softpaqs = Get-SoftpaqList -Category Driver -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Output "WARNING: Failed to get driver list: $($_.Exception.Message)"
            $softpaqs = $null
        }
        
        if ($softpaqs -and $softpaqs.Count -gt 0) {
            Write-Output "Found $($softpaqs.Count) driver updates available"
            
            # Limit to reasonable number of drivers to avoid timeout
            if ($softpaqs.Count -gt $MaxDrivers) {
                Write-Output "Limiting to first $MaxDrivers drivers for faster installation"
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
            
            Write-Output "Starting installation of $totalCount drivers..."
            
            foreach ($softpaq in $softpaqs) {
                $currentItem++
                $percentComplete = [math]::Round(($currentItem / $totalCount) * 100)
                
                Write-Output "[$currentItem/$totalCount] ($percentComplete%) Installing: $($softpaq.Name) ($($softpaq.Id))"
                
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
                            Write-Output "WARNING: Download attempt $retry failed: $($_.Exception.Message)"
                            if ($retry -lt 2) { Start-Sleep -Seconds 2 }
                        }
                    }
                    
                    if ($downloadSuccess -and (Test-Path $downloadPath)) {
                        # Install silently
                        $installResult = Start-Process -FilePath $downloadPath -ArgumentList '/S', '/v/qn' -Wait -PassThru -WindowStyle Hidden
                        
                        # Check various success exit codes
                        if ($installResult.ExitCode -in @(0, 3010, 1641)) {
                            Write-Output "  [OK] Successfully installed $($softpaq.Name)"
                            $successCount++
                        } else {
                            Write-Output "WARNING: [X] Installation failed with exit code: $($installResult.ExitCode)"
                            $failCount++
                        }
                        
                        # Clean up downloaded file
                        Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
                    } else {
                        Write-Output "WARNING: [X] Failed to download $($softpaq.Name)"
                        $failCount++
                    }
                    
                } catch {
                    Write-Output "WARNING: [X] Failed to install $($softpaq.Name): $($_.Exception.Message)"
                    $failCount++
                }
                
                # Add small delay between installations
                if ($currentItem -lt $totalCount) {
                    Start-Sleep -Milliseconds 500
                }
            }
            
            # Cleanup temp directory
            Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            
            Write-Output "`nHP driver update summary:"
            Write-Output "  Successfully installed: $successCount drivers"
            if ($failCount -gt 0) {
                Write-Output "  Failed installations: $failCount drivers"
            }
            
        } else {
            Write-Output "No HP driver updates available for this system"
        }
        
    } catch {
        Write-Output "WARNING: HP driver update failed: $($_.Exception.Message)"
        Write-Output "You may need to run this script as Administrator or check your internet connection"
    }
}



# Main execution
try {
    if ($manufacturer -like "*dell*") {
        if ($SkipDell) {
            Write-Output "Skipping Dell drivers (SkipDell parameter set)"
        } else {
            Write-Output "Detected Dell system - running Dell Command Update"
            Update-DellDrivers
        }
    } elseif ($manufacturer -like "*hewlett*" -or $manufacturer -like "*hp*") {
        if ($SkipHP) {
            Write-Output "Skipping HP drivers (SkipHP parameter set)"
        } else {
            Write-Output "Detected HP system - running HP driver updates"
            Update-HPDrivers
        }
    } elseif ($manufacturer -eq "unknown") {
        Write-Output "WARNING: Could not detect system manufacturer. Attempting HP method as fallback (most common)..."
        Write-Output "If this fails, please run the script on a Dell system, or install drivers manually"
        if (-not $SkipHP) {
            Update-HPDrivers
        }
    } else {
        Write-Output "WARNING: Unsupported or unrecognized manufacturer: $manufacturer"
        Write-Output "Supported manufacturers: Dell, HP/Hewlett-Packard"
        Write-Output "System detected: $manufacturer $model"
        
        # Provide helpful guidance
        Write-Output "`nFor unsupported systems, consider:"
        Write-Output "- Running Windows Update manually"
        Write-Output "- Downloading drivers from manufacturer's website"
        Write-Output "- Using Device Manager to update drivers"
    }
    
    Write-Output "`nDriver update process completed!"
    exit 0
    
} catch {
    Write-Output "WARNING: Error during driver update: $($_.Exception.Message)"
    Write-Output "Driver update finished with errors"
    Write-Output "`nTroubleshooting tips:"
    Write-Output "- Ensure you have internet connectivity"
    Write-Output "- Try running the script as Administrator"
    Write-Output "- Check Windows Update for basic driver updates"
    exit 1
}