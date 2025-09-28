<#PSScriptInfo

.VERSION 3.3.1

.AUTHOR Sten Tijhuis (Stensel8)

.COMPANYNAME Denko ICT

.TAGS PowerShell Intune Deployment Logging Security

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 3.3.1] - Updated wrapper to target Invoke-AdminToolkit.ps1 after toolkit rename.
[Version 3.2.0] - Converted script into a wrapper around ps_Toolkit.ps1 after consolidating functions there.
[Version 3.1.1] - Renamed script to ps_Invoke-Tools.ps1 per Denko ICT naming preference and refreshed usage examples.
[Version 3.1.0] - Renamed script to Invoke-DenkoToolkit.ps1 to follow PowerShell Verb-Noun guidance and refreshed documentation.
[Version 3.0.0] - Unified common initialization, logging, Intune success handling, and Denko administrator provisioning into a single script.

#>

<#
.SYNOPSIS
  Compatibility wrapper that forwards all operations to Invoke-AdminToolkit.ps1.
.DESCRIPTION
  Maintains the previous script name while delegating execution to Invoke-AdminToolkit.ps1,
  where the consolidated DenkoICT toolkit logic now resides.
.PARAMETER CreateDenkoAdmin
  When provided, provisions or updates the Denko administrator account using the supplied parameters.
.PARAMETER Username
  Local administrator account name. Default: DenkoAdmin.
.PARAMETER Password
  SecureString password for the administrator account. Defaults to a demo password when omitted.
.PARAMETER ResetExistingPassword
  Resets the password for an existing Denko administrator account when specified.
.PARAMETER SetIntuneSuccess
  Writes Intune success criteria to HKLM:\SOFTWARE\Intune when provided.
.PARAMETER IntuneKeyName
  Registry value name used for Intune success tracking.
.PARAMETER IntuneKeyValue
  Registry value content used for Intune success tracking. Default: 1.0.0.
.PARAMETER CheckOOBEStatus
  Evaluates the Autopilot OOBE requirement using Invoke-AdminToolkit.ps1.
.PARAMETER OOBELogPath
  Directory path used for CMTrace compatible logging. Default: C:\UA_IT.
.PARAMETER OOBELogName
  Name of the CMTrace log file. Default: OOBE-Requirement.log.
.EXAMPLE
  .\ps_Invoke-Tools.ps1 -CreateDenkoAdmin -Verbose

  Forwards the request to Invoke-AdminToolkit.ps1 to create or update the Denko admin account.
.NOTES
  Version:        3.3.1
  Author:         Sten Tijhuis (Stensel8)
  Original Work:  Jeffery Field, Denko ICT Team
  Requires:       Windows PowerShell 5.1 or newer, administrative privileges for most operations
  Compatibility:  Implements the same parameter surface as Invoke-AdminToolkit.ps1 and forwards all invocations.
#>

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [switch]$CreateDenkoAdmin,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Username = 'DenkoAdmin',

    [Parameter()]
    [System.Security.SecureString]$Password,

    [Parameter()]
    [switch]$ResetExistingPassword,

    [Parameter()]
    [switch]$SetIntuneSuccess,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$IntuneKeyName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$IntuneKeyValue = '1.0.0',

    [Parameter()]
    [switch]$CheckOOBEStatus,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OOBELogPath = 'C:\UA_IT',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OOBELogName = 'OOBE-Requirement.log'
)

$toolkitPath = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-AdminToolkit.ps1'

if (-not (Test-Path -Path $toolkitPath)) {
  throw "Unable to locate Invoke-AdminToolkit.ps1 at path '$toolkitPath'."
}

if ($PSBoundParameters.Count -gt 0) {
    & $toolkitPath @PSBoundParameters
} else {
    & $toolkitPath
}
