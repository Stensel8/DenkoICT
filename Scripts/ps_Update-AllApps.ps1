<#
.SYNOPSIS
    Updates all applications via WinGet.

.DESCRIPTION
    Checks for and installs available updates for applications managed by WinGet.

.PARAMETER ExcludeApps
    Array of application IDs to exclude from updates.

.PARAMETER ShowOnly
    Only shows available updates without installing them.

.PARAMETER SkipLogging
    Skip transcript logging for quick execution.

.EXAMPLE
    .\ps_Update-AllApps.ps1
    Updates all applications.

.EXAMPLE
    .\ps_Update-AllApps.ps1 -ShowOnly
    Shows available updates without installing.

.EXAMPLE
    .\ps_Update-AllApps.ps1 -ExcludeApps @("Mozilla.Firefox", "Google.Chrome")
    Updates all except Firefox and Chrome.

.RELEASENOTES
[Version 1.0.0] - Initial Release. Updates all apps via WinGet.
[Version 2.0.0] - Improved script using best practises and advanced features such as cmdletbinding.


.NOTES
    Author:   Sten Tijhuis
    Company:  Denko ICT
    Requires: WinGet, Admin rights
#>

#requires -Version 5.1

[CmdletBinding()]
param(
    [string[]]$ExcludeApps = @(),
    [switch]$ShowOnly,
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
    Start-Logging -LogName 'Update-AllApps.log'
}

try {
    Assert-AdminRights
    
    # Check WinGet availability
    Write-Log "Checking WinGet availability..." -Level Info
    try {
        $wingetVersion = winget --version 2>$null
        if (-not $wingetVersion) {
            throw "WinGet not found"
        }
        Write-Log "WinGet version: $wingetVersion" -Level Info
    } catch {
        Write-Log "WinGet is not installed or not in PATH" -Level Error
        exit 1
    }
    
    # Get available updates
    Write-Log "Checking for available updates..." -Level Info
    $upgradeOutput = winget upgrade --include-unknown 2>&1
    
    # Parse output for updates
    $updates = @()
    $parsing = $false
    
    foreach ($line in $upgradeOutput) {
        # Start parsing after the header line
        if ($line -match '^-+\s+-+') {
            $parsing = $true
            continue
        }
        
        if (-not $parsing) { continue }
        if ($line -match '^\d+ upgrades? available') { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        # Parse update line (Name, Id, Current Version, Available Version)
        $parts = $line -split '\s{2,}'
        if ($parts.Count -ge 4) {
            $id = $parts[1].Trim()
            
            # Skip if in exclude list
            if ($id -in $ExcludeApps) {
                Write-Log "Skipping excluded app: $id" -Level Info
                continue
            }
            
            $updates += [PSCustomObject]@{
                Name = $parts[0].Trim()
                Id = $id
                CurrentVersion = $parts[2].Trim()
                AvailableVersion = $parts[3].Trim()
            }
        }
    }
    
    if ($updates.Count -eq 0) {
        Write-Log "No updates available" -Level Success
        Set-IntuneSuccess -AppName 'AppUpdates' -Version (Get-Date -Format 'yyyy.MM.dd')
        exit 0
    }
    
    Write-Log "Found $($updates.Count) available updates:" -Level Info
    foreach ($update in $updates) {
        Write-Log "  $($update.Name): $($update.CurrentVersion) → $($update.AvailableVersion)" -Level Info
    }
    
    if ($ShowOnly) {
        Write-Log "ShowOnly mode - skipping installation" -Level Warning
        exit 0
    }
    
    # Install updates
    Write-Log "Starting updates..." -Level Info
    $success = 0
    $failed = 0
    
    foreach ($update in $updates) {
        Write-Log "Updating $($update.Name)..." -Level Info
        
        $result = Invoke-WithRetry -ScriptBlock {
            $proc = Start-Process winget -ArgumentList @(
                'upgrade',
                '--id', $update.Id,
                '--silent',
                '--accept-package-agreements',
                '--accept-source-agreements'
            ) -Wait -PassThru -NoNewWindow
            
            if ($proc.ExitCode -ne 0) {
                throw "Exit code: $($proc.ExitCode)"
            }
        } -MaxAttempts 2 -DelaySeconds 3
        
        if ($null -eq $result -or $result -eq $true) {
            Write-Log "  ✓ Updated successfully" -Level Success
            $success++
        } else {
            Write-Log "  ✗ Update failed" -Level Error
            $failed++
        }
    }
    
    # Summary
    Write-Log "Update complete: $success succeeded, $failed failed" -Level $(if ($failed -eq 0) { 'Success' } else { 'Warning' })
    
    # Record Intune success if all updates succeeded
    if ($failed -eq 0) {
        Set-IntuneSuccess -AppName 'AppUpdates' -Version (Get-Date -Format 'yyyy.MM.dd')
    }
    
    exit $(if ($failed -gt 0) { 1 } else { 0 })
    
} catch {
    Write-Log "Update process failed: $_" -Level Error
    exit 1
} finally {
    if (-not $SkipLogging) {
        Stop-Logging
    }
}