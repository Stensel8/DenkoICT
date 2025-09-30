<#
.SYNOPSIS
    Installs applications via WinGet or custom installers.

.DESCRIPTION
    Installs applications using WinGet package manager or custom installers like Teams.
    Supports PowerShell 7 for system context installations.

.PARAMETER Applications
    Array of WinGet application IDs to install.

.PARAMETER SkipTeams
    Skip Microsoft Teams installation.

.PARAMETER TeamsBootstrapperPath
    Path to teamsbootstrapper.exe (default: script directory).

.PARAMETER TeamsMSIXPath
    Path to MSTeams-x64.msix (default: script directory).

.PARAMETER InstallPowerShell7
    Install PowerShell 7 before other applications.

.PARAMETER PowerShell7Path
    Path to PowerShell 7 MSI installer.

.PARAMETER UsePowerShell7
    Use PowerShell 7 for WinGet installations (better for system context).

.PARAMETER Force
    Force reinstall even if already installed.

.PARAMETER SkipLogging
    Skip transcript logging.

.EXAMPLE
    .\ps_Install-Applications.ps1
    Installs default applications including Microsoft Teams.

.EXAMPLE
    .\ps_Install-Applications.ps1 -SkipTeams
    Installs default applications but skips Microsoft Teams.

.EXAMPLE
    .\ps_Install-Applications.ps1 -Applications @("7zip.7zip") -InstallPowerShell7
    Installs 7zip, PowerShell 7, and Microsoft Teams.

.RELEASENOTES
    1.0.0 Initial release
    1.1.0 Added PowerShell 7 installation and improved logging
    2.0.0 Added WinGet support and enhanced error handling
    2.1.0 Improved the handling of Teams installation
    2.1.1 Bugfix: Fixed installation not executing (Start-Process issue) + improved logging with output capture
    2.1.2 Improved logging and exit code handling for WinGet installations

.NOTES
    Version:  2.1.2
    Author:   Sten Tijhuis
    Company:  Denko ICT
    Requires: Admin rights, WinGet
#>

