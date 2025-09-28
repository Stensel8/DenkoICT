<#
.SYNOPSIS
  PowerShell Preamble - Standard initialization script for DenkoICT scripts
.DESCRIPTION
  Sets up common environment variables, logging functions, and utilities for DenkoICT scripts
.INPUTS
  None
.OUTPUTS
  Log file stored in C:\IT\<scriptname>.log
.NOTES
  Version History:
  1.0.0 - 05/01/2024 - Jeffery Field
    * Initial script development
  
  2.0.0 - 15/09/2024 - Sten Tijhuis (Stensel8)
    * Refactored and moved to Scripts folder
    * Added DenkoLog functions and standardized formatting
  
  2.1.0 - [Current Date] - Sten Tijhuis (Stensel8)
    * Reorganized structure for better readability
    * Standardized versioning scheme
    * Updated attribution

.EXAMPLE
  . .\ps_Preamble.ps1
#>

Set-StrictMode -Version Latest

#region Initialization
$ErrorActionPreference = "SilentlyContinue"
$PSModuleAutoloadingPreference = 'All'

$ScriptVersion   = '2.1.0'
$Scriptname      = $MyInvocation.MyCommand.Name
$Scriptpath      = $MyInvocation.MyCommand.Path
$FullScriptpath  = $MyInvocation.MyCommand.PSCommandPath

$LogPath = 'C:\IT'
$LogName = "$Scriptname.log"
$LogFile = Join-Path -Path $LogPath -ChildPath $LogName

if (-not (Test-Path -Path $LogPath)) {
  $null = New-Item -Path $LogPath -ItemType Directory -Force
}
#endregion Initialization

#region Functions
function Write-DenkoLog {
  <#
  .SYNOPSIS
    Writes a timestamped message to the console, optionally in color.
  .DESCRIPTION
    Formats output with a timestamp prefix and color coding based on the
    supplied level.
  .PARAMETER Message
    Text to emit to the console.
  .PARAMETER Level
    Semantic level for the message. Supports Info, Success, Warning, Error,
    or Verbose.
  .EXAMPLE
    Write-DenkoLog -Message 'Starting deployment' -Level Info
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [Parameter()]
    [ValidateSet('Info','Success','Warning','Error','Verbose')]
    [string]$Level = 'Info'
  )

  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $formatted = "[$timestamp] [$Level] $Message"

  $color = switch ($Level) {
    'Success' { 'Green' }
    'Warning' { 'Yellow' }
    'Error'   { 'Red' }
    'Verbose' { 'Cyan' }
    default   { 'White' }
  }

  Write-Host $formatted -ForegroundColor $color
}

function Assert-DenkoAdministrator {
  <#
  .SYNOPSIS
    Ensures the current session runs with administrative rights.
  .DESCRIPTION
    Throws a terminating error when the current security principal isn't a
    member of the local Administrators group.
  .EXAMPLE
    Assert-DenkoAdministrator
  .NOTES
    Requires Windows PowerShell 5.1 or later.
  #>
  [CmdletBinding()]
  param()

  $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)

  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script requires administrative privileges. Please run in an elevated PowerShell session.'
  }
}

function Global:Check-Admin {
  <#
  .SYNOPSIS
    Checks to see what context the script is running in.
  .DESCRIPTION
    Checks to see what context the script is running in.
  .EXAMPLE
    Check-Admin
  .NOTES
    Version : 1.0.0
    Author: Jeffery Field
  #>
  [CmdletBinding()]

  $user = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($user)
  $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

  if ($isAdmin) {
    $Global:Context = 'Admin'
    return 'Admin'
  }

  $Global:Context = 'Standard'
  return 'Standard'
}
#endregion Functions

#region Main Execution
[double]$LogFileSize = 0
if (Test-Path -Path $LogFile) {
  $logInfo = Get-Item -Path $LogFile
  $LogFileSize = [Math]::Round($logInfo.Length / 1MB, 2)
}

if ($LogFileSize -ge 10) {
  Start-Transcript -Path $LogFile
  Write-DenkoLog -Message "Starting script $Scriptname with a new log." -Level Info
} else {
  Start-Transcript -Path $LogFile -Append
  Write-DenkoLog -Message "Starting script $Scriptname appending the log." -Level Info
}

$Dir = Split-Path -Path $Scriptpath

if ($Dir -like '*IMECache*' -or $Dir -like '*Microsoft Intune Management Extension*') {
  Write-DenkoLog -Message 'Detected Intune execution context. Switching to invocation directory.' -Level Verbose
  Set-Location -Path $Dir
}

try {
  if (-not [System.Diagnostics.EventLog]::SourceExists('Intune-Script')) {
    New-EventLog -Source 'Intune-Script' -LogName 'Application'
    Write-DenkoLog -Message 'Registered event log source Intune-Script.' -Level Verbose
  }
} catch {
  Write-DenkoLog -Message "Unable to register event log source Intune-Script: $($_.Exception.Message)" -Level Verbose
}

try {
  Write-EventLog -LogName 'Application' -Source 'Intune-Script' -EventID 1000 -EntryType Information -Message "Starting $Scriptname"
} catch {
  Write-DenkoLog -Message "Unable to write to event log: $($_.Exception.Message)" -Level Verbose
}
#endregion Main Execution

#region Cleanup
$Variables = Get-Variable
foreach ($Variable in $Variables) {
  Write-DenkoLog -Message "Variable $($Variable.Name) is set to $($Variable.Value)" -Level Verbose
}

Stop-Transcript
#endregion Cleanup
