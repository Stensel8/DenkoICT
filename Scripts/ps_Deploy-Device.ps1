<#PSScriptInfo

.VERSION 1.2.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Deployment Logging

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Simple orchestrator for device provisioning.
[Version 1.0.1] - Added basic logging and remote download support.
[Version 1.0.2] - Aligned with better standards, improved error handling, and admin validation.
[Version 1.1.0] - Improved external log collection.
[Version 1.2.0] - Enforces C:\DenkoICT\Logs for all logging, uses Bitstransfer for downloads, forces custom-functions download.
[Version 1.2.2] - Enforces C:\DenkoICT\Download for all downloads.
#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Orchestrates Denko ICT device deployment by running child scripts in sequence.

.DESCRIPTION
    Always downloads custom functions. All logs and transcripts go to C:\DenkoICT\Logs. Uses Bitstransfer for remote downloads.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptBaseUrl = "https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:LogDirectory = 'C:\DenkoICT\Logs'
$script:DownloadDirectory = 'C:\DenkoICT\Download'
$script:TranscriptPath = $null
$script:TranscriptStarted = $false

function Write-ColorOutput {
    param([string]$Message,[string]$Level="Info")
    $color = switch ($Level) {
        "Success" {"Green"}
        "Warning" {"Yellow"}
        "Error"   {"Red"}
        "Verbose" {"Cyan"}
        Default   {"White"}
    }
    Write-Host $Message -ForegroundColor $color
}

function Write-Log {
    param([string]$Message,[string]$Level="INFO")
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $formattedMessage = "[$timestamp] [$Level] $Message"
    $colorLevel = switch ($Level) {
        "SUCCESS" {"Success"}
        "WARN"    {"Warning"}
        "ERROR"   {"Error"}
        "VERBOSE" {"Verbose"}
        Default   {"Info"}
    }
    Write-ColorOutput -Message $formattedMessage -Level $colorLevel
}

function Assert-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Script requires administrator privileges."
    }
    Write-Log "Administrator privileges confirmed." "VERBOSE"
}

function Initialize-Directories {
    if (-not (Test-Path $script:LogDirectory)) {
        New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $script:DownloadDirectory)) {
        New-Item -Path $script:DownloadDirectory -ItemType Directory -Force | Out-Null
    }
}

function Initialize-Logging {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:TranscriptPath = Join-Path $script:LogDirectory "Deployment-$timestamp.log"
    try {
        Start-Transcript -Path $script:TranscriptPath -Force | Out-Null
        $script:TranscriptStarted = $true
    } catch {
        $script:TranscriptPath = $null
        Write-Log "Transcript logging not started: $_" "WARN"
    }
    Write-Log "Transcript logging path: ${script:TranscriptPath}" "INFO"
}

function Get-RemoteScript {
    param([string]$ScriptUrl,[string]$SavePath)
    try {
        Import-Module BitsTransfer -ErrorAction SilentlyContinue
        Start-BitsTransfer -Source $ScriptUrl -Destination $SavePath -ErrorAction Stop
        Write-Log "Downloaded via BitsTransfer: $ScriptUrl > $SavePath" "SUCCESS"
    } catch {
        Write-Log "BitsTransfer failed, falling back to Invoke-WebRequest..." "WARN"
        try {
            Invoke-WebRequest -Uri $ScriptUrl -OutFile $SavePath -UseBasicParsing -ErrorAction Stop
            Write-Log "Downloaded via WebRequest: $ScriptUrl > $SavePath" "SUCCESS"
        } catch {
            Write-Log "Download failed: $ScriptUrl ($_) " "ERROR"
            throw
        }
    }
}

function Get-Script {
    param([string]$ScriptName)
    $url = "$ScriptBaseUrl/$ScriptName"
    $localPath = Join-Path $script:DownloadDirectory $ScriptName
    Get-RemoteScript -ScriptUrl $url -SavePath $localPath
    return $localPath
}

function Import-CustomFunctions {
    $customFunctionsUrl = "https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts/ps_Custom-Functions.ps1"
    $target = Join-Path $script:DownloadDirectory "ps_Custom-Functions.ps1"
    Get-RemoteScript -ScriptUrl $customFunctionsUrl -SavePath $target
    . $target
    Write-Log "Custom functions imported from $customFunctionsUrl" "INFO"
}

function Set-WinGetSessionDefaults {
    $wingetVariables = @{
        Debug = $false
        ForceClose = $false
        Force = $false
        AlternateInstallMethod = $false
    }
    foreach ($variable in $wingetVariables.Keys) {
        if (-not (Get-Variable -Name $variable -Scope Global -ErrorAction SilentlyContinue)) {
            New-Variable -Name $variable -Value $wingetVariables[$variable] -Scope Global | Out-Null
        }
    }
}

function Invoke-DeploymentStep {
    param([string]$ScriptName,[string]$DisplayName,[hashtable]$ScriptParameters)
    Write-Log "Start: ${DisplayName}" "INFO"
    try {
        $scriptPath = Get-Script -ScriptName $ScriptName
        Set-Variable -Name 'LASTEXITCODE' -Scope Global -Value 0 -Force
        if ($ScriptParameters -and $ScriptParameters.Count -gt 0) {
            & $scriptPath @ScriptParameters
        } else {
            & $scriptPath
        }
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Write-Log "Script exit code: $LASTEXITCODE" "WARN"
            return $false
        }
        Write-Log "Completed: ${DisplayName}" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed: ${DisplayName} - $($_)" "ERROR"
        return $false
    }
}

