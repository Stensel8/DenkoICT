<#PSScriptInfo

.VERSION 1.1.0

.GUID 6dbe7aa1-2cc8-410d-9be9-7b3453b9a0f5

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Deployment Intune FirstLogonAnimation Policy

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.1.0] - Added script metadata, administrative validation, and WhatIf support.
[Version 1.0.0] - Initial script to disable the first logon animation.
#>

#requires -Version 5.1

<#
.SYNOPSIS
    Disables the Windows first logon animation for all users.

.DESCRIPTION
    Creates the required registry key (if missing) under HKLM and sets
    the EnableFirstLogonAnimation value to 0, preventing the animated
    first-sign-in experience from showing to end users.

.EXAMPLE
    .\ps_DisableFirstLogonAnimation.ps1 -Verbose

    Runs the script with verbose output and disables the animation.

.NOTES
    Version      : 1.1.0
    Author       : Sten Tijhuis
    Company      : Denko ICT
    Requirements : Administrative privileges, Windows PowerShell 5.1+
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commonModule = Join-Path -Path $PSScriptRoot -ChildPath 'DenkoICT.Common.ps1'
if (-not (Test-Path -Path $commonModule)) {
    throw "Unable to locate shared helper module at $commonModule"
}

. $commonModule

Assert-AdminRights

$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

if ($PSCmdlet.ShouldProcess($regPath, 'Disable First Logon Animation')) {
    if (-not (Test-Path -Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    Write-Verbose "Created registry key at $regPath"
    Write-Log -Message "Created registry key at $regPath" -Level Verbose
    }

    Set-ItemProperty -Path $regPath -Name EnableFirstLogonAnimation -Type DWord -Value 0
    Write-Verbose 'Set EnableFirstLogonAnimation to 0'
    Write-Log -Message 'First logon animation disabled.' -Level Success
} else {
    Write-Verbose 'WhatIf: Skipping registry modifications.'
    Write-Log -Message 'WhatIf: Skipping registry modifications.' -Level Verbose
}
