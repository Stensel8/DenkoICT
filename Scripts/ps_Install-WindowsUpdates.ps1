<#PSScriptInfo

.VERSION 1.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Updates WindowsUpdate PSWindowsUpdate Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Installs Windows Updates using PSWindowsUpdate module.
#>

#requires -Version 5.1

<#
.SYNOPSIS
    Downloads and installs Windows Updates on the system.

.DESCRIPTION
    This script uses the PSWindowsUpdate module to check for, download, and install
    available Windows Updates. It handles module installation, update detection,
    and installation with proper logging and error handling.

    Features:
    - Automatic PSWindowsUpdate module installation
    - Optional reboot control
    - Category filtering (Security, Critical, etc.)
    - Detailed logging of all operations
    - Integration with Intune deployment tracking

.PARAMETER Categories
    Array of update categories to install. 
    Default: @("Security", "Critical", "Updates")
    Options: Security, Critical, Updates, Drivers, FeaturePacks, ServicePacks

.PARAMETER AutoReboot
    Automatically reboot if required after installing updates.

.PARAMETER ScheduleReboot
    Schedule a reboot instead of immediate restart (requires -AutoReboot).

.PARAMETER ScheduleTime
    Time to schedule the reboot (format: "HH:mm"). Default: "03:00"

.PARAMETER IgnoreReboot
    Install updates even if a reboot is pending from previous updates.

.PARAMETER SkipLogging
    Skip transcript logging.

.EXAMPLE
    .\ps_Install-WindowsUpdates.ps1
    Installs Security, Critical, and regular Updates without auto-reboot.

.EXAMPLE
    .\ps_Install-WindowsUpdates.ps1 -AutoReboot
    Installs updates and automatically reboots if needed.

.EXAMPLE
    .\ps_Install-WindowsUpdates.ps1 -Categories @("Security", "Critical") -AutoReboot
    Installs only Security and Critical updates with auto-reboot.

.EXAMPLE
    .\ps_Install-WindowsUpdates.ps1 -ScheduleReboot -ScheduleTime "02:00"
    Installs updates and schedules reboot for 2:00 AM.

.NOTES
    Version      : 1.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : Admin rights, Internet connection
    Module       : PSWindowsUpdate (auto-installed from PSGallery)

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
    PSWindowsUpdate: https://www.powershellgallery.com/packages/PSWindowsUpdate
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Security", "Critical", "Updates", "Drivers", "FeaturePacks", "ServicePacks")]
    [string[]]$Categories = @("Security", "Critical", "Updates"),
    
    [switch]$AutoReboot,
    [switch]$ScheduleReboot,
    
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d{2}:\d{2}$')]
    [string]$ScheduleTime = "03:00",
    
    [switch]$IgnoreReboot,
    [switch]$SkipLogging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Load custom functions
$functionsPath = Join-Path $PSScriptRoot 'ps_Custom-Functions.ps1'
if (-not (Test-Path $functionsPath)) {
    Write-Error "Required functions file not found: $functionsPath"
    exit 1
}
. $functionsPath

# Initialize
if (-not $SkipLogging) {
    Start-Logging -LogName 'Install-WindowsUpdates.log'
}

