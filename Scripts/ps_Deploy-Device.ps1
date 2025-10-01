<#PSScriptInfo

.VERSION 1.3.0

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
[Version 1.3.0] - Improved execution order, network stability checks with retries, better handling for network-dependent operations
#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Orchestrates Denko ICT device deployment by running child scripts in sequence.

.DESCRIPTION
    Always downloads custom functions. All logs and transcripts go to C:\DenkoICT\Logs. 
    Checks network stability before network-dependent operations.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptBaseUrl = "https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts",
    
    [Parameter(Mandatory = $false)]
    [int]$NetworkRetryCount = 5,
    
    [Parameter(Mandatory = $false)]
    [int]$NetworkRetryDelaySeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'  # Changed to Continue for better error resilience
$script:LogDirectory = 'C:\DenkoICT\Logs'
$script:DownloadDirectory = 'C:\DenkoICT\Download'
$script:TranscriptPath = $null
$script:TranscriptStarted = $false

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
    }
}

function Get-RemoteScript {
    param(
        [string]$ScriptUrl,
        [string]$SavePath,
        [int]$MaxRetries = 3
    )

    $directory = Split-Path $SavePath -Parent
    if (-not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Import-Module BitsTransfer -ErrorAction SilentlyContinue
            Start-BitsTransfer -Source $ScriptUrl -Destination $SavePath -ErrorAction Stop
            return $true
        } catch {
            if ($i -lt $MaxRetries) {
                try {
                    Invoke-WebRequest -Uri $ScriptUrl -OutFile $SavePath -UseBasicParsing -ErrorAction Stop
                    return $true
                } catch {
                    Start-Sleep -Seconds 5
                }
            }
        }
    }

    return $false
}

function Get-Script {
    param([string]$ScriptName)
    $url = "$ScriptBaseUrl/$ScriptName"
    $localPath = Join-Path $script:DownloadDirectory $ScriptName

    if (Get-RemoteScript -ScriptUrl $url -SavePath $localPath) {
        return $localPath
    } else {
        throw "Failed to download script: $ScriptName"
    }
}

function Import-CustomFunctions {
    $customFunctionsUrl = "https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts/ps_Custom-Functions.ps1"
    $target = Join-Path $script:DownloadDirectory "ps_Custom-Functions.ps1"

    if (Get-RemoteScript -ScriptUrl $customFunctionsUrl -SavePath $target) {
        . $target
    } else {
        throw "Failed to import custom functions"
    }
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
    param(
        [string]$ScriptName,
        [string]$DisplayName,
        [hashtable]$ScriptParameters,
        [switch]$RequiresNetwork,
        [switch]$RequiresStableNetwork
    )

    Write-Log "🔄 Starting: ${DisplayName}" -Level Info

    # Record step as running
    Set-DeploymentStepStatus -StepName $DisplayName -Status 'Running'

    try {
        # Check network if required
        if ($RequiresNetwork) {
            if (-not (Wait-ForNetworkStability -MaxRetries $NetworkRetryCount -DelaySeconds $NetworkRetryDelaySeconds -ContinuousCheck:$RequiresStableNetwork)) {
                Write-Log "Network not available for ${DisplayName}, skipping..." -Level Warning
                Set-DeploymentStepStatus -StepName $DisplayName -Status 'Skipped' -ErrorMessage 'Network not available'
                return $false
            }
        }

        $scriptPath = Get-Script -ScriptName $ScriptName
        Set-Variable -Name 'LASTEXITCODE' -Scope Global -Value 0 -Force

        if ($ScriptParameters -and $ScriptParameters.Count -gt 0) {
            & $scriptPath @ScriptParameters 2>&1 | Out-Null
        } else {
            & $scriptPath 2>&1 | Out-Null
        }

        $exitCode = $LASTEXITCODE

        if ($exitCode -and $exitCode -ne 0) {
            Write-Log "Step completed with exit code: $exitCode" -Level Warning
            # Non-zero exit code is logged but not considered a hard failure
            Set-DeploymentStepStatus -StepName $DisplayName -Status 'Success' -ExitCode $exitCode
            return $true
        }

        Write-Log "✓ Completed: ${DisplayName}" -Level Success
        Set-DeploymentStepStatus -StepName $DisplayName -Status 'Success'
        return $true

    } catch {
        $errorMsg = $_.Exception.Message
        Write-Log "✗ Failed: ${DisplayName}" -Level Error
        Write-Log "  Error details: $errorMsg" -Level Error
        Set-DeploymentStepStatus -StepName $DisplayName -Status 'Failed' -ErrorMessage $errorMsg
        return $false
    }
}

