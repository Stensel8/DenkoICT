<#
.SYNOPSIS
    Install vendor driver update tools and run updates for Dell and HP systems.

.DESCRIPTION
    Detects system manufacturer and runs appropriate driver update tool:
    - Dell: Dell Command Update (DCU)
    - HP: HP Image Assistant (primary) or HP CMSL (fallback)

.PARAMETER SkipDell
    Skip Dell driver updates even if Dell system is detected.

.PARAMETER SkipHP
    Skip HP driver updates even if HP system is detected.

.PARAMETER MaxDrivers
    Maximum number of HP drivers to install (default: 10).

.PARAMETER SkipLogging
    Skip transcript logging.

.EXAMPLE
    .\ps_Install-Drivers.ps1
    Runs the appropriate driver update tool based on detected system manufacturer.

.RELEASENOTES
    1.0.0 Initial release
    1.1.0 Added HP support and improved logging
    2.0.0 Improved error handling, printing and logging

.NOTES
    Version:  2.0.0
    Author:   Sten Tijhuis
    Company:  Denko ICT
#>

[CmdletBinding()]
param(
    [switch]$SkipDell,
    [switch]$SkipHP,
    [int]$MaxDrivers = 10,
    [switch]$SkipLogging
)

#requires -Version 5.1
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
    Start-Logging -LogName 'Install-Drivers.log'
}

