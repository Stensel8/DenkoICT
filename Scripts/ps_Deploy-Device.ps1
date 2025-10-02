<#PSScriptInfo

.VERSION 2.0.0

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
[Version 2.0.0] - Major refactor: Simplified orchestration, removed inline functions, better error handling, cleaner network retry logic
#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Orchestrates Denko ICT device deployment by running child scripts in sequence.

.DESCRIPTION
    Downloads custom functions, validates network connectivity, and executes deployment scripts.
    All logs go to C:\DenkoICT\Logs. All downloads go to C:\DenkoICT\Download.

.PARAMETER ScriptBaseUrl
    Base URL for downloading scripts from GitHub.

.PARAMETER NetworkRetryCount
    Number of retry attempts for network connectivity checks.

.PARAMETER NetworkRetryDelaySeconds
    Delay in seconds between network retry attempts.

.EXAMPLE
    .\ps_Deploy-Device.ps1
    Runs full deployment with default settings.

.EXAMPLE
    .\ps_Deploy-Device.ps1 -NetworkRetryCount 10
    Runs deployment with extended network retry attempts.

.NOTES
    Version      : 2.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : PowerShell 5.1+, Admin rights
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
$ErrorActionPreference = 'Continue'

# Script-scoped variables
$script:LogDirectory = 'C:\DenkoICT\Logs'
$script:DownloadDirectory = 'C:\DenkoICT\Download'
$script:TranscriptPath = $null
$script:TranscriptStarted = $false

# ============================================================================
# BASIC FUNCTIONS (Before Custom-Functions loaded)
# ============================================================================

function Initialize-Directories {
    <#
    .SYNOPSIS
        Creates required directories for deployment.
    #>
    if (-not (Test-Path $script:LogDirectory)) {
        $null = New-Item -Path $script:LogDirectory -ItemType Directory -Force
    }
    if (-not (Test-Path $script:DownloadDirectory)) {
        $null = New-Item -Path $script:DownloadDirectory -ItemType Directory -Force
    }
}

function Start-DeploymentLogging {
    <#
    .SYNOPSIS
        Starts transcript logging for deployment.
    #>
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:TranscriptPath = Join-Path $script:LogDirectory "Deployment-$timestamp.log"

    try {
        Start-Transcript -Path $script:TranscriptPath -Force | Out-Null
        $script:TranscriptStarted = $true
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Started logging to: $script:TranscriptPath" -ForegroundColor Cyan
    } catch {
        Write-Warning "Failed to start transcript: $_"
        $script:TranscriptPath = $null
    }
}

function Stop-DeploymentLogging {
    <#
    .SYNOPSIS
        Stops transcript logging.
    #>
    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        } catch {
            # Silently ignore
        }
    }
}

function Get-DeploymentScript {
    <#
    .SYNOPSIS
        Gets a deployment script, preferring local version over GitHub download.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName
    )

    # Check for local version first
    $scriptDir = Split-Path -Parent $PSCommandPath
    $localScript = Join-Path $scriptDir $ScriptName

    if (Test-Path $localScript) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Using local script: $ScriptName" -ForegroundColor Cyan
        return $localScript
    }

    # Download from GitHub if not found locally
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Local script not found, downloading from GitHub..." -ForegroundColor Yellow

    $url = "$ScriptBaseUrl/$ScriptName"
    $localPath = Join-Path $script:DownloadDirectory $ScriptName

    $attempt = 0
    $maxRetries = 3

    do {
        $attempt++

        try {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Downloading $ScriptName (attempt $attempt/$maxRetries)..." -ForegroundColor Cyan

            $webClient = New-Object System.Net.WebClient
            $webClient.Encoding = [System.Text.Encoding]::UTF8
            $content = $webClient.DownloadString($url)

            [System.IO.File]::WriteAllText($localPath, $content, (New-Object System.Text.UTF8Encoding $false))

            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Download successful" -ForegroundColor Green
            return $localPath
        } catch {
            if ($attempt -ge $maxRetries) {
                throw "Failed to download $ScriptName after $maxRetries attempts: $_"
            }
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Download failed, retrying..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
    } while ($attempt -lt $maxRetries)
}

function Import-CustomFunctions {
    <#
    .SYNOPSIS
        Imports ps_Custom-Functions.ps1 from local or GitHub.
    #>
    [CmdletBinding()]
    param()

    $customFunctionsUrl = "$ScriptBaseUrl/ps_Custom-Functions.ps1"
    $targetPath = Join-Path $script:DownloadDirectory "ps_Custom-Functions.ps1"

    # Check for local version first
    $scriptDir = Split-Path -Parent $PSCommandPath
    $localFunctions = Join-Path $scriptDir "ps_Custom-Functions.ps1"

    $sourceFile = $null

    if (Test-Path $localFunctions) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Using local custom functions" -ForegroundColor Cyan
        $sourceFile = $localFunctions
    } else {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Downloading custom functions from GitHub..." -ForegroundColor Cyan
        $sourceFile = Get-DeploymentScript -ScriptName "ps_Custom-Functions.ps1"
    }

    # Validate syntax
    $errors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $sourceFile -Raw), [ref]$errors)

    if ($errors.Count -gt 0) {
        Write-Host "Syntax errors detected in custom functions:" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "  Line $($err.Token.StartLine): $($err.Message)" -ForegroundColor Red
        }
        throw "Custom functions file contains syntax errors"
    }

    # Import into script scope (not function scope)
    $script:CustomFunctionsPath = $sourceFile
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Custom functions imported successfully" -ForegroundColor Green
}

