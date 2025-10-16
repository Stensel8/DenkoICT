<#PSScriptInfo

.VERSION 6.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows WinGet Installation Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 6.0.0] - Complete refactor: Moved all logic to Winget.psm1 module, simplified script to be human-readable

#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Ensures WinGet is installed and functional.

.DESCRIPTION
    Simple script that ensures Windows Package Manager (WinGet) is installed
    and working properly. All complex logic is handled by the Winget.psm1 module.

    This script will:
    - Check if WinGet is already working
    - Install WinGet if missing
    - Install dependencies (VCLibs, UI.Xaml, VCRedist)
    - Register and configure WinGet properly
    - Verify the installation succeeded

.EXAMPLE
    .\Install-Winget.ps1

.NOTES
    Version      : 6.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : Admin rights

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Bootstrap initialization using consolidated function
Import-Module (Join-Path $PSScriptRoot 'Utilities\ScriptBootstrap.psm1') -Force -Global
Initialize-DeploymentScript -LogName 'Install-Winget.log' -RequiredModules @('Logging','System','Winget') -RequireAdmin

# ============================================================================
# MAIN INSTALLATION
# ============================================================================

try {
    Write-Log "========================================" -Level Info
    Write-Log "  WinGet Installation Script v6.0.0" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "" -Level Info

    # Simple one-line installation using the Initialize-WinGet function
    $winget = Initialize-WinGet

    # Verify success
    Write-Log "" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "Installation Complete!" -Level Success
    Write-Log "  WinGet Path: $($winget.Path)" -Level Info
    Write-Log "  WinGet Version: $($winget.Version)" -Level Success
    Write-Log "========================================" -Level Info

    exit 0

} catch {
    Write-Log "========================================" -Level Error
    Write-Log "Installation Failed!" -Level Error
    Write-Log "  Error: $($_.Exception.Message)" -Level Error
    Write-Log "========================================" -Level Error

    if ($_.ScriptStackTrace) {
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    }

    exit 1

} finally {
    Complete-DeploymentScript
}
