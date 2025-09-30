<#
.SYNOPSIS
    Installs applications via WinGet.

.DESCRIPTION
    Installs applications using WinGet package manager.

.PARAMETER Applications
    Array of WinGet application IDs to install.

.PARAMETER Force
    Force reinstall even if already installed.

.PARAMETER SkipLogging
    Skip transcript logging.

.EXAMPLE
    .\ps_Install-Applications.ps1
    Installs default applications.

.EXAMPLE
    .\ps_Install-Applications.ps1 -Applications @("7zip.7zip")
    Installs only 7zip.

.RELEASENOTES
 [Version 1.0.0] - Initial release
 [Version 1.1.0] - Added PowerShell 7 installation and improved logging
 [Version 2.0.0] - Added WinGet support and enhanced error handling
 [Version 2.1.0] - Improved the handling of Teams installation
 [Version 2.1.1] - Bugfix: Fixed installation not executing (Start-Process issue) + improved logging with output capture
 [Version 2.1.2] - Improved logging and exit code handling for WinGet installations
 [Version 2.1.3] - Added refresh of environment PATH after winget installation to ensure winget is available in the current session.
 [Version 2.2.0] - Simplified installation flow

.NOTES
    Version:  2.2.0
    Author:   Sten Tijhuis
    Company:  Denko ICT
    Requires: Admin rights, WinGet
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

# WinGet exit codes mapping
$script:WinGetExitCodes = @{
    0 = "Success"
    -1978335231 = "Internal Error"
    -1978335230 = "Invalid command line arguments"
    -1978335229 = "Executing command failed"
    -1978335226 = "Running ShellExecute failed (installer failed)"
    -1978335224 = "Downloading installer failed"
    -1978335216 = "No applicable installer for the current system"
    -1978335215 = "Installer hash mismatch"
    -1978335212 = "No packages found"
    -1978335210 = "Multiple packages found"
    -1978335207 = "Command requires administrator privileges"
    -1978335189 = "No applicable update found (already up-to-date)"
    -1978335188 = "Upgrade all completed with failures"
    -1978335174 = "Operation blocked by Group Policy"
    -1978335135 = "Package already installed"
    -1978334975 = "Application currently running"
    -1978334974 = "Another installation in progress"
    -1978334973 = "File in use"
    -1978334972 = "Missing dependency"
    -1978334971 = "Disk full"
    -1978334970 = "Insufficient memory"
    -1978334969 = "No network connection"
    -1978334967 = "Reboot required to finish"
    -1978334966 = "Reboot required to install"
    -1978334964 = "Cancelled by user"
    -1978334963 = "Another version already installed"
    -1978334962 = "Downgrade attempt (higher version installed)"
    -1978334961 = "Blocked by policy"
    -1978334960 = "Failed to install dependencies"
}

function Get-WinGetExitCodeMessage {
    param([int]$ExitCode)
    
    if ($script:WinGetExitCodes.ContainsKey($ExitCode)) {
        return $script:WinGetExitCodes[$ExitCode]
    }
    return "Unknown exit code"
}

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
            
            # Clean and log output (strip progress bars)
            $cleanOutput = $output -replace '[\u2588\u2591\u258A-\u258F]', '' -replace '\s+', ' '
            if ($cleanOutput.Trim()) {
                Write-Log "  Output: $($cleanOutput.Trim())" -Level Info
            }
            Write-Log "  Exit Code: $exitCode" -Level Info
            
            # Interpret exit code
            $exitCodeMsg = Get-WinGetExitCodeMessage -ExitCode $exitCode
            
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