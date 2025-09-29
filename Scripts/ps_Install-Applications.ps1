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

.NOTES
    Version:  2.0.0
    Author:   Sten Tijhuis
    Company:  Denko ICT
    Requires: Admin rights, WinGet
#>

[CmdletBinding()]
param(
    [string[]]$Applications = @(
        "Microsoft.VCRedist.2015+.x64",
        "Microsoft.Office",
        "7zip.7zip"
    ),
    
    [switch]$SkipTeams,
    [string]$TeamsBootstrapperPath,
    [string]$TeamsMSIXPath,
    
    [switch]$InstallPowerShell7,
    [string]$PowerShell7Path,
    
    [switch]$UsePowerShell7,
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
                Write-Log "PowerShell 7 installed successfully" -Level Success
                
                # Install WinGet module for PS7
                if ($UsePowerShell7) {
                    Write-Log "Installing Microsoft.WinGet.Client module for PowerShell 7..." -Level Info
                    $ps7Exe = "C:\Program Files\PowerShell\7\pwsh.exe"
                    if (Test-Path $ps7Exe) {
                        & $ps7Exe -Command "Install-Module Microsoft.WinGet.Client -Force -Scope AllUsers -AcceptLicense" 2>$null
                    }
                }
            } else {
                Write-Log "PowerShell 7 installation failed (exit: $($result.ExitCode))" -Level Warning
            }
        } else {
            Write-Log "PowerShell 7 MSI not found" -Level Warning
        }
    }
    
    # Install Teams by default (unless skipped)
    if (-not $SkipTeams) {
        Write-Log "Installing Microsoft Teams..." -Level Info
        
        if (-not $TeamsBootstrapperPath) {
            $TeamsBootstrapperPath = Join-Path $PSScriptRoot "teamsbootstrapper.exe"
        }
        if (-not $TeamsMSIXPath) {
            $TeamsMSIXPath = Join-Path $PSScriptRoot "MSTeams-x64.msix"
        }
        
        if ((Test-Path $TeamsBootstrapperPath) -and (Test-Path $TeamsMSIXPath)) {
            $bootResult = Start-Process -FilePath $TeamsBootstrapperPath `
                         -ArgumentList "-p -o `"$TeamsMSIXPath`"" `
                         -Wait -PassThru -NoNewWindow
            
            if ($bootResult.ExitCode -eq 0) {
                Write-Log "Teams installed successfully" -Level Success
                
                # Check installation
                $teamsApp = Get-AppxPackage -AllUsers | Where-Object { $_.Name -eq "MSTeams" }
                if ($teamsApp) {
                    Write-Log "Teams version: $($teamsApp.Version)" -Level Info
                    
                    # Disable auto-start (optional)
                    $regPath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\MicrosoftTeams_8wekyb3d8bbwe\TeamsStartupTask"
                    Set-RegistryValue -Path $regPath -Name "State" -Value 2 -Type DWord
                    
                    Set-IntuneSuccess -AppName "MicrosoftTeams" -Version $teamsApp.Version
                }
            } else {
                Write-Log "Teams installation failed (exit: $($bootResult.ExitCode))" -Level Error
            }
        } else {
            Write-Log "Teams installer files not found" -Level Warning
            Write-Log "  Expected: $TeamsBootstrapperPath" -Level Warning
            Write-Log "  Expected: $TeamsMSIXPath" -Level Warning
        }
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
        Write-Log "WinGet not installed - skipping WinGet applications" -Level Error
        if (-not $InstallTeams -and -not $InstallPowerShell7) {
            exit 1
        }
        exit 0
    }
    
    # Adjust applications for ARM64
    if ($isARM64) {
        $Applications = $Applications | ForEach-Object {
            if ($_ -like "*x64*") { $_.Replace("x64", "arm64") } else { $_ }
        }
        Write-Log "Adjusted applications for ARM64" -Level Info
    }
    
    # Install WinGet applications
    $success = 0
    $failed = 0
    
    foreach ($app in $Applications) {
        Write-Log "Installing $app..." -Level Info
        
        if ($UsePowerShell7 -and (Test-Path "C:\Program Files\PowerShell\7\pwsh.exe")) {
            # Use PowerShell 7 for better system context support
            $ps7Result = Start-Process "C:\Program Files\PowerShell\7\pwsh.exe" `
                        -ArgumentList "-Command", "Install-WinGetPackage -Id '$app' -Mode Silent" `
                        -Wait -PassThru -NoNewWindow
            
            if ($ps7Result.ExitCode -eq 0) {
                Write-Log "  ✓ Installed via PowerShell 7" -Level Success
                $success++
            } else {
                Write-Log "  ✗ Failed (PS7 exit: $($ps7Result.ExitCode))" -Level Error
                $failed++
            }
        } else {
            # Standard WinGet installation
            $wingetArgs = @(
                "install",
                "--id", $app,
                "--silent",
                "--accept-package-agreements",
                "--accept-source-agreements"
            )
            
            if ($Force) { $wingetArgs += "--force" }
            
            $result = Start-Process winget -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
                
                # Handle exit codes
                if ($result.ExitCode -eq 0) {
                    Write-Log "  ✓ Installed successfully" -Level Success
                    $success++
                } elseif ($result.ExitCode -eq -1978335189) {
                    Write-Log "  ℹ Already installed" -Level Info
                    $success++
                } else {
                    Write-Log "  ✗ Failed (exit: $($result.ExitCode))" -Level Error
                    $failed++
                }
            }
    }
    
    # Summary
    Write-Log "Installation complete: $success succeeded, $failed failed" -Level $(if ($failed -eq 0) { 'Success' } else { 'Warning' })
    
    if ($failed -eq 0) {
        Set-IntuneSuccess -AppName 'ApplicationBundle' -Version (Get-Date -Format 'yyyy.MM.dd')
    }
    
    exit $(if ($failed -gt 0) { 1 } else { 0 })
    
} catch {
    Write-Log "Installation process failed: $_" -Level Error
    exit 1
} finally {
    if (-not $SkipLogging) {
        Stop-Logging
    }
}
