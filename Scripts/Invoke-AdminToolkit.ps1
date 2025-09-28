<#PSScriptInfo

.VERSION 3.3.0

.AUTHOR Sten Tijhuis (Stensel8)

.COMPANYNAME Denko ICT

.TAGS PowerShell Intune Deployment Logging Security

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 3.3.1] - Renamed script to Invoke-AdminToolkit.ps1 and updated documentation references.
[Version 3.3.0] - Consolidated toolkit, Invoke-Tools, and OOBE scripts; unified directory handling logic.
[Version 3.2.0] - Renamed script to ps_Toolkit.ps1 and simplified helper function names for clarity.
[Version 3.1.1] - Renamed script to ps_Invoke-Tools.ps1 per Denko ICT naming preference and refreshed usage examples.
[Version 3.1.0] - Renamed script to Invoke-DenkoToolkit.ps1 to follow PowerShell Verb-Noun guidance and refreshed documentation.
[Version 3.0.0] - Unified common initialization, logging, Intune success handling, and Denko administrator provisioning into a single script.

#>

<#!
.SYNOPSIS
  DenkoICT unified initialization and utility script.
.DESCRIPTION
  Provides standardized logging, administrative validation, Intune success registry handling,
  and Denko administrator provisioning in a single reusable script.
.PARAMETER CreateDenkoAdmin
  When provided, provisions or updates the Denko administrator account using the supplied parameters.
.PARAMETER Username
  Local administrator account name. Default: DenkoAdmin.
.PARAMETER Password
  SecureString password for the administrator account. Required when creating a new account or resetting credentials.
.PARAMETER ResetExistingPassword
  Resets the password for an existing Denko administrator account when specified.
.PARAMETER SetIntuneSuccess
  Writes Intune success criteria to HKLM:\SOFTWARE\Intune when provided.
.PARAMETER IntuneKeyName
  Registry value name used for Intune success tracking.
.PARAMETER IntuneKeyValue
  Registry value content used for Intune success tracking. Default: 1.0.0.
.EXAMPLE
  .\Invoke-AdminToolkit.ps1 -CreateDenkoAdmin -Verbose

  Initialises the environment, provisions the Denko administrator account, and emits verbose logs.
.EXAMPLE
  .\Invoke-AdminToolkit.ps1 -SetIntuneSuccess -IntuneKeyName FireFox_Version -IntuneKeyValue 129.0.1

  Records a success registry value for Intune.
.NOTES
  Version:        3.3.1
  Author:         Sten Tijhuis (Stensel8)
  Requires:       Windows PowerShell 5.1 or newer, administrative privileges for most operations
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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSModuleAutoloadingPreference = 'All'

$script:ScriptVersion     = '3.3.1'
$script:ScriptName        = $MyInvocation.MyCommand.Name
$script:ScriptPath        = $MyInvocation.MyCommand.Path
$script:FullScriptPath    = $MyInvocation.PSCommandPath
$script:LogPath           = 'C:\IT'
$script:LogFile           = Join-Path -Path $script:LogPath -ChildPath "${script:ScriptName}.log"
$script:TranscriptStarted = $false

function Write-Log {
  <#
  .SYNOPSIS
    Writes a timestamped message to the console, optionally in color.
  .PARAMETER Message
    Text to emit to the console.
  .PARAMETER Level
    Semantic level for the message. Supports Info, Success, Warning, Error, or Verbose.
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

function Initialize-DirectoryPath {
  <#
  .SYNOPSIS
    Guarantees that a directory exists, creating it when necessary.
  .PARAMETER Path
    Directory path to validate or create.
  .PARAMETER Purpose
    Friendly name used for log messages. Default: directory.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter()]
    [string]$Purpose = 'directory'
  )

  if (Test-Path -Path $Path) {
    return
  }

  try {
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    Write-Log -Message "Created $Purpose at ${Path}." -Level Verbose
  } catch {
    Write-Log -Message "Unable to create $Purpose at ${Path}: $($_.Exception.Message)" -Level Error
    throw
  }
}

function Assert-AdminRights {
  <#
  .SYNOPSIS
    Ensures the current session runs with administrative rights.
  .DESCRIPTION
    Throws a terminating error when the current security principal isn't a member of the local Administrators group.
  #>
  [CmdletBinding()]
  param()

  $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)

  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $message = 'This script requires administrative privileges. Please run in an elevated PowerShell session.'
    Write-Log -Message $message -Level Error
    throw $message
  }
}

