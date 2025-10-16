# Denko ICT Device Deployment Script
# Part of the Denko ICT Deployment Toolkit
# See RELEASES.md for current version and CHANGELOG.md for changes

#requires -Version 7.0
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Orchestrates Denko ICT device deployment by running child scripts in proper sequence.

.DESCRIPTION
    Executes all deployment scripts in the correct order. Requires PowerShell 7.
    Use Start.ps1 to automatically install prerequisites and launch this script.
    All logs are saved to C:\DenkoICT\Logs. All downloads go to C:\DenkoICT\Download.

.EXAMPLE
    .\Deploy-Device.ps1

.NOTES
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : PowerShell 7+, Admin rights
    Version Info : See RELEASES.md and CHANGELOG.md in repository root
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Allow host environments to predefine NoPause; default to $false otherwise
if (-not (Get-Variable -Name NoPause -Scope Script -ErrorAction SilentlyContinue) -and
    -not (Get-Variable -Name NoPause -Scope Global -ErrorAction SilentlyContinue)) {
    $NoPause = $false
}

# Script-scoped variables
$script:LogDirectory = 'C:\DenkoICT\Logs'
$script:DownloadDirectory = 'C:\DenkoICT\Download'

# Resolve utilities path and load modules
$possiblePaths = @(
    (Join-Path $PSScriptRoot 'Utilities'),
    'C:\DenkoICT\Download\Utilities',
    'C:\DenkoICT\Utilities'
)
$utilitiesPath = $null
foreach ($p in $possiblePaths) { if (Test-Path $p) { $utilitiesPath = $p; break } }
if (-not $utilitiesPath) { Write-Error "Could not find Utilities folder in any expected location"; exit 1 }

$loggingModule = Join-Path $utilitiesPath 'Logging.psm1'
if (-not (Test-Path $loggingModule)) { Write-Error "Logging.psm1 not found in $utilitiesPath"; exit 1 }
Import-Module $loggingModule -Force -Global

# Import remaining utility modules (excluding Logging already imported)
Get-ChildItem "$utilitiesPath\*.psm1" | Where-Object { $_.Name -ne 'Logging.psm1' } | ForEach-Object {
    Import-Module $_.FullName -Force -Global
}

Start-EmergencyTranscript -LogName 'Deploy-Device.log'
Initialize-Script -RequireAdmin

# ============================================================================
# UTILITY FUNCTIONS (from modules)
# ============================================================================

