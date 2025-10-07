<#PSScriptInfo

.VERSION 3.0.0

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
[Version 1.2.2] - Enf        if (Test-PowerShell7) {
            Write-Host "\nPowerShell 7 detected. Restarting deployment in PS7..." -ForegroundColor Cyan
            Stop-DeploymentLogging
            
            $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
            $pwshPath = if ($pwshCommand -and $pwshCommand.Source) { $pwshCommand.Source } else { "$env:ProgramFiles\PowerShell\7\pwsh.exe" }\DenkoICT\Download for all downloads.
[Version 1.3.0] - Improved execution order, network stability checks with retries, better handling for network-dependent operations
[Version 2.0.0] - Major refactor: Simplified orchestration, removed inline functions, better error handling, cleaner network retry logic
[Version 2.1.0] - Resolved conflicts, improved PS7 switching, better error handling
[Version 2.2.0] - Fixed log naming, improved agent handling, child scripts in separate windows, reduced WinGet messages
[Version 3.0.0] - Removed PowerShell 7 installation logic. Now requires PowerShell 7 to run. Use ps_Init-Deployment.ps1 as entry point.
#>

#requires -Version 7.0
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Orchestrates Denko ICT device deployment by running child scripts in proper sequence.

.DESCRIPTION
    Executes all deployment scripts in the correct order. Requires PowerShell 7.
    Use ps_Init-Deployment.ps1 to automatically install prerequisites and launch this script.
    All logs are saved to C:\DenkoICT\Logs. All downloads go to C:\DenkoICT\Download.

.PARAMETER ScriptBaseUrl
    Base URL for downloading scripts from GitHub.

.EXAMPLE
    .\ps_Deploy-Device.ps1
    Runs full deployment (requires PowerShell 7).

.NOTES
    Version      : 3.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : PowerShell 7+, Admin rights
#>

[CmdletBinding()]
param (
    [string]$ScriptBaseUrl = "https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts",
    [int]$NetworkRetryCount = 5,
    [int]$NetworkRetryDelaySeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Script-scoped variables
$script:LogDirectory = 'C:\DenkoICT\Logs'
$script:DownloadDirectory = 'C:\DenkoICT\Download'
$script:TranscriptPath = $null

# ============================================================================
# BASIC FUNCTIONS
# ============================================================================

function Initialize-Directories {
    @($script:LogDirectory, $script:DownloadDirectory) | ForEach-Object {
        if (!(Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }
}

function Start-DeploymentLogging {
    $script:TranscriptPath = Join-Path $script:LogDirectory "ps_Deploy-Device.ps1.log"

    try {
        Start-Transcript -Path $script:TranscriptPath -Force | Out-Null
        Write-Host "[INFO] Logging to: $script:TranscriptPath" -ForegroundColor Cyan
    } catch {
        Write-Warning "Failed to start transcript: $_"
    }
}

function Stop-DeploymentLogging {
    try {
        Stop-Transcript | Out-Null
    } catch {
        # Silently ignore
    }
}

function Test-NetworkConnection {
    param(
        [string]$TestUrl = "https://github.com",
        [int]$MaxRetries = $NetworkRetryCount,
        [int]$RetryDelay = $NetworkRetryDelaySeconds
    )

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Host "Testing network connectivity (attempt $i/$MaxRetries)..." -ForegroundColor Cyan
            $response = Invoke-WebRequest -Uri $TestUrl -Method Head -UseBasicParsing -TimeoutSec 10
            if ($response.StatusCode -eq 200) {
                Write-Host "Network connection verified" -ForegroundColor Green
                return $true
            }
        } catch {
            if ($i -eq $MaxRetries) {
                Write-Host "Network connection failed after $MaxRetries attempts" -ForegroundColor Red
                return $false
            }
            Write-Host "Network test failed, retrying in $RetryDelay seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds $RetryDelay
        }
    }
    return $false
}

function Get-ScriptFromGitHub {
    param(
        [string]$ScriptName,
        [int]$MaxRetries = 3
    )

    $url = "$ScriptBaseUrl/$ScriptName"
    $localPath = Join-Path $script:DownloadDirectory $ScriptName

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Host "Downloading $ScriptName (attempt $i/$MaxRetries)..." -ForegroundColor Cyan
            $webClient = New-Object System.Net.WebClient
            $webClient.Encoding = [System.Text.Encoding]::UTF8
            $content = $webClient.DownloadString($url)

            if (![string]::IsNullOrWhiteSpace($content)) {
                [System.IO.File]::WriteAllText($localPath, $content, (New-Object System.Text.UTF8Encoding $false))
                Write-Host "Downloaded: $ScriptName" -ForegroundColor Green
                return $true
            }
        } catch {
            if ($i -eq $MaxRetries) {
                Write-Host "Failed to download $ScriptName : $_" -ForegroundColor Red
                return $false
            }
            Start-Sleep -Seconds 5
        }
    }
    return $false
}