function Get-SessionContext {
  <#
  .SYNOPSIS
    Returns the current execution context, Admin or Standard.
  #>
  [CmdletBinding()]
  param()

  $user      = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($user)
  $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

  if ($isAdmin) {
    $Global:Context = 'Admin'
    return 'Admin'
  }

  $Global:Context = 'Standard'
  return 'Standard'
}
Set-Alias -Name 'Check-Admin' -Value Get-SessionContext

function Initialize-Environment {
  <#
  .SYNOPSIS
    Creates log directories, starts the transcript, and prepares event log sources.
  #>
  [CmdletBinding()]
  param()

  Initialize-DirectoryPath -Path $script:LogPath -Purpose 'log directory'

  $logSizeMB = 0
  if (Test-Path -Path $script:LogFile) {
    $logInfo  = Get-Item -Path $script:LogFile
    $logSizeMB = [Math]::Round($logInfo.Length / 1MB, 2)
  }

  if ($logSizeMB -ge 10) {
    Start-Transcript -Path $script:LogFile | Out-Null
    Write-Log -Message "Starting script ${script:ScriptName} with a new log." -Level Info
  } else {
    Start-Transcript -Path $script:LogFile -Append | Out-Null
    Write-Log -Message "Starting script ${script:ScriptName} appending the log." -Level Info
  }
  $script:TranscriptStarted = $true

  $dir = Split-Path -Path $script:ScriptPath
  if ($dir -like '*IMECache*' -or $dir -like '*Microsoft Intune Management Extension*') {
    Write-Log -Message 'Detected Intune execution context. Switching to invocation directory.' -Level Verbose
    Set-Location -Path $dir
  }

  foreach ($source in @('Intune-Script','DenkoICT')) {
    try {
      if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
        New-EventLog -Source $source -LogName 'Application'
        Write-Log -Message "Registered event log source ${source}." -Level Verbose
      }
    } catch {
      Write-Log -Message "Unable to register event log source ${source}: $($_.Exception.Message)" -Level Verbose
    }
  }

  foreach ($eventRecord in @(
    @{ Source = 'Intune-Script'; EventId = 1000; Message = "Starting ${script:ScriptName}"; EntryType = 'Information' },
    @{ Source = 'DenkoICT';     EventId = 1000; Message = "Initializing ${script:ScriptName}"; EntryType = 'Information' }
  )) {
    try {
      Write-EventLog -LogName 'Application' -Source $eventRecord.Source -EventID $eventRecord.EventId -EntryType $eventRecord.EntryType -Message $eventRecord.Message
    } catch {
      Write-Log -Message "Unable to write to event log ($($eventRecord.Source)): $($_.Exception.Message)" -Level Verbose
    }
  }
}

function Stop-Environment {
  <#
  .SYNOPSIS
    Stops the transcript and optionally emits a variable dump for verbose diagnostics.
  .PARAMETER EmitEnvironmentDump
    When set, logs current variable values at Verbose level before stopping the transcript.
  #>
  [CmdletBinding()]
  param(
    [Parameter()]
    [switch]$EmitEnvironmentDump
  )

  if ($EmitEnvironmentDump) {
    foreach ($variable in Get-Variable) {
      Write-Log -Message "Variable $($variable.Name) is set to $($variable.Value)" -Level Verbose
    }
  }

  if ($script:TranscriptStarted) {
    try {
      Stop-Transcript | Out-Null
    } catch {
      Write-Log -Message "Unable to stop transcript: $($_.Exception.Message)" -Level Verbose
    }
    $script:TranscriptStarted = $false
  }
}
Set-Alias -Name 'Finalize-Environment' -Value Stop-Environment