try {
    Assert-AdminRights
    
    Write-Log "Starting driver update process..." -Level Info
    
    # Get system info
    try {
        $systemInfo = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $manufacturer = $systemInfo.Manufacturer.ToLower()
        $model = $systemInfo.Model
        Write-Log "System: $manufacturer $model" -Level Info
    } catch {
        Write-Log "Failed to detect system manufacturer" -Level Error
        exit 1
    }
    
    # Check WinGet availability
    Write-Log "Checking WinGet availability..." -Level Info
    try {
        $wingetVersion = winget --version 2>$null
        if (-not $wingetVersion) {
            throw "WinGet not available"
        }
        Write-Log "WinGet version: $wingetVersion" -Level Info
    } catch {
        Write-Log "WinGet not installed - driver tools may not install" -Level Warning
    }
    
    # Dell drivers
    if ($manufacturer -like "*dell*") {
        if ($SkipDell) {
            Write-Log "Skipping Dell drivers (SkipDell parameter set)" -Level Info
        } else {
            Write-Log "Installing Dell Command Update..." -Level Info
            
            $installArgs = @(
                "install",
                "--id", "Dell.CommandUpdate",
                "--silent",
                "--accept-package-agreements",
                "--accept-source-agreements"
            )
            
            $result = Start-Process winget -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
            
            if ($result.ExitCode -in @(0, -1978335189)) {
                if ($result.ExitCode -eq -1978335189) {
                    Write-Log "Dell Command Update already installed" -Level Info
                } else {
                    Write-Log "Dell Command Update installed successfully" -Level Success
                }
                
                # Find DCU executable
                $dcuPaths = @(
                    "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe",
                    "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe"
                )
                
                $dcu = $dcuPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
                
                if ($dcu) {
                    Write-Log "Running Dell driver updates..." -Level Info
                    
                    # Scan for updates
                    $scanResult = Start-Process $dcu -ArgumentList "/scan", "-silent" -Wait -PassThru -NoNewWindow
                    
                    if ($scanResult.ExitCode -eq 0) {
                        # Apply updates
                        $applyResult = Start-Process $dcu -ArgumentList "/applyUpdates", "-reboot=disable", "-silent" -Wait -PassThru -NoNewWindow
                        
                        switch ($applyResult.ExitCode) {
                            0 { Write-Log "Dell updates completed successfully" -Level Success }
                            1 { Write-Log "Dell updates completed - reboot recommended" -Level Success }
                            500 { Write-Log "Dell system is up to date" -Level Info }
                            default { Write-Log "Dell updates may have failed (exit: $($applyResult.ExitCode))" -Level Warning }
                        }
                    } elseif ($scanResult.ExitCode -eq 500) {
                        Write-Log "Dell system is up to date - no updates available" -Level Info
                    } else {
                        Write-Log "Dell update scan failed (exit: $($scanResult.ExitCode))" -Level Warning
                    }
                } else {
                    Write-Log "Dell Command Update not found at expected path" -Level Warning
                }
            } else {
                Write-Log "Dell Command Update installation failed (exit: $($result.ExitCode))" -Level Error
            }
        }
    }
    # HP drivers
    elseif ($manufacturer -like "*hewlett*" -or $manufacturer -like "*hp*") {
        if ($SkipHP) {
            Write-Log "Skipping HP drivers (SkipHP parameter set)" -Level Info
        } else {
            # Check if HP IA already exists
            $hpiaPaths = @(
                "C:\Program Files\HP\HPIA\HPImageAssistant.exe",
                "C:\SWSetup\HPImageAssistant\HPImageAssistant.exe"
            )
            
            $hpia = $hpiaPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            
            if (-not $hpia) {
                Write-Log "Installing HP Image Assistant..." -Level Info
                
                $installArgs = @(
                    "install",
                    "--id", "HP.ImageAssistant",
                    "--silent",
                    "--accept-package-agreements",
                    "--accept-source-agreements"
                )
                
                $result = Start-Process winget -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
                
                if ($result.ExitCode -in @(0, -1978335189)) {
                    Write-Log "HP Image Assistant installed successfully" -Level Success
                } else {
                    Write-Log "HP Image Assistant installation failed (exit: $($result.ExitCode))" -Level Warning
                }
                
                # Re-check for HPIA after installation attempt
                $hpia = $hpiaPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            } else {
                Write-Log "HP Image Assistant already installed" -Level Info
            }
            
                if ($hpia) {
                Write-Log "Running HP Image Assistant..." -Level Info
                
                $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $workPath = Join-Path $env:TEMP "HPIA-$timestamp"
                New-Item -ItemType Directory -Path $workPath -Force | Out-Null
                
                $hpiaArgs = @(
                    "/Operation:Analyze",
                    "/Category:All",
                    "/Selection:All",
                    "/InstallType:All",
                    "/Action:Install",
                    "/Silent",
                    "/ReportFolder:$workPath"
                )
                
                $hpiaResult = Start-Process $hpia -ArgumentList $hpiaArgs -Wait -PassThru -NoNewWindow
                
                # Check if report was generated (success indicator)
                $report = Get-ChildItem -Path $workPath -Filter *.html -ErrorAction SilentlyContinue | Select-Object -First 1
                
                if ($report) {
                    Write-Log "HP Image Assistant completed - report generated" -Level Success
                    Write-Log "Report: $($report.FullName)" -Level Info
                    
                    if ($hpiaResult.ExitCode -ne 0) {
                        Write-Log "Note: Exit code $($hpiaResult.ExitCode) - may indicate warnings (e.g., unsupported OS version)" -Level Warning
                    }
                } else {
                    # No report means actual failure
                    switch ($hpiaResult.ExitCode) {
                        0 { Write-Log "HP Image Assistant completed successfully" -Level Success }
                        4097 { Write-Log "HP system may be up to date or OS version not fully supported" -Level Info }
                        default { Write-Log "HP Image Assistant failed (exit: $($hpiaResult.ExitCode))" -Level Warning }
                    }
                }
                
                # Cleanup
                Remove-Item -Path $workPath -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Write-Log "HP Image Assistant not found - unable to update drivers" -Level Error
            }
        }
    }
    else {
        Write-Log "Unsupported manufacturer: $manufacturer" -Level Warning
        Write-Log "Supported: Dell, HP" -Level Info
    }
    
    Write-Log "Driver update process completed" -Level Success
    exit 0
    
} catch {
    Write-Log "Driver update failed: $_" -Level Error
    exit 1
} finally {
    if (-not $SkipLogging) {
        Stop-Logging
    }
}