function Invoke-Deployment {
    $deploymentSteps = @(
        @{ Script = 'ps_Install-Winget.ps1'; Name = 'WinGet installation' },
        @{ Script = 'ps_Install-Drivers.ps1'; Name = 'Driver Updates' },
        @{ Script = 'ps_Install-Applications.ps1'; Name = 'Application installation' },
        @{ Script = 'ps_Set-Wallpaper.ps1'; Name = 'Wallpaper configuration' }
    )
    $result = [pscustomobject]@{ Success = 0; Failed = 0 }
    Set-WinGetSessionDefaults
    $wingetSucceeded = $false
    foreach ($step in $deploymentSteps) {
        $parameters = if ($step.ContainsKey('Parameters')) { $step.Parameters } else { $null }
        if ($step.Script -eq 'ps_Install-Winget.ps1') {
            $wingetSucceeded = Invoke-DeploymentStep -ScriptName $step.Script -DisplayName $step.Name -ScriptParameters $parameters
            if (-not $wingetSucceeded) {
                Write-Log "WinGet installation failed. Attempting alternative method..." "WARN"
                Set-Variable -Name 'AlternateInstallMethod' -Scope Global -Value $true -Force
                $wingetSucceeded = Invoke-DeploymentStep -ScriptName $step.Script -DisplayName 'WinGet installation (alternative)' -ScriptParameters $parameters
                Set-Variable -Name 'AlternateInstallMethod' -Scope Global -Value $false -Force
            }
            if ($wingetSucceeded) { $result.Success++ } else { $result.Failed++ }
            continue
        }
        if ($step.Script -eq 'ps_Install-Applications.ps1' -and -not $wingetSucceeded) {
            Write-Log "Application installation skipped; WinGet not available." "WARN"
            $result.Failed++
            continue
        }
        if (Invoke-DeploymentStep -ScriptName $step.Script -DisplayName $step.Name -ScriptParameters $parameters) {
            $result.Success++
        } else {
            $result.Failed++
            Write-Log "Continuing despite error..." "WARN"
        }
    }
    return $result
}

function Copy-ExternalLogs {
    if (-not $script:LogDirectory) {
        Write-Log "Log directory not defined. Skipping external logs." "WARN"
        return
    }
    if (-not (Test-Path -Path $script:LogDirectory)) {
        try { New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null }
        catch { Write-Log "Failed to create log directory: $_" "WARN"; return }
    }
    $logPaths = @(
        'C:\Windows\Setup\Scripts\SetComputerName.log'
        'C:\Windows\Setup\Scripts\RemovePackages.log'
        'C:\Windows\Setup\Scripts\RemoveCapabilities.log'
        'C:\Windows\Setup\Scripts\RemoveFeatures.log'
        'C:\Windows\Setup\Scripts\Specialize.log'
        (Join-Path $env:TEMP 'UserOnce.log')
        'C:\Windows\Setup\Scripts\DefaultUser.log'
        'C:\Windows\Setup\Scripts\FirstLogon.log'
    )
    $collected = 0
    foreach ($path in ($logPaths | Sort-Object -Unique)) {
        if (-not $path -or -not (Test-Path -Path $path -PathType Leaf)) {
            Write-Log "External log not found: '$path'" "VERBOSE"
            continue
        }
        try {
            $item = Get-Item -Path $path -ErrorAction Stop
            $destination = Join-Path $script:LogDirectory $item.Name
            if (Test-Path -Path $destination) {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
                $extension = [System.IO.Path]::GetExtension($item.Name)
                $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $destination = Join-Path $script:LogDirectory ("{0}-{1}{2}" -f $baseName, $timestamp, $extension)
            }
            Copy-Item -Path $item.FullName -Destination $destination -Force
            $collected++
            Write-Log "Copied log '$($item.FullName)' to '$destination'" "VERBOSE"
        } catch {
            Write-Log "Failed to copy log '$($item.FullName)': $_" "WARN"
        }
    }
    if ($collected -gt 0) {
        Write-Log "Copied $collected external log(s) to $script:LogDirectory" "INFO"
    } else {
        Write-Log "No external logs found to copy." "VERBOSE"
    }
}

try {
    Assert-Administrator
    Initialize-Directories
    Initialize-Logging
    Import-CustomFunctions
    Write-Log "=== Denko ICT Device Deployment Started ===" "INFO"
    $deploymentResult = Invoke-Deployment
    Write-Log "=== Deployment Complete ===" "INFO"
    Write-Log "Successful: $($deploymentResult.Success) | Failed: $($deploymentResult.Failed)" "INFO"
    Write-Log "Log file: $script:TranscriptPath" "INFO"
    Write-ColorOutput "`nDeployment finished. Press any key to exit..." "Info"
    [void][System.Console]::ReadKey($true)
    if ($deploymentResult.Failed -gt 0) { exit 1 } else { exit 0 }
} catch {
    Write-Log "Deployment aborted due to an unexpected error: $($_)" "ERROR"
    exit 1
} finally {
    try { Copy-ExternalLogs } catch { Write-Log "Failed to collect external logs: $_" "WARN" }
    if ($script:TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch { Write-Log "Failed to stop transcript: $_" "WARN" }
    }
}
