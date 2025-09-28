<#PSScriptInfo

.VERSION 1.1.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows WinGet Updates PackageManager Maintenance

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.1.0] - Added WhatIf support, standardized logging, and administrator validation.
[Version 1.0.1] - Improved error handling and logging.
[Version 1.0.0] - Initial Release. Updates all applications via WinGet.
#>

<#
.SYNOPSIS
    Updates all installed applications using WinGet package manager.

.DESCRIPTION
    This script checks for available updates for all installed applications managed by WinGet
    and performs the updates automatically. It includes progress tracking, error handling,
    and detailed logging of the update process.

.PARAMETER ExcludeApps
    Array of application IDs to exclude from updates.

.PARAMETER LogPath
    Path for the update log file. Creates log in temp directory by default.

.PARAMETER ShowOnly
    Only shows available updates without installing them.

.EXAMPLE
    .\ps_Update-AllApps.ps1
    
    Updates all applications with available updates.

.EXAMPLE
    .\ps_Update-AllApps.ps1 -ShowOnly
    
    Shows available updates without installing them.

.EXAMPLE
    .\ps_Update-AllApps.ps1 -ExcludeApps @("Mozilla.Firefox", "Google.Chrome")
    
    Updates all applications except Firefox and Chrome.

.OUTPUTS
    Console output showing update progress and log file with detailed results.

.NOTES
    Version      : 1.0.1
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    
    Requires WinGet to be installed and configured.
    Updates are performed silently with automatic agreement acceptance.
    
    Exit codes:
    0 - All updates successful
    1 - Some or all updates failed

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeApps = @(),
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\DenkoICT-Updates-$(Get-Date -Format 'yyyyMMdd-HHmmss').log",
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$commonModule = Join-Path -Path $PSScriptRoot -ChildPath 'DenkoICT.Common.ps1'
if (-not (Test-Path -Path $commonModule)) {
    throw "Unable to locate shared helper module at $commonModule"
}

. $commonModule

Assert-AdminRights

# Function to write colored and logged output
function Write-ColorLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Highlight')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $LogPath -Value $logMessage -Force
    
    $logLevel = switch ($Level) {
        'Success' { 'Success' }
        'Warning' { 'Warning' }
        'Error'   { 'Error' }
        'Highlight' { 'Verbose' }
        default   { 'Info' }
    }

    Write-Log -Message $Message -Level $logLevel
}

# Function to check if WinGet is available
function Test-WinGetAvailable {
    try {
        $wingetVersion = winget --version
        if ($wingetVersion) {
            Write-ColorLog "WinGet version: $wingetVersion" -Level 'Info'
            return $true
        }
    } catch {
        Write-ColorLog "WinGet is not available: $_" -Level 'Error'
        return $false
    }
}

# Function to get available updates
function Get-WinGetUpdates {
    Write-ColorLog "Checking for available updates..." -Level 'Info'
    
    try {
        # Run winget upgrade to get list
        $upgradeOutput = winget upgrade --include-unknown 2>&1
        
        # Parse the output
        $updates = @()
        $startParsing = $false
        
        foreach ($line in $upgradeOutput) {
            if ($line -match "^-+\s+-+") {
                $startParsing = $true
                continue
            }
            
            if ($startParsing -and $line.Trim() -ne "" -and $line -notmatch "^\d+ upgrades available") {
                $parts = $line -split '\s{2,}'
                if ($parts.Count -ge 4) {
                    $update = [PSCustomObject]@{
                        Name = $parts[0].Trim()
                        Id = $parts[1].Trim()
                        CurrentVersion = $parts[2].Trim()
                        AvailableVersion = $parts[3].Trim()
                    }
                    
                    # Check if app is excluded
                    if ($ExcludeApps -notcontains $update.Id) {
                        $updates += $update
                    }
                }
            }
        }
        
        return $updates
        
    } catch {
        Write-ColorLog "Error checking for updates: $_" -Level 'Error'
        return @()
    }
}