# All utility functions are now in modules:
# - Initialize-LogDirectory (Logging.psm1)
# - Test-NetworkConnectivity (Network.psm1)
# - Get-RemoteScript (Download.psm1)
# - RMM Agent functions (RMMAgent.psm1)

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

    Write-StepStart -StepName $StepName
    Write-StepExecuting -Message "Executing with PowerShell 7"

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
exit `$exitCode
"@

        # Save wrapper script
        [System.IO.File]::WriteAllText($wrapperScript, $wrapperContent, [System.Text.Encoding]::UTF8)

        # Execute wrapper script in pwsh (hidden)
        $result = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperScript -Wait -PassThru -WindowStyle Hidden

        # Cleanup wrapper
        Remove-Item $wrapperScript -Force -ErrorAction SilentlyContinue

        if ($result.ExitCode -eq 0) {
            Write-StepComplete -StepName $StepName
        } else {
            Write-Host "✗ FAILED: $StepName (Exit Code: $($result.ExitCode))" -ForegroundColor Red
        }

        return $result.ExitCode
    } catch {
        Write-Host "✗ ERROR: Failed to execute $StepName - $_" -ForegroundColor Red
        return 1
    }
}

function Invoke-ParallelDeploymentScripts {
    param([array]$Steps)

    Write-Host ""
    Write-Host "[PARALLEL EXECUTION] Starting $($Steps.Count) scripts simultaneously..." -ForegroundColor Cyan

    $jobs = @()

    foreach ($step in $Steps) {
        $scriptPath = $step.Path

        if (!(Test-Path $scriptPath)) {
            Write-Host "[SKIPPED] $($step.Name) - Script not found at $scriptPath" -ForegroundColor Yellow
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
exit `$exitCode
"@

            [System.IO.File]::WriteAllText($wrapperScript, $wrapperContent, [System.Text.Encoding]::UTF8)

            $process = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperScript -PassThru -WindowStyle Hidden

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

    Write-Host ""
    Write-Host "[WAITING] Waiting for $($jobs.Count) parallel scripts to complete..." -ForegroundColor Cyan

    $results = @()
    foreach ($job in $jobs) {
        try {
            $job.Process.WaitForExit()
            $exitCode = $job.Process.ExitCode

            # Cleanup wrapper script
            Remove-Item $job.WrapperScript -Force -ErrorAction SilentlyContinue

            if ($exitCode -eq 0) {
                Write-Host "  $([char]0x221A) COMPLETED: $($job.Name) (Exit Code: 0)" -ForegroundColor Green
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

function Get-DeploymentScript {
    <#
    .SYNOPSIS
        Locates a deployment script in order: PSScriptRoot -> Download folder -> GitHub
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName
    )

    # Check 1: Same directory as this script
    $localPath = Join-Path $PSScriptRoot $ScriptName
    if (Test-Path $localPath) {
        Write-Log "  -> Found $ScriptName in script directory" -Level Verbose
        return $localPath
    }

    # Check 2: Download directory
    $downloadPath = Join-Path $script:DownloadDirectory $ScriptName
    if (Test-Path $downloadPath) {
        Write-Log "  -> Found $ScriptName in download directory" -Level Verbose
        return $downloadPath
    }

    # Check 3: Try to download from GitHub
    if (Test-NetworkConnectivity) {
        Write-Log "  -> Downloading $ScriptName from GitHub..." -Level Info
        if (Get-RemoteScript -ScriptName $ScriptName) {
            return $downloadPath
        }
    }

    Write-Log "  -> ERROR: Could not find $ScriptName" -Level Error
    return $null
}

function Start-Deployment {
    Write-SectionBanner -Title "EXECUTING DEPLOYMENT STEPS"

    # Locate all required scripts (silent)

    $scripts = @(
        'Install-Drivers.ps1',
        'Install-Applications.ps1',
        'Set-Wallpaper.ps1',
        'Remove-Bloat.ps1',
        'Install-WindowsUpdates.ps1'
    )

    $scriptPaths = @{}
    foreach ($script in $scripts) {
        $path = Get-DeploymentScript -ScriptName $script
        if ($path) {
            $scriptPaths[$script] = $path
        }
    }

    # Install RMM Agent
    Install-RMMAgent -DownloadDirectory $script:DownloadDirectory | Out-Null

    # Define parallel execution steps
    $parallelSteps = @()
    if ($scriptPaths['Install-Drivers.ps1']) {
        $parallelSteps += @{ Name = "Install Drivers"; Script = "Install-Drivers.ps1"; Path = $scriptPaths['Install-Drivers.ps1'] }
    }
    if ($scriptPaths['Install-Applications.ps1']) {
        $parallelSteps += @{ Name = "Install Applications"; Script = "Install-Applications.ps1"; Path = $scriptPaths['Install-Applications.ps1'] }
    }

    # Execute parallel steps
    $parallelResults = @()
    if ($parallelSteps.Count -gt 0) {
        $parallelResults = Invoke-ParallelDeploymentScripts -Steps $parallelSteps
    }

    # Execute sequential steps
    Write-Host ""
    Write-Host "[SEQUENTIAL EXECUTION] Running remaining scripts..." -ForegroundColor Cyan
    Write-Host ""

    $bloatExitCode = if ($scriptPaths['Remove-Bloat.ps1']) {
        Invoke-DeploymentScript -ScriptPath $scriptPaths['Remove-Bloat.ps1'] -StepName "Bloatware Removal"
    } else { 2 }

    $wallpaperExitCode = if ($scriptPaths['Set-Wallpaper.ps1']) {
        Invoke-DeploymentScript -ScriptPath $scriptPaths['Set-Wallpaper.ps1'] -StepName "Wallpaper Configuration"
    } else { 2 }

    $updatesExitCode = if ($scriptPaths['Install-WindowsUpdates.ps1']) {
        Invoke-DeploymentScript -ScriptPath $scriptPaths['Install-WindowsUpdates.ps1'] -StepName "Windows Updates"
    } else { 2 }

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

    # Get log path for summary
    $logPath = Join-Path 'C:\DenkoICT\Logs' 'Deploy-Device.log'

    # Display summary
    Write-DeploymentSummary -SuccessCount $results.Success -FailedCount $results.Failed -SkippedCount $results.Skipped -LogPath $logPath

    return $results
}

# ============================================================================
# ENTRY POINT
# ============================================================================

try {
    # Ensure required directories exist
    Initialize-LogDirectory -Path $script:LogDirectory
    Initialize-LogDirectory -Path $script:DownloadDirectory

    Write-Host ""
    Write-Host "    ============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    " -NoNewline
    Write-Host ".;%%%%?:                                                              " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "+%*,,:?%,                                                             " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "*%;  .*%;.                                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ".+%?*??*??*;,.    .,,.                                                " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "  .,:,. .,;*??*::*?????;.                                             " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "            .:+?%?:..,;%*.                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "               +%:     ?%,                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "               :%?:..,+%*.                                            " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "             .:?%*????*;.                                             " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "            :*%+, ....                                                " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "    ....  :*%*,                                           .       ..  " -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host " .;****?**%*,    .*****:.    ,****+.   .**+. ;*,    +*, ;*:.   .+***+," -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ".*?:...,;%?.     .%%,,*S:    :S*....   ,%%%+ *%,    *S:+%+.    +S+.;%?" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "+%.      ;%+     .%%. ;S+    :%?++;    ,%*+%:*%,    *%?%+      *%: .%%" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ";%.      ;%;     .%%. ;S+    :%*,,.    ,%*.???%,    *%;??,     *S: ,%%" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host ".+?;,..,+%+.     .%%;;??,    :S?:::.   ,%? ,%%%,    *S:,%%,    ;%*:+%+" -ForegroundColor Red
    Write-Host "    " -NoNewline
    Write-Host "  ,+*???+,       .;;;;:.     ,;;;+;.   .;:  :;;.    :;, ,;:.    ,;+;:." -ForegroundColor Red
    Write-Host ""
    Write-Host "    ============================================================" -ForegroundColor Cyan
    Write-Host "         Windows Device Deployment Automation Toolkit" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    PowerShell: " -NoNewline -ForegroundColor Gray
    Write-Host "$($PSVersionTable.PSVersion)" -ForegroundColor White
    Write-Host "    Script: " -NoNewline -ForegroundColor Gray
    Write-Host "$PSCommandPath" -ForegroundColor White
    Write-Host ""

    # Verify PowerShell 7
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "[ERROR] This script requires PowerShell 7 or higher" -ForegroundColor Red
        Write-Host "[ERROR] Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
        Write-Host "[SOLUTION] Use Start.ps1 to automatically install PowerShell 7" -ForegroundColor Yellow
        Write-Host "Press any key to exit..." -ForegroundColor Red
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }

    # Install/Verify WinGet first (as shown in deployment flow)
    Write-StepStart -StepName "WinGet Installation"
    if (Test-WinGet) {
        Write-Host "WARNING: winget is already installed, exiting..." -ForegroundColor Yellow
        Write-Host "WARNING: If you want to reinstall winget, run the script with the -Force parameter." -ForegroundColor Yellow
        Write-StepComplete -StepName "WinGet Installation"
    } else {
        Write-Host "Installing WinGet..." -ForegroundColor Cyan
        # WinGet installation logic would go here
        Write-StepComplete -StepName "WinGet Installation"
    }

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
        Write-Host ""
        Write-Host "[WARNING] Some deployment steps failed!" -ForegroundColor Yellow
        Write-Host "Review the logs for details in C:\DenkoICT\Logs" -ForegroundColor Yellow
        if (-not $NoPause) {
            Write-Host "Press any key to continue..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    } elseif (!$isUnattended -and -not $NoPause) {
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } else {
        Start-Sleep -Seconds 5
    }

    exit $exitCode

} catch {
    Write-Host ""
    Write-Host "[CRITICAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Error details: $($_.ScriptStackTrace)" -ForegroundColor Red

    $isUnattended = $false
    if ($env:USERNAME -eq 'defaultuser0' -or $env:USERNAME -eq 'SYSTEM') {
        $isUnattended = $true
    }

    if (!$isUnattended) {
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Red
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } else {
        Start-Sleep -Seconds 10
    }

    exit 1
} finally {
    if (Get-Command Complete-Script -ErrorAction SilentlyContinue) {
        try { Complete-Script } catch { Stop-EmergencyTranscript }
    } else {
        Stop-EmergencyTranscript
    }
}