function Set-DenkoAdmin {
  <#
  .SYNOPSIS
    Provisions or updates the Denko ICT local administrator account.
  .PARAMETER Username
    Username for the local administrator. Default: DenkoAdmin.
  .PARAMETER Password
    Optional SecureString password for the administrator.
  .PARAMETER ResetExistingPassword
    When provided, resets the password for the existing account.
  #>
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
  param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Username = 'DenkoAdmin',

    [Parameter()]
    [System.Security.SecureString]$Password,

    [Parameter()]
    [switch]$ResetExistingPassword
  )

  try {
    Assert-AdminRights

    Write-Log -Message "Checking if user '$Username' exists." -Level Verbose
    $existingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue

    $accountExists = [bool]$existingUser
    $passwordSupplied = $PSBoundParameters.ContainsKey('Password') -and $Password

    if (-not $accountExists -and -not $passwordSupplied) {
      Write-Log -Message "No password supplied; '$Username' will be created without credentials. Ensure this aligns with your security policy." -Level Warning
    }

    if ($accountExists -and $Password -and -not $ResetExistingPassword.IsPresent) {
      Write-Log -Message 'Password parameter supplied without requesting a reset; ignoring provided value.' -Level Verbose
    }

    if ($accountExists) {
      Write-Log -Message "User '$Username' already exists." -Level Warning

      if ($ResetExistingPassword) {
        if ($passwordSupplied) {
          if ($PSCmdlet.ShouldProcess("Local user '$Username'", 'Reset local administrator password')) {
            Set-LocalUser -Name $Username -Password $Password
            Write-Log -Message "Password reset for user '$Username'." -Level Success
          }
        } else {
          Write-Log -Message 'ResetExistingPassword specified without a new password; skipping password reset.' -Level Warning
        }
      } else {
        Write-Log -Message 'ResetExistingPassword not specified; leaving existing credentials unchanged.' -Level Verbose
      }
    } else {
      Write-Log -Message "Creating new local user '$Username'." -Level Verbose

      if ($PSCmdlet.ShouldProcess("Local user '$Username'", 'Create local administrator account')) {
        $userParams = @{
          Name                     = $Username
          FullName                 = 'Denko ICT Administrator'
          Description              = 'Administrative account for Denko ICT management'
          PasswordNeverExpires     = $true
          AccountNeverExpires      = $true
          UserMayNotChangePassword = $false
        }

        if ($passwordSupplied) {
          $userParams['Password'] = $Password
        } else {
          $userParams['NoPassword'] = $true
        }

        New-LocalUser @userParams
        Write-Log -Message "Created local user '$Username'." -Level Success
      }
    }

    $isMember = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$Username" }
    if (-not $isMember) {
      if ($PSCmdlet.ShouldProcess('Administrators group', "Add '$Username' as member")) {
        Add-LocalGroupMember -Group 'Administrators' -Member $Username
        Write-Log -Message "Added '$Username' to the Administrators group." -Level Success
      }
    } else {
      Write-Log -Message "'$Username' is already a member of the Administrators group." -Level Verbose
    }

    if ($PSCmdlet.ShouldProcess('Application Event Log', 'Record DenkoAdmin account activity')) {
      $logMessage = "DenkoAdmin account processed on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') by $env:USERNAME"
      try {
        Write-EventLog -LogName 'Application' -Source 'DenkoICT' -EventID 1000 -EntryType Information -Message $logMessage
        Write-Log -Message 'Audit entry written to Application log.' -Level Verbose
      } catch {
        Write-Log -Message "Unable to write audit entry: $($_.Exception.Message)" -Level Warning
      }
    }

    $finalCheck = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$Username" }
    if ($finalCheck) {
      Write-Log -Message "Verified: '$Username' has administrator privileges." -Level Success
    } else {
      Write-Log -Message "Warning: '$Username' might not have full administrator privileges." -Level Warning
    }

  } catch {
    Write-Log -Message "Failed to create or modify user: $($_.Exception.Message)" -Level Error
    throw
  }
}

function Set-IntuneStatus {
  <#
  .SYNOPSIS
    Creates or updates the Intune success criteria registry value.
  .PARAMETER KeyName
    Registry value name to update beneath HKLM:\SOFTWARE\Intune.
  .PARAMETER KeyValue
    Registry value data. Default: 1.0.0.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$KeyName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$KeyValue = '1.0.0'
  )

  $regKeyName    = 'Intune'
  $fullRegKeyName = "HKLM:\\SOFTWARE\\$regKeyName"

  Write-Log -Message "Setting Intune success registry key '$KeyName' to '$KeyValue'." -Level Info

  if (-not (Test-Path -Path $fullRegKeyName)) {
    Write-Log -Message "Creating registry path $fullRegKeyName." -Level Verbose
    try {
      New-Item -Path $fullRegKeyName -ItemType Directory -Force | Out-Null
    } catch {
      Write-Log -Message "Unable to create registry path: $($_.Exception.Message)" -Level Error
      throw
    }
  } else {
    Write-Log -Message "Registry path $fullRegKeyName already exists." -Level Verbose
  }

  try {
    New-ItemProperty -Path $fullRegKeyName -Name $KeyName -Value $KeyValue -PropertyType String -Force | Out-Null
    Write-Log -Message 'Completed Intune success registry update.' -Level Success
  } catch {
    Write-Log -Message "Failed to set Intune success registry value: $($_.Exception.Message)" -Level Error
    throw
  }
}

