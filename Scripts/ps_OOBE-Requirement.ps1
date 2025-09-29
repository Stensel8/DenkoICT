<#
Revision: 3.1.0
Author: Sten Tijhuis (Stensel8)
Date: 15/09/2025
Purpose/Change: Wrapper updated to target ps_Custom-Functions.ps1 after toolkit rename.
.SYNOPSIS
  Ensures the device is in OOBE by delegating to ps_Custom-Functions.ps1.
.DESCRIPTION
  Calls ps_Custom-Functions.ps1 with the CheckOOBEStatus switch so the consolidated toolkit
  performs the Autopilot status evaluation and CMTrace logging.
.PARAMETER LogPath
  Directory path used for CMTrace compatible logging. Default: C:\UA_IT.
.PARAMETER LogName
  Name of the CMTrace log file. Default: OOBE-Requirement.log.
.OUTPUTS
  Returns "In-OOBE" or "Not-In-OOBE" along with writing CMTrace logs via ps_Custom-Functions.ps1.
.NOTES
  Version:        3.1.0
  Author:         Sten Tijhuis
  Creation Date:  15/09/2025
  Purpose/Change: Refactored to call ps_Custom-Functions.ps1 for consolidated maintenance.
#>

#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = 'C:\UA_IT',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogName = 'OOBE-Requirement.log'
)

$toolkitPath = Join-Path -Path $PSScriptRoot -ChildPath 'Custom-Functions.ps1'

if (-not (Test-Path -Path $toolkitPath)) {
  throw "Unable to locate Custom-Functions.ps1 at path '$toolkitPath'."
}

$arguments = @{
    CheckOOBEStatus = $true
    OOBELogPath     = $LogPath
    OOBELogName     = $LogName
}

& $toolkitPath @arguments