<#PSScriptInfo

.VERSION 2.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows WindowsUpdate PSWindowsUpdate

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Basic Windows Update installation.
[Version 2.0.0] - Major refactor: PSWindowsUpdate module support, better error handling, PowerShell 7 compatibility
#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs Windows Updates using PSWindowsUpdate module.

.DESCRIPTION
    Downloads and installs Windows Updates with proper error handling and compatibility for both PowerShell 5.1 and 7+.
    Logs are saved to C:\DenkoICT\Logs.

.PARAMETER Categories
    Update categories to install. Default: Security, Critical, Updates

.PARAMETER AutoReboot
    Automatically reboot if required after updates.

.PARAMETER MaxUpdates
    Maximum number of updates to install in one run. Default: 100

.PARAMETER IgnorePendingReboot
    Skip pending reboot check and proceed with updates anyway.

.EXAMPLE
    .\ps_Install-WindowsUpdates.ps1
    Installs all security, critical and regular updates.

.EXAMPLE
    .\ps_Install-WindowsUpdates.ps1 -AutoReboot -MaxUpdates 10
    Installs up to 10 updates with automatic reboot.

.EXAMPLE
    .\ps_Install-WindowsUpdates.ps1 -Categories Security,Critical -IgnorePendingReboot
    Installs only security and critical updates, ignoring pending reboot status.

.NOTES
    Version      : 2.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : PowerShell 5.1+, Admin rights
#>