function Write-CmTraceLog {
  <#
  .SYNOPSIS
    Writes structured log entries compatible with CMTrace.
  .PARAMETER Message
    Text to record in the log entry.
  .PARAMETER Component
    Name of the component emitting the log entry.
  .PARAMETER Path
    Directory that will contain the log file. Created when absent.
  .PARAMETER LogName
    File name for the log file.
  .PARAMETER Thread
    Optional thread identifier used in the log entry. Default: 0.
  .PARAMETER File
    Optional file identifier used in the log entry. Default: N/A.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [Parameter(Mandatory = $true)]
    [string]$Component,

    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$LogName,

    [Parameter()]
    [string]$Thread = '0',

    [Parameter()]
    [string]$File = 'N/A'
  )

  Initialize-DirectoryPath -Path $Path -Purpose 'CMTrace log directory'

  $timeStamp = Get-Date -Format 'HH:mm:ss.fff+300'
  $dateStamp = Get-Date -Format 'MM-dd-yyyy'
  $header = '<![LOG['
  $footer = ']LOG]!>'
  $metadata = 'time="{0}" date="{1}" component="{2}" context="" type="1" thread="{3}" file="{4}"' -f $timeStamp, $dateStamp, $Component, $Thread, $File
  $entry = "$header$Message$footer<$metadata>"

  Add-Content -Path (Join-Path -Path $Path -ChildPath $LogName) -Value $entry
}

function Get-AutopilotStatusDetails {
  <#
  .SYNOPSIS
    Retrieves Autopilot provisioning category status details.
  .OUTPUTS
    Array of PSObject instances containing Category, Step, Status, StatusText, and OverallStatus.
  #>
  [CmdletBinding()]
  param()

  $statusCollection = @()

  $autoPilotSettingsKey = 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotSettings'
  $devicePrepName      = 'DevicePreparationCategory.Status'
  $deviceSetupName     = 'DeviceSetupCategory.Status'
  $accountSetupName    = 'AccountSetupCategory.Status'

  $autoPilotDiagnosticsKey = 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot'
  $tenantIdName             = 'CloudAssignedTenantId'

  $joinInfoKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'

  $cloudAssignedTenantID = (Get-ItemProperty -Path $autoPilotDiagnosticsKey -Name $tenantIdName -ErrorAction Ignore).$tenantIdName

  if ([string]::IsNullOrEmpty($cloudAssignedTenantID)) {
    return $statusCollection
  }

  $azureADTenantId = $null
  foreach ($guidKey in (Get-ChildItem -Path $joinInfoKey -ErrorAction Ignore)) {
    $tenant = (Get-ItemProperty -Path (Join-Path -Path $joinInfoKey -ChildPath $guidKey.PSChildName) -Name 'TenantId' -ErrorAction Ignore).'TenantId'
    if (-not [string]::IsNullOrEmpty($tenant)) {
      $azureADTenantId = $tenant
      break
    }
  }

  if ($cloudAssignedTenantID -ne $azureADTenantId) {
    return $statusCollection
  }

  $categoryDefinitions = @(
    @{ Name = $devicePrepName;  Label = 'DevicePreparation' },
    @{ Name = $deviceSetupName; Label = 'DeviceSetup' },
    @{ Name = $accountSetupName; Label = 'AccountSetup' }
  )

  foreach ($definition in $categoryDefinitions) {
    $rawDetails = (Get-ItemProperty -Path $autoPilotSettingsKey -Name $definition.Name -ErrorAction Ignore).$($definition.Name)
    if ([string]::IsNullOrEmpty($rawDetails)) {
      continue
    }

    try {
      $details = $rawDetails | ConvertFrom-Json
    } catch {
      Write-Log -Message "Unable to parse Autopilot JSON for $($definition.Label): $($_.Exception.Message)" -Level Warning
      continue
    }

    $noteProperties = Get-Member -InputObject $details | Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -like "$($definition.Label).*" }
    $overallStatus = "$($details.categoryState) - $($details.CategoryStatusText)"

    foreach ($noteProperty in $noteProperties) {
      $propName  = $noteProperty.Name.Split('.')[-1]
      $category  = $noteProperty.Name.Split('.')[0]
      $stepInfo  = $details."$($noteProperty.Name)"

      if ($null -eq $stepInfo) {
        continue
      }

      $statusObject = [PSCustomObject]@{
        Category      = $category
        Step          = $propName
        StatusText    = $stepInfo.Subcategorystatustext
        Status        = $stepInfo.SubcategoryState
        OverallStatus = $overallStatus
      }

      $statusCollection += $statusObject
    }
  }

  return $statusCollection
}

