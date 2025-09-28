<#PSScriptInfo

.VERSION 1.0.2

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Deployment Automation Logging

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Simple orchestrator for device provisioning.
[Version 1.0.1] - Added basic logging and remote download support.
[Version 1.0.2] - Aligned with better standards, improved error handling, and admin validation.
#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Orchestrates Denko ICT device deployment by running child scripts in sequence.

.DESCRIPTION
    Downloads or resolves required deployment scripts, executes them in a predefined order,
    and provides consistent logging via both console output and transcript files. Designed to be
    used during device provisioning either with local copies of scripts or remote downloads.

.PARAMETER ScriptBaseUrl
    The base URL where remote deployment scripts are hosted. Used when -UseLocal is not specified.

.PARAMETER UseLocal
    Switch to force execution of scripts from the local repository instead of downloading them.

.EXAMPLE
    .\ps_Deploy-Device.ps1

    Runs the deployment workflow by downloading the latest scripts from the repository.

.EXAMPLE
    .\ps_Deploy-Device.ps1 -UseLocal

    Runs the deployment workflow using scripts located alongside this orchestrator.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. Writes status information to the console and transcript log.

.NOTES
    Version      : 1.0.2
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires administrative privileges to execute successfully.

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptBaseUrl = "https://raw.githubusercontent.com/Stensel8/DenkoICT/main/Scripts",

    [Parameter(Mandatory = $false)]
    [switch]$UseLocal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LogDirectory = Join-Path $env:ProgramData 'DenkoICT\Logs'
$script:TranscriptPath = $null
$script:TranscriptStarted = $false

function Write-ColorOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Verbose')]
        [string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Verbose' { 'Cyan' }
        default   { 'White' }
    }

    Write-Host $Message -ForegroundColor $color
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR', 'VERBOSE')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $formattedMessage = "[$timestamp] [$Level] $Message"

    $colorLevel = switch ($Level) {
        'SUCCESS' { 'Success' }
        'WARN'    { 'Warning' }
        'ERROR'   { 'Error' }
        'VERBOSE' { 'Verbose' }
        default   { 'Info' }
    }

    Write-ColorOutput -Message $formattedMessage -Level $colorLevel
}

function Assert-Administrator {
    [CmdletBinding()]
    param()

    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script requires administrative privileges. Please run in an elevated PowerShell session.'
    }

    Write-Verbose 'Administrative privileges confirmed.'
}

function Initialize-Logging {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -Path $script:LogDirectory)) {
        New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:TranscriptPath = Join-Path $script:LogDirectory "Deployment-$timestamp.log"

    try {
        Start-Transcript -Path $script:TranscriptPath -Force | Out-Null
        $script:TranscriptStarted = $true
    } catch {
        $script:TranscriptPath = $null
        Write-ColorOutput -Message "Failed to start transcript logging: $_" -Level 'Warning'
    }

    if ($script:TranscriptPath) {
    Write-Log -Message "Transcript logging to ${script:TranscriptPath}" -Level 'INFO'
    }
}

function Get-RemoteScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptName
    )

    $localPath = Join-Path $env:TEMP "DenkoICT\$ScriptName"
    $localDir = Split-Path -Path $localPath -Parent

    if (-not (Test-Path -Path $localDir)) {
        New-Item -Path $localDir -ItemType Directory -Force | Out-Null
    }

    try {
        Write-Log -Message "Downloading ${ScriptName}..." -Level 'INFO'
        Invoke-WebRequest -Uri "$ScriptBaseUrl/$ScriptName" -OutFile $localPath -UseBasicParsing
    Write-Log -Message "Downloaded ${ScriptName} to ${localPath}" -Level 'SUCCESS'
        return $localPath
    } catch {
        Write-Log -Message "Failed to download ${ScriptName}: $($_)" -Level 'ERROR'
        throw
    }
}

function Resolve-LocalScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptName
    )

    $scriptDirectory = Split-Path -Parent $MyInvocation.PSCommandPath
    $scriptPath = Join-Path $scriptDirectory $ScriptName

    if (-not (Test-Path -Path $scriptPath)) {
        throw "Local script not found: $scriptPath"
    }

    return $scriptPath
}

function Invoke-DeploymentStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName
    )

    Write-Log -Message "Starting: ${DisplayName}" -Level 'INFO'

    try {
        $scriptPath = if ($UseLocal) {
            Resolve-LocalScript -ScriptName $ScriptName
        } else {
            Get-RemoteScript -ScriptName $ScriptName
        }

        & $scriptPath

        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Write-Log -Message "Script returned exit code: $LASTEXITCODE" -Level 'WARN'
            return $false
        }

    Write-Log -Message "Completed: ${DisplayName}" -Level 'SUCCESS'
        return $true
    } catch {
        Write-Log -Message "Failed: ${DisplayName} - $($_)" -Level 'ERROR'
        return $false
    }
}

function Invoke-Deployment {
    [CmdletBinding()]
    param()

    $deploymentSteps = @(
        @{ Script = 'ps_Install-Winget.ps1'; Name = 'WinGet Installation' },
        @{ Script = 'ps_Install-Drivers.ps1'; Name = 'Driver Updates' },
        @{ Script = 'ps_Install-Applications.ps1'; Name = 'Application Installation' },
        @{ Script = 'ps_Set-Wallpaper.ps1'; Name = 'Wallpaper Configuration' }
    )

    $result = [pscustomobject]@{
        Success = 0
        Failed  = 0
    }

    foreach ($step in $deploymentSteps) {
        if (Invoke-DeploymentStep -ScriptName $step.Script -DisplayName $step.Name) {
            $result.Success++
        } else {
            $result.Failed++
            Write-Log -Message 'Continuing despite error...' -Level 'WARN'
        }
    }

    return $result
}

try {
    Assert-Administrator

    Initialize-Logging

    Write-Log -Message '=== Denko ICT Device Deployment Started ===' -Level 'INFO'
    $mode = if ($UseLocal) { 'Local' } else { 'Remote' }
    Write-Log -Message ("Mode: {0}" -f $mode) -Level 'INFO'

    $deploymentResult = Invoke-Deployment

    Write-Log -Message '=== Deployment Complete ===' -Level 'INFO'
    Write-Log -Message ("Successful: {0} | Failed: {1}" -f $deploymentResult.Success, $deploymentResult.Failed) -Level 'INFO'

    if ($script:TranscriptPath) {
        Write-Log -Message ("Log file: {0}" -f $script:TranscriptPath) -Level 'INFO'
    }

    Write-ColorOutput -Message "`nDeployment finished. Press any key to exit..." -Level 'Info'
    [void][System.Console]::ReadKey($true)

    if ($deploymentResult.Failed -gt 0) {
        exit 1
    } else {
        exit 0
    }
} catch {
        Write-Log -Message "Deployment halted due to unexpected error: $($_)" -Level 'ERROR'
    exit 1
} finally {
    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        } catch {
            Write-ColorOutput -Message "Failed to stop transcript: $_" -Level 'Warning'
        }
    }
}