# ============================================================================
# RMM AGENT FUNCTIONS
# ============================================================================

function Test-RMMAgentInstalled {
    $agentExePath = "C:\Program Files (x86)\CentraStage\CagService.exe"
    $fileExists = Test-Path $agentExePath

    $serviceExists = $false
    try {
        $service = Get-Service -Name "CagService" -ErrorAction SilentlyContinue
        if ($service) {
            $serviceExists = $true
        } else {
            $service = Get-Service | Where-Object { $_.DisplayName -like "*Datto RMM*" }
            if ($service) {
                $serviceExists = $true
            }
        }
    } catch {
        # Service not found
    }

    if ($fileExists -and $serviceExists) {
        Write-Host "[RMM] Agent verified: Service running and files present" -ForegroundColor Green
        return $true
    } elseif ($fileExists) {
        Write-Host "[RMM] Agent files present but service not detected" -ForegroundColor Yellow
        return $true
    } elseif ($serviceExists) {
        Write-Host "[RMM] Agent service detected" -ForegroundColor Green
        return $true
    }

    return $false
}

function Wait-ForRMMAgentInstallation {
    param([int]$MaxWaitSeconds = 30)

    Write-Host "[RMM] Waiting for agent installation to complete (max $MaxWaitSeconds seconds)..." -ForegroundColor Cyan

    for ($i = 1; $i -le $MaxWaitSeconds; $i++) {
        if (Test-RMMAgentInstalled) {
            Write-Host "[RMM] Agent installation confirmed after $i seconds" -ForegroundColor Green
            return $true
        }

        if ($i -lt $MaxWaitSeconds) {
            Write-Host "  Checking... ($i/$MaxWaitSeconds)" -ForegroundColor Gray
            Start-Sleep -Seconds 1
        }
    }

    Write-Host "[RMM] Agent installation verification failed after $MaxWaitSeconds seconds" -ForegroundColor Red
    return $false
}