try {
    Assert-AdminRights
    
    Write-Log "=== Windows Update Installation Started ===" -Level Info
    Write-Log "Categories: $($Categories -join ', ')" -Level Info
    Write-Log "Auto Reboot: $AutoReboot" -Level Info
    
    # ============================================================================ #
    # Install PSWindowsUpdate Module
    # ============================================================================ #
    
    Write-Log "Checking for PSWindowsUpdate module..." -Level Info
    
    $module = Get-Module -ListAvailable -Name PSWindowsUpdate | 
              Sort-Object Version -Descending | 
              Select-Object -First 1
    
    if (-not $module) {
        Write-Log "PSWindowsUpdate module not found, installing..." -Level Info
        
        # Ensure NuGet provider is installed
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nuget) {
            Write-Log "Installing NuGet package provider..." -Level Info
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
        }
        
        # Trust PSGallery temporarily
        $psGalleryTrust = (Get-PSRepository -Name PSGallery).InstallationPolicy
        if ($psGalleryTrust -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        
        try {
            Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -AllowClobber
            Write-Log "PSWindowsUpdate module installed successfully" -Level Success
        } catch {
            Write-Log "Failed to install PSWindowsUpdate: $_" -Level Error
            throw
        } finally {
            # Restore PSGallery trust setting
            if ($psGalleryTrust -ne 'Trusted') {
                Set-PSRepository -Name PSGallery -InstallationPolicy $psGalleryTrust
            }
        }
    } else {
        Write-Log "PSWindowsUpdate module already installed (v$($module.Version))" -Level Info
    }
    
    # Import module
    Import-Module PSWindowsUpdate -Force
    Write-Log "PSWindowsUpdate module imported" -Level Info
    
    # ============================================================================ #
    # Check for pending reboot
    # ============================================================================ #
    
    if (-not $IgnoreReboot) {
        Write-Log "Checking for pending reboot..." -Level Info
        
        $rebootPending = $false
        
        # Check CBS/DISM pending
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
            $rebootPending = $true
        }
        
        # Check Windows Update pending
        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
            $rebootPending = $true
        }
        
        # Check PendingFileRenameOperations
        $pendingFileRename = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($pendingFileRename) {
            $rebootPending = $true
        }
        
        if ($rebootPending) {
            Write-Log "Reboot is pending from previous operations" -Level Warning
            Write-Log "Consider rebooting before installing new updates, or use -IgnoreReboot to proceed anyway" -Level Warning
        }
    }
    
    # ============================================================================ #
    # Check for available updates
    # ============================================================================ #
    
    Write-Log "Scanning for available updates..." -Level Info
    
    $getUpdatesParams = @{
        Category = $Categories
        Verbose = $false
    }
    
    $updates = Get-WindowsUpdate @getUpdatesParams
    
    if (-not $updates -or $updates.Count -eq 0) {
        Write-Log "No updates available in specified categories" -Level Success
        Set-IntuneSuccess -AppName 'WindowsUpdates' -Version (Get-Date -Format 'yyyy.MM.dd')
        exit 0
    }
    
    Write-Log "Found $($updates.Count) available updates:" -Level Info
    foreach ($update in $updates) {
        $sizeInMB = [math]::Round($update.Size / 1MB, 2)
        Write-Log "  - $($update.Title) ($sizeInMB MB)" -Level Info
    }
    
    # ============================================================================ #
    # Install updates
    # ============================================================================ #
    
    Write-Log "Installing updates..." -Level Info
    
    $installParams = @{
        Category = $Categories
        AcceptAll = $true
        IgnoreReboot = $true
        Verbose = $false
    }
    
    try {
        $result = Install-WindowsUpdate @installParams
        
        if ($result) {
            $installedCount = ($result | Where-Object { $_.Result -eq 'Installed' }).Count
            $failedCount = ($result | Where-Object { $_.Result -eq 'Failed' }).Count
            
            Write-Log "Installation complete: $installedCount installed, $failedCount failed" -Level Success
            
            # Log individual results
            foreach ($update in $result) {
                $level = if ($update.Result -eq 'Installed') { 'Success' } else { 'Error' }
                Write-Log "  $($update.Result): $($update.Title)" -Level $level
            }
            
            # Check if reboot is required
            $rebootRequired = ($result | Where-Object { $_.RebootRequired -eq $true }).Count -gt 0
            
            if ($rebootRequired) {
                Write-Log "System reboot is required to complete installation" -Level Warning
                
                if ($AutoReboot) {
                    if ($ScheduleReboot) {
                        Write-Log "Scheduling reboot for $ScheduleTime..." -Level Info
                        
                        $scheduledTime = [DateTime]::ParseExact($ScheduleTime, "HH:mm", $null)
                        $now = Get-Date
                        
                        # If scheduled time is in the past today, schedule for tomorrow
                        if ($scheduledTime -lt $now) {
                            $scheduledTime = $scheduledTime.AddDays(1)
                        }
                        
                        $secondsUntilReboot = ($scheduledTime - $now).TotalSeconds
                        
                        shutdown.exe /r /t $secondsUntilReboot /c "Windows Updates installed - reboot scheduled" /d p:2:17
                        Write-Log "Reboot scheduled for $($scheduledTime.ToString('yyyy-MM-dd HH:mm'))" -Level Success
                    } else {
                        Write-Log "Initiating automatic reboot in 60 seconds..." -Level Warning
                        shutdown.exe /r /t 60 /c "Windows Updates installed - automatic reboot" /d p:2:17
                    }
                } else {
                    Write-Log "Please reboot the system manually to complete update installation" -Level Warning
                }
            }
            
            # Record success if no failures
            if ($failedCount -eq 0) {
                Set-IntuneSuccess -AppName 'WindowsUpdates' -Version (Get-Date -Format 'yyyy.MM.dd')
            }
            
        } else {
            Write-Log "No updates were installed" -Level Warning
        }
        
    } catch {
        Write-Log "Update installation failed: $_" -Level Error
        throw
    }
    
    Write-Log "=== Windows Update Installation Complete ===" -Level Success
    
    exit 0
    
} catch {
    Write-Log "Windows Update process failed: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
} finally {
    if (-not $SkipLogging) {
        Stop-Logging
    }
}