function Invoke-DeploymentStep {
    <#
    .SYNOPSIS
        Executes a single deployment step with proper error handling and logging.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [hashtable]$ScriptParameters,

        [switch]$RequiresNetwork,
        [switch]$RequiresStableNetwork
    )

    Write-Log "Starting: $DisplayName" -Level Info
    Set-DeploymentStepStatus -StepName $DisplayName -Status 'Running'

    try {
        # Check network if required
        if ($RequiresNetwork) {
            $networkAvailable = if ($RequiresStableNetwork) {
                Wait-ForNetworkStability -MaxRetries $NetworkRetryCount -DelaySeconds $NetworkRetryDelaySeconds -ContinuousCheck
            } else {
                Wait-ForNetworkStability -MaxRetries $NetworkRetryCount -DelaySeconds $NetworkRetryDelaySeconds
            }

            if (-not $networkAvailable) {
                Write-Log "Network not available for $DisplayName, skipping..." -Level Warning
                Set-DeploymentStepStatus -StepName $DisplayName -Status 'Skipped' -ErrorMessage 'Network not available'
                return $false
            }
        }

        # Download script
        $scriptPath = Get-DeploymentScript -ScriptName $ScriptName

        # Execute script
        Write-Log "Executing $ScriptName..." -Level Info

        # Temporarily set ErrorAction to Continue to prevent Write-Error from child scripts becoming terminating
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'

            if ($ScriptParameters -and $ScriptParameters.Count -gt 0) {
                & $scriptPath @ScriptParameters
            } else {
                & $scriptPath
            }
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        $exitCode = $LASTEXITCODE

        if ($exitCode -and $exitCode -ne 0) {
            Write-Log "Step completed with exit code: $exitCode" -Level Warning
            Set-DeploymentStepStatus -StepName $DisplayName -Status 'Success' -ExitCode $exitCode
        } else {
            Write-Log "Completed: $DisplayName" -Level Success
            Set-DeploymentStepStatus -StepName $DisplayName -Status 'Success'
        }

        return $true

    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Failed: $DisplayName" -Level Error
        Write-Log "  Error: $errorMessage" -Level Error
        Set-DeploymentStepStatus -StepName $DisplayName -Status 'Failed' -ErrorMessage $errorMessage
        return $false
    }
}

# ============================================================================
# MAIN DEPLOYMENT ORCHESTRATION
# ============================================================================

function Start-Deployment {
    <#
    .SYNOPSIS
        Main deployment orchestration logic.
    #>
    [CmdletBinding()]
    param()

    # Deployment steps configuration
    $deploymentSteps = @(
        @{
            Script = 'ps_Install-Winget.ps1'
            Name = 'WinGet Installation'
            RequiresNetwork = $true
            RequiresStableNetwork = $false
            Critical = $false
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

    $result = @{
        Success = 0
        Failed = 0
        Skipped = 0
    }

    $wingetSucceeded = $false

    Write-Log "═══════════════════════════════════════════════════════════" -Level Info
    Write-Log "  DENKO ICT DEVICE DEPLOYMENT" -Level Info
    Write-Log "═══════════════════════════════════════════════════════════" -Level Info

    foreach ($step in $deploymentSteps) {
        $parameters = if ($step.ContainsKey('Parameters')) { $step.Parameters } else { $null }

        # Track WinGet installation
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
            Write-Log "Skipping $($step.Name) - WinGet not available" -Level Warning
            Set-DeploymentStepStatus -StepName $step.Name -Status 'Skipped' -ErrorMessage 'WinGet not available'
            $result.Skipped++
            continue
        }

        # Execute step
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
            Write-Log "Step failed, continuing to next step..." -Level Warning
        }
    }

    return $result
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

try {
    # Pre-flight admin check
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script requires administrative privileges. Please run as Administrator."
    }

    # Initialize environment
    Initialize-Directories
    Start-DeploymentLogging

    # Import custom functions (critical - must succeed)
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  DENKO ICT DEVICE DEPLOYMENT" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    Import-CustomFunctions

    # Dot-source at script scope
    . $script:CustomFunctionsPath

    # Verify functions loaded
    if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
        throw "Custom functions failed to load properly. Write-Log function not found."
    }

    # Initial network check with extended retry
    Write-Log "Performing initial network check..." -Level Info
    if (-not (Test-NetworkConnectivity)) {
        Write-Log "No network connectivity detected" -Level Warning
        Write-Log "Waiting for network (up to 2 minutes)..." -Level Info

        $networkAvailable = Wait-ForNetworkStability -MaxRetries 12 -DelaySeconds 10

        if (-not $networkAvailable) {
            Write-Log "Network still unavailable - some steps will be skipped" -Level Warning
        }
    } else {
        Write-Log "Network connectivity confirmed" -Level Success
    }

    # Run deployment
    Write-Log "" -Level Info
    $deploymentResult = Start-Deployment

    # Show deployment summary
    Write-Log "" -Level Info
    Show-DeploymentSummary -Title "DENKO ICT DEPLOYMENT COMPLETE"

    Write-Log "" -Level Info
    Write-Log "Log file location: $script:TranscriptPath" -Level Info
    Write-Log "" -Level Info

    # Show instructions
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

    # Collect external logs
    Copy-ExternalLogs -LogDirectory $script:LogDirectory

    Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
    $null = [System.Console]::ReadKey($true)

    exit 0

} catch {
    Write-Host "`n[CRITICAL ERROR] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "This error prevented the deployment from starting or completing." -ForegroundColor Red

    if ($_.ScriptStackTrace) {
        Write-Host "`nStack trace:" -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    }

    Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
    $null = [System.Console]::ReadKey($true)
    exit 1

} finally {
    # Always stop logging
    Stop-DeploymentLogging
}
