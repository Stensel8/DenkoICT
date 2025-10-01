<#PSScriptInfo

.VERSION 2.3.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows WinGet Applications Deployment Installation

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial release
[Version 1.1.0] - Added PowerShell 7 installation and improved logging
[Version 2.0.0] - Added WinGet support and enhanced error handling
[Version 2.1.0] - Improved the handling of Teams installation
[Version 2.1.1] - Bugfix: Fixed installation not executing (Start-Process issue) + improved logging with output capture
[Version 2.1.2] - Improved logging and exit code handling for WinGet installations
[Version 2.1.3] - Added refresh of environment PATH after winget installation
[Version 2.2.0] - Simplified installation flow
[Version 2.3.0] - Refactored to use centralized WinGet exit code descriptions from ps_Custom-Functions.ps1
#>

#requires -Version 5.1

<#
.SYNOPSIS
    Installs applications via WinGet package manager.

.DESCRIPTION
    Automates application installation using Windows Package Manager (WinGet).
    Supports ARM64 architecture detection, exit code interpretation, and detailed logging.

    Features:
    - Automatic architecture detection (x64/ARM64)
    - Intelligent exit code handling
    - Detailed installation logging with duration tracking
    - Force reinstall capability
    - Integration with Intune deployment tracking

.PARAMETER Applications
    Array of WinGet application IDs to install.
    Default: Microsoft.PowerShell, VCRedist, Office, Teams, OneDrive, 7zip

.PARAMETER Force
    Force reinstall applications even if already installed.

.PARAMETER SkipLogging
    Skip transcript logging to file.

.EXAMPLE
    .\ps_Install-Applications.ps1
    Installs default application bundle.

.EXAMPLE
    .\ps_Install-Applications.ps1 -Applications @("7zip.7zip", "Microsoft.PowerShell")
    Installs only specified applications.

.EXAMPLE
    .\ps_Install-Applications.ps1 -Force
    Reinstalls all default applications even if already installed.

.NOTES
    Version      : 2.3.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : Admin rights, WinGet installed

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

[CmdletBinding()]
param(
    [string[]]$Applications = @(
        "Microsoft.PowerShell",
        "Microsoft.VCRedist.2015+.x64",
        "Microsoft.Office",
        "Microsoft.Teams",
        "Microsoft.OneDrive",
        "7zip.7zip"
    ),
    
    [switch]$Force,
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
    Start-Logging -LogName 'Install-Applications.log'
}

try {
    Assert-AdminRights
    
    # Detect architecture
    $isARM64 = $env:PROCESSOR_ARCHITECTURE -eq "ARM64"
    Write-Log "System architecture: $env:PROCESSOR_ARCHITECTURE" -Level Info
    
    # Refresh environment PATH to ensure WinGet is available
    Write-Log "Refreshing environment PATH..." -Level Info
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
    
    # Check WinGet availability
    Write-Log "Checking WinGet availability..." -Level Info
    try {
        $wingetVersion = & winget --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet not available (exit: $LASTEXITCODE)"
        }
        Write-Log "WinGet version: $wingetVersion" -Level Info
    } catch {
        Write-Log "WinGet not installed - cannot proceed: $_" -Level Error
        exit 1
    }
    
    # Adjust applications for ARM64
    if ($isARM64) {
        $Applications = $Applications | ForEach-Object {
            if ($_ -like "*x64*") { $_.Replace("x64", "arm64") } else { $_ }
        }
        Write-Log "Adjusted applications for ARM64: $($Applications -join ', ')" -Level Info
    }
    
    # Install WinGet applications
    $success = 0
    $failed = 0
    
    Write-Log "Starting installation of $($Applications.Count) applications..." -Level Info
    
    foreach ($app in $Applications) {
        Write-Log "=== Processing: $app ===" -Level Info
        
        try {
            # Build winget arguments
            $wingetArgs = @(
                "install"
                "--id", $app
                "--silent"
                "--accept-package-agreements"
                "--accept-source-agreements"
            )
            
            if ($Force) { 
                $wingetArgs += "--force"
                Write-Log "  Force flag enabled" -Level Info
            }
            
            Write-Log "  Executing: winget $($wingetArgs -join ' ')" -Level Info
            
            # Execute winget and capture output
            $startTime = Get-Date
            Write-Log "  Installation started at: $($startTime.ToString('HH:mm:ss'))" -Level Info
            
            $output = & winget $wingetArgs 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
            
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            Write-Log "  Installation completed in $([math]::Round($duration, 1)) seconds" -Level Info
            
            # Extract meaningful output (skip progress bars)
            $meaningfulOutput = ($output -split "`n") | 
                Where-Object { $_ -match '\S' -and $_ -notmatch '^[\s█▆▇▊▋▌▍▎▏▐░▒▓■□▪▫▬%\d\-\\|/]+$' } | 
                Select-Object -Last 3
            
            if ($meaningfulOutput) {
                foreach ($line in $meaningfulOutput) {
                    Write-Log "  $($line.Trim())" -Level Info
                }
            }
            
            Write-Log "  Exit Code: $exitCode" -Level Info

            # Interpret exit code using centralized function
            $exitCodeMsg = Get-WinGetExitCodeDescription -ExitCode $exitCode
            
            # Handle exit codes
            if ($exitCode -eq 0) {
                Write-Log "  ✓ Installed successfully" -Level Success
                $success++
            } elseif ($exitCode -in @(-1978335189, -1978335135)) {
                Write-Log "  ✓ Already installed: $exitCodeMsg" -Level Info
                $success++
            } elseif ($exitCode -in @(-1978334967, -1978334966)) {
                Write-Log "  ⚠ Installed but reboot required: $exitCodeMsg" -Level Warning
                $success++
            } elseif ($exitCode -in @(-1978334975, -1978334973)) {
                Write-Log "  ⚠ Cannot install: $exitCodeMsg" -Level Warning
                $failed++
            } else {
                Write-Log "  ✗ Failed: $exitCodeMsg (exit code: $exitCode)" -Level Warning
                $failed++
            }
        } catch {
            Write-Log "  ✗ Exception during installation: $($_.Exception.Message)" -Level Error
            Write-Log "  Exception type: $($_.Exception.GetType().FullName)" -Level Error
            if ($_.ScriptStackTrace) {
                Write-Log "  Stack trace: $($_.ScriptStackTrace)" -Level Error
            }
            $failed++
        }
        
        Write-Log "" -Level Info  # Blank line for readability
    }
    
    # Summary
    Write-Log "======================================" -Level Info
    Write-Log "Installation Summary:" -Level Info
    Write-Log "  Total applications: $($Applications.Count)" -Level Info
    Write-Log "  Successfully installed: $success" -Level Info
    Write-Log "  Failed: $failed" -Level Info
    Write-Log "======================================" -Level Info
    
    $summaryLevel = if ($failed -eq 0) { 'Success' } else { 'Warning' }
    Write-Log "Installation complete: $success succeeded, $failed failed" -Level $summaryLevel
    
    if ($failed -eq 0) {
        Set-IntuneSuccess -AppName 'ApplicationBundle' -Version (Get-Date -Format 'yyyy.MM.dd')
    }
    
    exit $(if ($failed -gt 0) { 1 } else { 0 })
    
} catch {
    Write-Log "Installation process failed with exception: $($_.Exception.Message)" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
} finally {
    if (-not $SkipLogging) {
        Stop-Logging
    }
}