[CmdletBinding()]
param(
    [string[]]$Applications = @(
        "Microsoft.VCRedist.2015+.x64",
        "Microsoft.Office",
        "Microsoft.Teams",
        "Microsoft.OneDrive",
        "7zip.7zip"
    ),
    
    [switch]$InstallPowerShell7,
    [string]$PowerShell7Path,
    
    [switch]$UsePowerShell7,
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
    # Install errors
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
    
    # Install PowerShell 7 if requested
    if ($InstallPowerShell7) {
        Write-Log "Installing PowerShell 7..." -Level Info
        
        if (-not $PowerShell7Path) {
            # Auto-detect PS7 MSI in script directory
            $pattern = if ($isARM64) { "PowerShell-7.*-win-arm64.msi" } else { "PowerShell-7.*-win-x64.msi" }
            $PowerShell7Path = Get-ChildItem -Path $PSScriptRoot -Filter $pattern -ErrorAction SilentlyContinue | 
                              Select-Object -First 1 -ExpandProperty FullName
        }
        
        if ($PowerShell7Path -and (Test-Path $PowerShell7Path)) {
            $msiArgs = @(
                "/i", "`"$PowerShell7Path`""
                "/qn"
                "ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1"
                "ENABLE_PSREMOTING=1"
                "ADD_PATH=1"
            )
            
            $result = Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
            
            if ($result.ExitCode -in @(0, 3010, 1641)) {
                Write-Log "PowerShell 7 installed successfully (exit: $($result.ExitCode))" -Level Success
                
                # Install WinGet module for PS7
                if ($UsePowerShell7) {
                    Write-Log "Installing Microsoft.WinGet.Client module for PowerShell 7..." -Level Info
                    $ps7Exe = "C:\Program Files\PowerShell\7\pwsh.exe"
                    if (Test-Path $ps7Exe) {
                        try {
                            $moduleOutput = & $ps7Exe -Command "Install-Module Microsoft.WinGet.Client -Force -Scope AllUsers -AcceptLicense" 2>&1
                            Write-Log "  Module installation output: $moduleOutput" -Level Info
                        } catch {
                            Write-Log "  Module installation warning: $_" -Level Warning
                        }
                    }
                }
            } else {
                Write-Log "PowerShell 7 installation failed (exit: $($result.ExitCode))" -Level Warning
            }
        } else {
            Write-Log "PowerShell 7 MSI not found at: $PowerShell7Path" -Level Warning
        }
    }
    
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
    
    foreach ($app in $Applications) {
        Write-Log "Installing $app..." -Level Info
        
        try {
            if ($UsePowerShell7 -and (Test-Path "C:\Program Files\PowerShell\7\pwsh.exe")) {
                # Use PowerShell 7 for better system context support
                Write-Log "  Using PowerShell 7 for installation..." -Level Info
                $output = & "C:\Program Files\PowerShell\7\pwsh.exe" -Command "Install-WinGetPackage -Id '$app' -Mode Silent" 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
                
                Write-Log "  PS7 Output: $($output.Trim())" -Level Info
                Write-Log "  PS7 Exit Code: $exitCode" -Level Info
                
                if ($exitCode -eq 0) {
                    Write-Log "  ✓ Installed via PowerShell 7" -Level Success
                    $success++
                } else {
                    Write-Log "  ✗ Failed via PowerShell 7" -Level Error
                    $failed++
                }
            } else {
                # Standard WinGet installation with proper output capture
                $wingetArgs = @(
                    "install"
                    "--id", $app
                    "--silent"
                    "--accept-package-agreements"
                    "--accept-source-agreements"
                )
                
                if ($Force) { $wingetArgs += "--force" }
                
                Write-Log "  Executing: winget $($wingetArgs -join ' ')" -Level Info
                $output = & winget $wingetArgs 2>&1 | Out-String
                $exitCode = $LASTEXITCODE
                
                # Clean and log output (strip progress bars)
                $cleanOutput = $output -replace '[\u2588\u2591\u258A-\u258F]', '' -replace '\s+', ' '
                Write-Log "  WinGet Output: $($cleanOutput.Trim())" -Level Info
                Write-Log "  WinGet Exit Code: $exitCode" -Level Info
                
                # Interpret exit code
                $exitCodeMsg = Get-WinGetExitCodeMessage -ExitCode $exitCode
                
                # Handle exit codes with appropriate logic
                if ($exitCode -eq 0) {
                    Write-Log "  ✓ Installed successfully" -Level Success
                    $success++
                } elseif ($exitCode -eq -1978335189) {
                    # No update available - this is fine
                    Write-Log "  ✓ Already installed and up-to-date" -Level Info
                    $success++
                } elseif ($exitCode -eq -1978335135) {
                    # Package already installed
                    Write-Log "  ✓ Package already installed" -Level Info
                    $success++
                } elseif ($exitCode -in @(-1978334967, -1978334966)) {
                    # Reboot required
                    Write-Log "  ⚠ Installed but reboot required: $exitCodeMsg" -Level Warning
                    $success++
                } elseif ($exitCode -in @(-1978334975, -1978334973)) {
                    # Application/file in use - treat as warning, may need retry
                    Write-Log "  ⚠ Cannot install: $exitCodeMsg - try closing the application" -Level Warning
                    $failed++
                } else {
                    Write-Log "  ✗ Failed: $exitCodeMsg (exit code: $exitCode)" -Level Warning
                    $failed++
                }
            }
        } catch {
            Write-Log "  ✗ Exception during installation: $_" -Level Error
            $failed++
        }
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
    Write-Log "Installation process failed with exception: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
} finally {
    if (-not $SkipLogging) {
        Stop-Logging
    }
}