[CmdletBinding()]
param(
    [ValidateSet("Security", "Critical", "Updates", "Drivers", "Optional")]
    [string[]]$Categories = @("Security", "Critical", "Updates"),
    
    [switch]$AutoReboot,
    
    [ValidateRange(1, 500)]
    [int]$MaxUpdates = 100,
    
    [switch]$IgnorePendingReboot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Setup logging
$LogDir = "C:\DenkoICT\Logs"
$LogFile = Join-Path $LogDir "ps_Install-WindowsUpdates.ps1.log"
$TranscriptFile = Join-Path $LogDir "ps_Install-WindowsUpdates.ps1.transcript"

if (!(Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path $TranscriptFile -Force | Out-Null

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Append to log file
    Add-Content -Path $LogFile -Value $logEntry -Force
    
    # Console output with colors
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Cyan' }
    }
    
    Write-Host $Message -ForegroundColor $color
}

# ============================================================================
# Module Installation
# ============================================================================

function Install-PSWindowsUpdateModule {
    Write-Log "Checking for PSWindowsUpdate module..." -Level Info
    
    $module = Get-Module -ListAvailable -Name PSWindowsUpdate | 
              Sort-Object Version -Descending | 
              Select-Object -First 1
    
    if ($module -and $module.Version -ge [Version]"2.2.0") {
        Write-Log "PSWindowsUpdate v$($module.Version) already installed" -Level Success
        return $true
    }
    
    Write-Log "Installing/updating PSWindowsUpdate module..." -Level Info
    
    try {
        # Ensure NuGet provider
        if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
            Write-Log "NuGet provider installed" -Level Success
        }
        
        # Trust PSGallery
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        
        # Install module (CurrentUser for PS7, AllUsers for PS5.1)
        $scope = if ($PSVersionTable.PSVersion.Major -ge 7) { 'CurrentUser' } else { 'AllUsers' }
        Install-Module -Name PSWindowsUpdate -Force -Scope $scope -AllowClobber
        
        Write-Log "PSWindowsUpdate module installed successfully" -Level Success
        return $true
        
    } catch {
        Write-Log "Failed to install PSWindowsUpdate: $_" -Level Error
        return $false
    } finally {
        # Restore PSGallery setting
        Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# Reboot Checking
# ============================================================================

function Test-PendingReboot {
    $rebootRequired = $false
    $reasons = @()
    
    # Check registry keys
    $regPaths = @(
        @{Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing"; Key = "RebootPending"; Reason = "Component Based Servicing"}
        @{Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"; Key = "RebootRequired"; Reason = "Windows Update"}
        @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"; Key = "PendingFileRenameOperations"; Reason = "Pending File Operations"}
    )
    
    foreach ($reg in $regPaths) {
        if (Test-Path "$($reg.Path)\$($reg.Key)" -ErrorAction SilentlyContinue) {
            $rebootRequired = $true
            $reasons += $reg.Reason
        } elseif ($reg.Key -eq "PendingFileRenameOperations") {
            $prop = Get-ItemProperty -Path $reg.Path -Name $reg.Key -ErrorAction SilentlyContinue
            if ($prop -and $prop.PendingFileRenameOperations) {
                $rebootRequired = $true
                $reasons += $reg.Reason
            }
        }
    }
    
    return @{
        Required = $rebootRequired
        Reasons = $reasons
    }
}

# ============================================================================
# Main Execution
# ============================================================================

try {
    Write-Log "========================================" -Level Info
    Write-Log "  WINDOWS UPDATE INSTALLATION" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "PowerShell: $($PSVersionTable.PSVersion)" -Level Info
    Write-Log "Categories: $($Categories -join ', ')" -Level Info
    Write-Log "Max Updates: $MaxUpdates" -Level Info
    Write-Log "Auto Reboot: $AutoReboot" -Level Info
    
    # Check pending reboot
    if (!$IgnorePendingReboot) {
        $rebootStatus = Test-PendingReboot
        if ($rebootStatus.Required) {
            Write-Log "REBOOT PENDING from: $($rebootStatus.Reasons -join ', ')" -Level Warning
            Write-Log "Consider rebooting first or use -IgnorePendingReboot" -Level Warning
            
            # Don't exit, just warn
        }
    }
    
    # Install module if needed
    if (!(Install-PSWindowsUpdateModule)) {
        throw "Failed to setup PSWindowsUpdate module"
    }
    
    # Import module
    Import-Module PSWindowsUpdate -Force
    Write-Log "Module imported successfully" -Level Success
    
    # Get available updates
    Write-Log "`nScanning for updates..." -Level Info
    
    try {
        # Build parameters for Get-WindowsUpdate
        $getParams = @{
            MicrosoftUpdate = $true
            IgnoreReboot = $true
        }
        
        # Add category filter if specified
        if ($Categories.Count -gt 0) {
            $getParams['Category'] = $Categories
        }
        
        $updates = @(Get-WindowsUpdate @getParams -ErrorAction Stop)
        
        if ($updates.Count -eq 0) {
            Write-Log "No updates available" -Level Success
            exit 0
        }
        
        Write-Log "Found $($updates.Count) updates:" -Level Info
        
        # Display update list
        $totalSizeMB = 0
        $displayCount = [Math]::Min($updates.Count, $MaxUpdates)
        for ($i = 0; $i -lt $displayCount; $i++) {
            $update = $updates[$i]
            $sizeMB = [Math]::Round($update.Size / 1MB, 2)
            $totalSizeMB += $sizeMB
            Write-Log "  • $($update.Title) [$sizeMB MB]" -Level Info
        }
        
        if ($updates.Count -gt $MaxUpdates) {
            Write-Log "  (Showing first $MaxUpdates of $($updates.Count) total updates)" -Level Warning
        }
        
        Write-Log "Total download size: $([Math]::Round($totalSizeMB, 2)) MB" -Level Info
        
    } catch {
        Write-Log "Failed to get updates: $_" -Level Error
        throw
    }
    
    # Install updates
    Write-Log "`nInstalling updates..." -Level Info
    
    try {
        # Build install parameters
        $installParams = @{
            MicrosoftUpdate = $true
            IgnoreReboot = $true
            AcceptAll = $true
            MaxSize = $MaxUpdates
        }
        
        if ($Categories.Count -gt 0) {
            $installParams['Category'] = $Categories
        }
        
        # Perform installation
        $installResults = Install-WindowsUpdate @installParams -ErrorAction Stop
        
        # Process results - handle both single result and array
        $results = @($installResults)
        
        $installed = @($results | Where-Object { $_.Result -eq 'Installed' })
        $failed = @($results | Where-Object { $_.Result -eq 'Failed' })
        $alreadyInstalled = @($results | Where-Object { $_.Result -eq 'NotNeeded' -or $_.Status -eq 'Installed' })
        
        Write-Log "`nInstallation Summary:" -Level Info
        Write-Log "  Installed: $($installed.Count)" -Level $(if ($installed.Count -gt 0) { 'Success' } else { 'Info' })
        Write-Log "  Already Installed: $($alreadyInstalled.Count)" -Level Info
        Write-Log "  Failed: $($failed.Count)" -Level $(if ($failed.Count -gt 0) { 'Error' } else { 'Info' })
        
        # Log failed updates
        if ($failed.Count -gt 0) {
            Write-Log "`nFailed updates:" -Level Error
            foreach ($fail in $failed) {
                Write-Log "  ✗ $($fail.Title)" -Level Error
            }
        }
        
        # Check if any results require reboot
        $rebootNeeded = $false
        foreach ($result in $results) {
            if ($result.RebootRequired -eq $true -or $result.RestartNeeded -eq $true) {
                $rebootNeeded = $true
                break
            }
        }
        
        if ($rebootNeeded) {
            Write-Log "`nREBOOT REQUIRED to complete installation" -Level Warning
            
            if ($AutoReboot) {
                Write-Log "Initiating automatic reboot in 60 seconds..." -Level Warning
                Write-Log "Run 'shutdown /a' to cancel" -Level Warning
                shutdown.exe /r /t 60 /c "Windows Updates completed - automatic reboot"
            } else {
                Write-Log "Please reboot manually to complete installation" -Level Warning
            }
        }
        
        # Set success code if we installed something
        if ($installed.Count -gt 0) {
            exit 0
        } elseif ($alreadyInstalled.Count -gt 0 -and $failed.Count -eq 0) {
            Write-Log "All applicable updates already installed" -Level Success
            exit 0
        } else {
            exit 1
        }
        
    } catch {
        Write-Log "Installation failed: $_" -Level Error
        Write-Log "Error details: $($_.Exception.Message)" -Level Error
        throw
    }
    
} catch {
    Write-Log "`n[CRITICAL ERROR] $_" -Level Error
    exit 1
    
} finally {
    Write-Log "`n========================================" -Level Info
    Write-Log "Log saved to: $LogFile" -Level Info
    Stop-Transcript | Out-Null
}