# Function to perform updates
function Update-Applications {
    param(
        [array]$Updates
    )
    
    if ($Updates.Count -eq 0) {
        Write-ColorLog "No updates available." -Level 'Success'
        return 0
    }
    
    Write-ColorLog "Found $($Updates.Count) available updates:" -Level 'Highlight'
    Write-ColorLog "----------------------------------------" -Level 'Highlight'
    
    foreach ($update in $Updates) {
        Write-Host "$($update.Name) | $($update.CurrentVersion) → $($update.AvailableVersion)"
    }
    
    if ($ShowOnly) {
        Write-ColorLog "`nShowing updates only (ShowOnly mode enabled)" -Level 'Warning'
        return 0
    }
    
    Write-ColorLog "`nStarting updates..." -Level 'Info'
    
    $successCount = 0
    $failCount = 0
    $currentItem = 0
    
    foreach ($update in $Updates) {
        $currentItem++
        $percentComplete = [math]::Round(($currentItem / $Updates.Count) * 100)
        
        Write-ColorLog "[$currentItem/$($Updates.Count)] ($percentComplete%) Updating $($update.Name)..." -Level 'Highlight'
        
        try {
            # Run update
            $process = Start-Process -FilePath "winget" -ArgumentList @(
                "upgrade"
                "--id", $update.Id
                "--accept-source-agreements"
                "--accept-package-agreements"
                "--silent"
                "--force"
            ) -Wait -PassThru -NoNewWindow
            
            if ($process.ExitCode -eq 0) {
                Write-ColorLog "  ✓ Successfully updated $($update.Name)" -Level 'Success'
                $successCount++
            } else {
                Write-ColorLog "  ✗ Failed to update $($update.Name) (Exit code: $($process.ExitCode))" -Level 'Error'
                $failCount++
            }
            
        } catch {
            Write-ColorLog "  ✗ Exception updating $($update.Name): $_" -Level 'Error'
            $failCount++
        }
    }
    
    # Summary
    Write-ColorLog "`n=== Update Summary ===" -Level 'Highlight'
    Write-ColorLog "Total updates: $($Updates.Count)" -Level 'Info'
    Write-ColorLog "Successful: $successCount" -Level $(if ($successCount -gt 0) { 'Success' } else { 'Info' })
    Write-ColorLog "Failed: $failCount" -Level $(if ($failCount -gt 0) { 'Error' } else { 'Info' })
    
    return $(if ($failCount -gt 0) { 1 } else { 0 })
}

# Main execution

Write-ColorLog "=== WinGet Application Update Started ===" -Level 'Highlight'
Write-ColorLog "User: $env:USERNAME" -Level 'Info'
Write-ColorLog "Computer: $env:COMPUTERNAME" -Level 'Info'

if ($ExcludeApps.Count -gt 0) {
    Write-ColorLog "Excluded apps: $($ExcludeApps -join ', ')" -Level 'Warning'
}

# Check WinGet availability
if (-not (Test-WinGetAvailable)) {
    Write-ColorLog "WinGet is not installed. Please install WinGet first." -Level 'Error'
    exit 1
}

# Get available updates
$updates = Get-WinGetUpdates

# Determine whether to perform updates (respects -WhatIf)
$shouldApplyUpdates = $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Install available WinGet application updates')

if ($ShowOnly) {
    Write-ColorLog "ShowOnly mode enabled. Listing updates without installing." -Level 'Warning'
    if ($updates.Count -gt 0) {
        Write-ColorLog "Updates available:" -Level 'Highlight'
        $updates | ForEach-Object { Write-ColorLog "$($_.Name) | $($_.CurrentVersion) → $($_.AvailableVersion)" -Level 'Highlight' }
    }
    $exitCode = 0
} elseif (-not $shouldApplyUpdates) {
    Write-ColorLog "WhatIf: Skipping installation of WinGet updates." -Level 'Warning'
    $exitCode = 0
} else {
    $exitCode = Update-Applications -Updates $updates
}

Write-ColorLog "Log file saved to: $LogPath" -Level 'Info'
Write-ColorLog "`nExiting..." -Level 'Highlight'

Start-Sleep -Seconds 1

exit $exitCode