function Find-AndPrepareRMMAgent {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  PREPARING RMM AGENT" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    $targetAgentPath = Join-Path $script:DownloadDirectory 'Agent.exe'

    if (Test-Path $targetAgentPath) {
        Write-Host "[RMM] Agent.exe already present in Download folder" -ForegroundColor Green
        return $targetAgentPath
    }

    $oldAgentPath = Join-Path 'C:\DenkoICT' 'RMM-Agent.exe'
    if (Test-Path $oldAgentPath) {
        Write-Host "[RMM] Found RMM-Agent.exe, moving to Download folder as Agent.exe..." -ForegroundColor Cyan
        try {
            Move-Item -Path $oldAgentPath -Destination $targetAgentPath -Force
            Write-Host "[RMM] Agent moved successfully" -ForegroundColor Green
            return $targetAgentPath
        } catch {
            Write-Host "[RMM] Failed to move agent: $_" -ForegroundColor Red
        }
    }

    $searchPaths = @('C:\DenkoICT', 'D:\', 'E:\', 'F:\', 'G:\', 'H:\')
    foreach ($path in $searchPaths) {
        if (!(Test-Path $path)) { continue }

        $agents = Get-ChildItem -Path $path -Filter "*Agent*.exe" -File -ErrorAction SilentlyContinue
        if ($agents) {
            $agent = $agents | Select-Object -First 1
            Write-Host "[RMM] Agent found: $($agent.FullName)" -ForegroundColor Green
            Write-Host "[RMM] Moving to Download folder as Agent.exe..." -ForegroundColor Cyan

            try {
                Copy-Item -Path $agent.FullName -Destination $targetAgentPath -Force
                Write-Host "[RMM] Agent copied successfully" -ForegroundColor Green
                return $targetAgentPath
            } catch {
                Write-Host "[RMM] Failed to copy agent: $_" -ForegroundColor Red
            }
        }
    }

    Write-Host "[RMM] No RMM agent found" -ForegroundColor Yellow
    return $null
}

function Install-RMMAgent {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  INSTALLING RMM AGENT" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    if (Test-RMMAgentInstalled) {
        Write-Host "[RMM] Agent is already installed" -ForegroundColor Green
        return $true
    }

    $agentPath = Find-AndPrepareRMMAgent

    if (!$agentPath -or !(Test-Path $agentPath)) {
        Write-Host "[RMM] Cannot install - Agent.exe not found" -ForegroundColor Yellow
        return $false
    }

    Write-Host "[RMM] Starting agent installation..." -ForegroundColor Cyan
    Write-Host "[RMM] Executing: $agentPath" -ForegroundColor Gray

    try {
        Start-Process -FilePath $agentPath -ArgumentList "/S", "/v/qn" -PassThru -NoNewWindow | Out-Null

        $installed = Wait-ForRMMAgentInstallation -MaxWaitSeconds 30

        if ($installed) {
            Write-Host "[RMM] Agent installation successful" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[RMM] Agent installation failed or timed out" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "[RMM] Agent installation error: $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# SCRIPT EXECUTION FUNCTIONS
# ============================================================================

function Invoke-DeploymentScript {
    param(
        [string]$ScriptPath,
        [string]$StepName
    )

    if (!(Test-Path $ScriptPath)) {
        Write-Host "[ERROR] Script not found: $ScriptPath" -ForegroundColor Red
        return 1
    }

    Write-Host "[RUNNING] $StepName..." -ForegroundColor Cyan
    Write-Host "  -> Script: $ScriptPath" -ForegroundColor Gray

    try {
        # Create a temporary wrapper script to handle the execution
        $wrapperScript = Join-Path $env:TEMP "wrapper_$([guid]::NewGuid()).ps1"

        # Build wrapper script content with proper escaping
        $wrapperContent = @"
`$Host.UI.RawUI.WindowTitle = '$StepName'
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  $StepName' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

& '$ScriptPath'
`$exitCode = `$LASTEXITCODE

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
if (`$exitCode -eq 0) {
    Write-Host 'Script completed successfully. Exit code: 0' -ForegroundColor Green
} else {
    Write-Host "Script completed with errors. Exit code: `$exitCode" -ForegroundColor Red
}
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Press any key to close this window...' -ForegroundColor Gray
`$null = [Console]::ReadKey(`$true)
exit `$exitCode
"@

        # Save wrapper script
        [System.IO.File]::WriteAllText($wrapperScript, $wrapperContent, [System.Text.Encoding]::UTF8)

        # Execute wrapper script in pwsh
        $result = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperScript -Wait -PassThru

        # Cleanup wrapper
        Remove-Item $wrapperScript -Force -ErrorAction SilentlyContinue

        if ($result.ExitCode -eq 0) {
            Write-Host "  ✓ SUCCESS: $StepName (Exit Code: 0)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ FAILED: $StepName (Exit Code: $($result.ExitCode))" -ForegroundColor Red
        }

        return $result.ExitCode
    } catch {
        Write-Host "  ✗ ERROR: Failed to execute $StepName - $_" -ForegroundColor Red
        return 1
    }
}

function Invoke-ParallelDeploymentScripts {
    param([array]$Steps)

    Write-Host "`n[PARALLEL EXECUTION] Starting $($Steps.Count) scripts simultaneously..." -ForegroundColor Cyan

    $jobs = @()

    foreach ($step in $Steps) {
        $scriptPath = Join-Path $script:DownloadDirectory $step.Script

        if (!(Test-Path $scriptPath)) {
            Write-Host "[SKIPPED] $($step.Name) - Script not found" -ForegroundColor Yellow
            continue
        }

        Write-Host "  -> Launching: $($step.Name)" -ForegroundColor Gray

        try {
            # Create wrapper script for this step
            $wrapperScript = Join-Path $env:TEMP "wrapper_$([guid]::NewGuid()).ps1"

            $wrapperContent = @"
`$Host.UI.RawUI.WindowTitle = '$($step.Name)'
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  $($step.Name)' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

& '$scriptPath'
`$exitCode = `$LASTEXITCODE

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
if (`$exitCode -eq 0) {
    Write-Host 'Script completed successfully. Exit code: 0' -ForegroundColor Green
} else {
    Write-Host "Script completed with errors. Exit code: `$exitCode" -ForegroundColor Red
}
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Press any key to close this window...' -ForegroundColor Gray
`$null = [Console]::ReadKey(`$true)
exit `$exitCode
"@

            [System.IO.File]::WriteAllText($wrapperScript, $wrapperContent, [System.Text.Encoding]::UTF8)

            $process = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperScript -PassThru

            $jobs += @{
                Process = $process
                Name = $step.Name
                Script = $step.Script
                WrapperScript = $wrapperScript
            }
        } catch {
            Write-Host "  ✗ ERROR: Failed to start $($step.Name) - $_" -ForegroundColor Red
        }
    }

    if ($jobs.Count -eq 0) {
        Write-Host "[WARNING] No scripts were started" -ForegroundColor Yellow
        return @()
    }

    Write-Host "`n[WAITING] Waiting for $($jobs.Count) parallel scripts to complete..." -ForegroundColor Cyan

    $results = @()
    foreach ($job in $jobs) {
        try {
            $job.Process.WaitForExit()
            $exitCode = $job.Process.ExitCode

            # Cleanup wrapper script
            Remove-Item $job.WrapperScript -Force -ErrorAction SilentlyContinue

            if ($exitCode -eq 0) {
                Write-Host "  ✓ COMPLETED: $($job.Name) (Exit Code: 0)" -ForegroundColor Green
            } else {
                Write-Host "  ✗ FAILED: $($job.Name) (Exit Code: $exitCode)" -ForegroundColor Red
            }

            $results += @{
                Name = $job.Name
                Script = $job.Script
                ExitCode = $exitCode
                Success = ($exitCode -eq 0)
            }
        } catch {
            Write-Host "  ✗ ERROR: $($job.Name) - $_" -ForegroundColor Red
            $results += @{
                Name = $job.Name
                Script = $job.Script
                ExitCode = 1
                Success = $false
            }
        }
    }

    return $results
}

# ============================================================================
# MAIN DEPLOYMENT ORCHESTRATION
# ============================================================================

function Start-Deployment {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  STARTING DEPLOYMENT" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # Download all required scripts
    Write-Host "[SETUP] Downloading deployment scripts..." -ForegroundColor Cyan

    $scripts = @(
        'ps_Custom-Functions.ps1',
        'ps_Install-Drivers.ps1',
        'ps_Install-Applications.ps1',
        'ps_Set-Wallpaper.ps1',
        'ps_Remove-Bloat.ps1',
        'ps_Install-WindowsUpdates.ps1'
    )

    $hasNetwork = Test-NetworkConnection

    if (!$hasNetwork) {
        Write-Host "[WARNING] No network connection - will use local scripts only" -ForegroundColor Yellow
    } else {
        foreach ($script in $scripts) {
            $localPath = Join-Path $script:DownloadDirectory $script
            if (!(Test-Path $localPath)) {
                Get-ScriptFromGitHub -ScriptName $script | Out-Null
            } else {
                Write-Host "  -> $script already present" -ForegroundColor Gray
            }
        }
    }

    # Install RMM Agent
    Install-RMMAgent | Out-Null

    # Define parallel execution steps
    $parallelSteps = @(
        @{ Name = "Install Drivers"; Script = "ps_Install-Drivers.ps1" },
        @{ Name = "Install Applications"; Script = "ps_Install-Applications.ps1" }
    )

    # Execute parallel steps
    $parallelResults = Invoke-ParallelDeploymentScripts -Steps $parallelSteps

    # Execute sequential steps
    Write-Host "`n[SEQUENTIAL EXECUTION] Running remaining scripts..." -ForegroundColor Cyan

    $bloatExitCode = Invoke-DeploymentScript -ScriptPath (Join-Path $script:DownloadDirectory "ps_Remove-Bloat.ps1") -StepName "Remove Bloatware"
    $wallpaperExitCode = Invoke-DeploymentScript -ScriptPath (Join-Path $script:DownloadDirectory "ps_Set-Wallpaper.ps1") -StepName "Set Wallpaper"
    $updatesExitCode = Invoke-DeploymentScript -ScriptPath (Join-Path $script:DownloadDirectory "ps_Install-WindowsUpdates.ps1") -StepName "Install Windows Updates"

    # Compile results
    $results = @{
        Success = 0
        Failed = 0
        Skipped = 0
        Details = @()
    }

    # Count parallel results
    foreach ($result in $parallelResults) {
        if ($result.Success) {
            $results.Success++
        } else {
            $results.Failed++
        }
        $results.Details += $result
    }

    # Count sequential results
    if ($bloatExitCode -eq 0) { $results.Success++ } else { $results.Failed++ }
    if ($wallpaperExitCode -eq 0) { $results.Success++ } else { $results.Failed++ }
    if ($updatesExitCode -eq 0) { $results.Success++ } else { $results.Failed++ }

    # Summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total Steps: $($results.Success + $results.Failed)" -ForegroundColor Cyan
    Write-Host "  Success: $($results.Success)" -ForegroundColor Green
    Write-Host "  Failed: $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })
    Write-Host "  Skipped: $($results.Skipped)" -ForegroundColor $(if ($results.Skipped -gt 0) { 'Yellow' } else { 'Gray' })
    Write-Host "`nLog File: $script:TranscriptPath" -ForegroundColor Cyan

    return $results
}

# ============================================================================
# ENTRY POINT
# ============================================================================

try {
    Initialize-Directories
    Start-DeploymentLogging

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  DENKO ICT DEVICE DEPLOYMENT" -ForegroundColor Cyan
    Write-Host "  Version 3.0.0" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
    Write-Host "Script Path: $PSCommandPath" -ForegroundColor Cyan

    # Verify PowerShell 7
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "`n[ERROR] This script requires PowerShell 7 or higher" -ForegroundColor Red
        Write-Host "[ERROR] Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
        Write-Host "`n[SOLUTION] Use ps_Init-Deployment.ps1 to automatically install PowerShell 7" -ForegroundColor Yellow
        Write-Host "`nPress any key to exit..." -ForegroundColor Red
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }

    Write-Host "`n[VERIFIED] Running in PowerShell 7" -ForegroundColor Green

    # Run main deployment
    $deploymentResults = Start-Deployment

    # Determine exit code
    $failedCount = 0
    if ($deploymentResults -and $deploymentResults.Failed) {
        $failedCount = $deploymentResults.Failed
    }

    $exitCode = 0
    if ($failedCount -gt 0) {
        $exitCode = 1
    }

    # Check if unattended
    $isUnattended = $false
    if ($env:USERNAME -eq 'defaultuser0' -or $env:USERNAME -eq 'SYSTEM') {
        $isUnattended = $true
    }

    if (!$isUnattended -and $failedCount -gt 0) {
        Write-Host "`n[WARNING] Some deployment steps failed!" -ForegroundColor Yellow
        Write-Host "Review the logs for details: $script:TranscriptPath" -ForegroundColor Yellow
        Write-Host "`nPress any key to continue..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } elseif (!$isUnattended) {
        Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } else {
        Start-Sleep -Seconds 5
    }

    exit $exitCode

} catch {
    Write-Host "`n[CRITICAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Error details: $($_.ScriptStackTrace)" -ForegroundColor Red

    $isUnattended = $false
    if ($env:USERNAME -eq 'defaultuser0' -or $env:USERNAME -eq 'SYSTEM') {
        $isUnattended = $true
    }

    if (!$isUnattended) {
        Write-Host "`nPress any key to exit..." -ForegroundColor Red
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } else {
        Start-Sleep -Seconds 10
    }

    exit 1
} finally {
    Stop-DeploymentLogging
}