function Invoke-Deployment {
    # Execution order optimized for network stability and dependencies
    $deploymentSteps = @(
        @{
            Script = 'ps_Install-Winget.ps1'
            Name = 'WinGet Installation'
            RequiresNetwork = $true
            RequiresStableNetwork = $false
            Critical = $false  # Changed: Continue even if WinGet fails
        },
        @{
            Script = 'ps_Install-Drivers.ps1'
            Name = 'Driver Updates'
            RequiresNetwork = $true
            RequiresStableNetwork = $true
            Critical = $false
        },
        @{
            Script = 'ps_Install-Applications.ps1'
            Name = 'Application Installation'
            RequiresNetwork = $true
            RequiresStableNetwork = $true
            Critical = $false
            RequiresWinGet = $true
        },
        @{
            Script = 'ps_Set-Wallpaper.ps1'
            Name = 'Wallpaper Configuration'
            RequiresNetwork = $true
            RequiresStableNetwork = $false
            Critical = $false
        },
        @{
            Script = 'ps_Install-WindowsUpdates.ps1'
            Name = 'Windows Updates'
            RequiresNetwork = $true
            RequiresStableNetwork = $false
            Critical = $false
        }
    )

    $result = [pscustomobject]@{ Success = 0; Failed = 0; Skipped = 0 }
    Set-WinGetSessionDefaults
    $wingetSucceeded = $false

    Write-Log "═══════════════════════════════════════════════════════════" -Level Info
    Write-Log "  DENKO ICT DEVICE DEPLOYMENT" -Level Info
    Write-Log "═══════════════════════════════════════════════════════════" -Level Info

    foreach ($step in $deploymentSteps) {
        $parameters = if ($step.ContainsKey('Parameters')) { $step.Parameters } else { $null }

        # Track WinGet installation success
        if ($step.Script -eq 'ps_Install-Winget.ps1') {
            $wingetSucceeded = Invoke-DeploymentStep `
                -ScriptName $step.Script `
                -DisplayName $step.Name `
                -ScriptParameters $parameters `
                -RequiresNetwork:$step.RequiresNetwork `
                -RequiresStableNetwork:$step.RequiresStableNetwork

            if ($wingetSucceeded) {
                $result.Success++
            } else {
                $result.Failed++
                Write-Log "WinGet installation failed, but continuing deployment..." -Level Warning
            }
            continue
        }

        # Skip steps that require WinGet if it's not available
        if ($step.ContainsKey('RequiresWinGet') -and $step.RequiresWinGet -and -not $wingetSucceeded) {
            Write-Log "⊘ Skipping $($step.Name) - WinGet not available" -Level Warning
            $result.Skipped++
            continue
        }

        # Execute step with graceful error handling
        $stepResult = Invoke-DeploymentStep `
            -ScriptName $step.Script `
            -DisplayName $step.Name `
            -ScriptParameters $parameters `
            -RequiresNetwork:$step.RequiresNetwork `
            -RequiresStableNetwork:$step.RequiresStableNetwork

        if ($stepResult) {
            $result.Success++
        } else {
            $result.Failed++

            # Never abort - always try to complete as much as possible
            if ($step.Critical) {
                Write-Log "Critical step failed, but continuing with remaining steps..." -Level Warning
            } else {
                Write-Log "Step failed, continuing to next step..." -Level Warning
            }
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
    # Pre-flight checks
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script requires administrative privileges. Please run as Administrator."
    }

    Initialize-Directories
    Initialize-Logging

    # Import custom functions (critical - must succeed)
    Import-CustomFunctions

    # Initial network check with extended retry
    if (-not (Test-InternetConnection)) {
        Write-Host "[WARNING] No network connectivity detected. Some steps may fail." -ForegroundColor Yellow
        Write-Host "Waiting for network (up to 2 minutes)..." -ForegroundColor Cyan
        $null = Wait-ForNetworkStability -MaxRetries 12 -DelaySeconds 10
    }

    # Run deployment
    $null = Invoke-Deployment

    # Show detailed deployment summary from registry
    Show-DeploymentSummary -Title "DENKO ICT DEPLOYMENT COMPLETE"

    Write-Log "" -Level Info
    Write-Log "Log file location: $script:TranscriptPath" -Level Info
    Write-Log "" -Level Info

    # Show instructions for checking deployment status later
    Write-Log "═══════════════════════════════════════════════════════════" -Level Info
    Write-Log "  HOW TO CHECK DEPLOYMENT STATUS LATER:" -Level Info
    Write-Log "═══════════════════════════════════════════════════════════" -Level Info
    Write-Log "" -Level Info
    Write-Log "  You can check deployment status anytime by running:" -Level Info
    Write-Log "  Get-ItemProperty 'HKLM:\SOFTWARE\DenkoICT\Deployment\Steps\*'" -Level Info
    Write-Log "" -Level Info
    Write-Log "  Or import the custom functions and use:" -Level Info
    Write-Log "  . .\ps_Custom-Functions.ps1" -Level Info
    Write-Log "  Show-DeploymentSummary" -Level Info
    Write-Log "" -Level Info
    Write-Log "═══════════════════════════════════════════════════════════" -Level Info
    Write-Log "" -Level Info

    Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
    [void][System.Console]::ReadKey($true)

    # Exit with success code even if some steps failed (graceful degradation)
    exit 0

} catch {
    Write-Host "`n[CRITICAL ERROR] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "This error prevented the deployment from starting or completing." -ForegroundColor Red

    if ($_.ScriptStackTrace) {
        Write-Host "`nStack trace:" -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    }

    Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
    [void][System.Console]::ReadKey($true)
    exit 1

} finally {
    # Always try to collect external logs
    try {
        Copy-ExternalLogs
    } catch {
        Write-Host "[WARNING] Failed to collect external logs: $_" -ForegroundColor Yellow
    }

    # Always try to stop transcript
    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        } catch {
            # Silently ignore transcript stop errors
        }
    }
}
