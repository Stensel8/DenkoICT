<#PSScriptInfo

.VERSION 2.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Deployment Intune FirstLogonAnimation Policy

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial script to disable the first logon animation.
[Version 1.1.0] - Added script metadata, administrative validation, and WhatIf support.
[Version 2.0.0] - Refactored to use modular utilities, removed parameters for simplicity.
#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Disables the Windows first logon animation for all users.

.DESCRIPTION
    Sets registry key to disable the animated first-sign-in experience.

.EXAMPLE
    .\DisableFirstLogonAnimation.ps1

.NOTES
    Version      : 2.0.0
    Author       : Sten Tijhuis
    Company      : Denko ICT
    Requirements : Administrative privileges, Windows PowerShell 5.1+
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import required modules
$possiblePaths = @(
    (Join-Path $PSScriptRoot 'Utilities'),
    'C:\DenkoICT\Download\Utilities',
    'C:\DenkoICT\Utilities'
)
$utilitiesPath = $null
foreach ($p in $possiblePaths) { if (Test-Path $p) { $utilitiesPath = $p; break } }
if (-not $utilitiesPath) { Write-Error "Could not find Utilities folder"; exit 1 }

Import-Module (Join-Path $utilitiesPath 'Logging.psm1') -Force -Global
Import-Module (Join-Path $utilitiesPath 'Registry.psm1') -Force -Global

Start-EmergencyTranscript -LogName 'DisableFirstLogonAnimation.log'
Initialize-Script -RequireAdmin

try {
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

    Set-RegistryValue -Path $regPath -Name 'EnableFirstLogonAnimation' -Value 0 -Type 'DWord'
    Write-Log 'First logon animation disabled' -Level Success

    Set-IntuneSuccess -AppName 'DisableFirstLogonAnimation' -Version '2.0.0'
    exit 0
} catch {
    Write-Log "Failed to disable first logon animation: $($_.Exception.Message)" -Level Error
    exit 1
} finally {
    Complete-Script
}