function Invoke-OOBERequirement {
  <#
  .SYNOPSIS
    Evaluates Autopilot provisioning state and records CMTrace-compatible logs.
  .PARAMETER LogPath
    Directory path for the CMTrace log file.
  .PARAMETER LogName
    Name of the CMTrace log file.
  .OUTPUTS
    Returns the string "In-OOBE" or "Not-In-OOBE" to reflect provisioning progress.
  #>
  [CmdletBinding()]
  param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = 'C:\UA_IT',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogName = 'OOBE-Requirement.log'
  )

  $statuses = Get-AutopilotStatusDetails
  $Global:APStatus = $statuses

  Write-CmTraceLog -Message 'AutoPilot status is' -Component 'UA-Intune-Script' -Path $LogPath -LogName $LogName
  Write-CmTraceLog -Message ' ' -Component 'UA-Intune-Script' -Path $LogPath -LogName $LogName

  foreach ($status in $statuses) {
    Write-CmTraceLog -Message "$($status.Category) - $($status.Step) - $($status.Status) - $($status.StatusText)" -Component 'UA-Intune-Script' -Path $LogPath -LogName $LogName
  }

  if (-not $statuses) {
    $Global:IsAPRunning = 'AP_Unknown'
    Write-CmTraceLog -Message 'No Autopilot status information available' -Component 'UA-Intune-Script' -Path $LogPath -LogName $LogName
    return 'Not-In-OOBE'
  }

  if (($statuses | Select-Object -ExpandProperty OverallStatus -Unique) -match 'Failed') {
    Write-CmTraceLog -Message 'AutoPilot has failed' -Component 'UA-Intune-Script' -Path $LogPath -LogName $LogName
    $Global:IsAPRunning = 'AP_Failed'
    return 'Not-In-OOBE'
  }

  if (($statuses | Select-Object -ExpandProperty Status -Unique) -match 'InProgress') {
    $Global:IsAPRunning = 'AP_Running'
    Write-CmTraceLog -Message 'AutoPilot is running' -Component 'UA-Intune-Script' -Path $LogPath -LogName $LogName
    return 'In-OOBE'
  }

  $Global:IsAPRunning = 'AP_Complete'
  Write-CmTraceLog -Message 'AutoPilot is complete' -Component 'UA-Intune-Script' -Path $LogPath -LogName $LogName
  return 'Not-In-OOBE'
}

if ($MyInvocation.InvocationName -ne '.') {
  Initialize-Environment
  $emitVariableDump = $VerbosePreference -eq 'Continue'

  try {
    $actionsInvoked = $false

    if ($CreateDenkoAdmin) {
      Set-DenkoAdmin -Username $Username -Password $Password -ResetExistingPassword:$ResetExistingPassword
      $actionsInvoked = $true
    }

    if ($SetIntuneSuccess) {
      if (-not $IntuneKeyName) {
        throw "Parameter -IntuneKeyName is required when using -SetIntuneSuccess."
      }

      Set-IntuneStatus -KeyName $IntuneKeyName -KeyValue $IntuneKeyValue
      $actionsInvoked = $true
    }

    if ($CheckOOBEStatus) {
      $oobeResult = Invoke-OOBERequirement -LogPath $OOBELogPath -LogName $OOBELogName
      Write-Log -Message "OOBE requirement result: $oobeResult" -Level Info
      $actionsInvoked = $true
      Write-Output $oobeResult
    }

    if (-not $actionsInvoked) {
      Write-Log -Message 'Initialization complete. No actions were requested. Use -CreateDenkoAdmin, -SetIntuneSuccess, and/or -CheckOOBEStatus to perform operations.' -Level Info
      Write-Log -Message 'Exported helper functions: Write-Log, Assert-AdminRights, Check-Admin, Initialize-DirectoryPath, Set-DenkoAdmin, Set-IntuneStatus, Write-CmTraceLog, Get-AutopilotStatusDetails, Invoke-OOBERequirement.' -Level Verbose
    }
  } catch {
    Write-Log -Message "Script encountered an unrecoverable error: $($_.Exception.Message)" -Level Error
    throw
  } finally {
    Stop-Environment -EmitEnvironmentDump:$emitVariableDump
  }
}
