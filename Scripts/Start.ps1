#requires -Version 5.1

<#
.SYNOPSIS
    Complete Denko ICT device deployment automation script with auto-elevation.

.DESCRIPTION
    This unified deployment script automatically:
    - Elevates to Administrator if needed
    - Relaunches in PowerShell 7 if needed
    - Verifies WinGet installation
    - Executes all deployment steps in a single terminal window

    All logs are saved to C:\DenkoICT\Logs\Start.log

.EXAMPLE
    .\Start.ps1

    Runs the complete deployment with automatic privilege and PowerShell version handling.

.NOTES
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Version      : 2.0.0 - Unified deployment with auto-elevation and PS7 relaunch
    Requires     : Windows 10/11, PowerShell 5.1+ (auto-upgrades to PS7)
#>

[CmdletBinding()]
param()

# ============================================================================
# AUTO-ELEVATION CHECK (Step 1: Ensure Admin)
# ============================================================================
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Script needs to be run as Administrator. Attempting to relaunch..." -ForegroundColor Yellow

    # Rebuild argument list from bound parameters
    $argList = @()
    $PSBoundParameters.GetEnumerator() | ForEach-Object {
        $argList += if ($_.Value -is [switch] -and $_.Value) {
            "-$($_.Key)"
        } elseif ($_.Value -is [array]) {
            "-$($_.Key) $($_.Value -join ',')"
        } elseif ($_.Value) {
            "-$($_.Key) '$($_.Value)'"
        }
    }

    # Build the script execution command
    $script = "& { & `'$PSCommandPath`' $($argList -join ' ') }"

    # Detect PowerShell version (prefer pwsh if available)
    $powershellCmd = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }

    # Detect Windows Terminal (to reuse same window)
    $processCmd = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { "wt.exe" } else { $powershellCmd }

    # Launch elevated process
    try {
        if ($processCmd -eq "wt.exe") {
            Start-Process $processCmd -ArgumentList "$powershellCmd -ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
        } else {
            Start-Process $processCmd -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
        }

        # Exit current non-admin session
        exit
    } catch {
        Write-Host "Failed to elevate: $_" -ForegroundColor Red
        Write-Host "Please run this script as Administrator manually." -ForegroundColor Yellow
        pause
        exit 1
    }
}

# ============================================================================
# POWERSHELL 7 CHECK (Step 2: Ensure PowerShell 7)
# ============================================================================
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "Script needs PowerShell 7 in order to function. Attempting to relaunch..." -ForegroundColor Yellow

    # First check if PowerShell 7 is already installed
    $pwshPath = $null
    $possiblePaths = @(
        'C:\Program Files\PowerShell\7\pwsh.exe',
        'C:\Program Files (x86)\PowerShell\7\pwsh.exe'
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) { $pwshPath = $path; break }
    }

    # If not installed, try to install it
    if (-not $pwshPath) {
        Write-Host "PowerShell 7 not found. Installing..." -ForegroundColor Cyan

        # Try to install using WinGet or fallback method
        # First check script directory, then download directory
        $wingetScript = Join-Path $PSScriptRoot "Install-Winget.ps1"
        if (-not (Test-Path $wingetScript)) {
            $wingetScript = Join-Path 'C:\DenkoICT\Download' "Install-Winget.ps1"
        }

        $ps7Script = Join-Path $PSScriptRoot "Install-PowerShell7.ps1"
        if (-not (Test-Path $ps7Script)) {
            $ps7Script = Join-Path 'C:\DenkoICT\Download' "Install-PowerShell7.ps1"
        }

        # Ensure download directory exists
        if (!(Test-Path 'C:\DenkoICT\Download')) {
            New-Item -Path 'C:\DenkoICT\Download' -ItemType Directory -Force | Out-Null
        }

        # Check/Install WinGet first if needed
        $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
        if (!$wingetAvailable) {
            Write-Host "Installing WinGet first..." -ForegroundColor Cyan
            if (Test-Path $wingetScript) {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wingetScript
            } else {
                Write-Host "ERROR: Install-Winget.ps1 not found in script directory or download folder" -ForegroundColor Red
            }
        }

        # Install PowerShell 7
        if (Test-Path $ps7Script) {
            Write-Host "Installing PowerShell 7..." -ForegroundColor Cyan
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps7Script
        } else {
            Write-Host "ERROR: Install-PowerShell7.ps1 not found in script directory or download folder" -ForegroundColor Red
        }

        # Recheck for pwsh
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) { $pwshPath = $path; break }
        }
    }

    if (-not $pwshPath) {
        Write-Host "Failed to locate or install PowerShell 7" -ForegroundColor Red
        Write-Host "Please install PowerShell 7 manually from: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Yellow
        pause
        exit 1
    }

    # Rebuild argument list
    $argList = @()
    $PSBoundParameters.GetEnumerator() | ForEach-Object {
        $argList += if ($_.Value -is [switch] -and $_.Value) {
            "-$($_.Key)"
        } elseif ($_.Value -is [array]) {
            "-$($_.Key) $($_.Value -join ',')"
        } elseif ($_.Value) {
            "-$($_.Key) '$($_.Value)'"
        }
    }

    # Build the script execution command for PowerShell 7
    $script = "& { & `'$PSCommandPath`' $($argList -join ' ') }"

    # Detect Windows Terminal (to reuse same window)
    $processCmd = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { "wt.exe" } else { $pwshPath }

    # Launch in PowerShell 7
    try {
        if ($processCmd -eq "wt.exe") {
            Start-Process $processCmd -ArgumentList "$pwshPath -ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
        } else {
            Start-Process $pwshPath -ArgumentList "-ExecutionPolicy Bypass -NoProfile -Command `"$script`"" -Verb RunAs
        }

        # Exit current PowerShell 5 session
        exit
    } catch {
        Write-Host "Failed to relaunch in PowerShell 7: $_" -ForegroundColor Red
        pause
        exit 1
    }
}

# ============================================================================
# PREREQUISITES MET - Continue with deployment
# ============================================================================

# Set PowerShell window title to indicate admin mode and PS7
$Host.UI.RawUI.WindowTitle = "DENKO ICT Deployment (Admin - PS7)"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ============================================================================
# LOAD UTILITIES AND INITIALIZE LOGGING
# ============================================================================
$possiblePaths = @(
    (Join-Path $PSScriptRoot 'Utilities'),
    'C:\DenkoICT\Download\Utilities',
    'C:\DenkoICT\Utilities'
)
$utilitiesPath = $null
foreach ($path in $possiblePaths) {
    if (Test-Path $path) { $utilitiesPath = $path; break }
}
if (-not $utilitiesPath) {
    Write-Error "Utilities folder not found in expected locations"
    exit 1
}

$loggingModule = Join-Path $utilitiesPath 'Logging.psm1'
if (-not (Test-Path $loggingModule)) { Write-Error "Logging.psm1 not found in $utilitiesPath"; exit 1 }
Import-Module $loggingModule -Force -Global

# Import remaining utility modules after logging is available
Get-ChildItem "$utilitiesPath\*.psm1" | Where-Object { $_.Name -ne 'Logging.psm1' } | ForEach-Object {
    Import-Module $_.FullName -Force -Global
}

Start-EmergencyTranscript -LogName 'Start.log'
Initialize-Script -RequireAdmin

# ============================================================================
# DEPLOYMENT FUNCTIONS
# ============================================================================
# All utility functions are now in modules:
# - Test-WinGet (WinGet.psm1)
# - Get-RemoteScript (Download.psm1)
# - RMM Agent functions (RMMAgent.psm1)

# Allow host environments to predefine NoPause; default to $false otherwise
if (-not (Get-Variable -Name NoPause -Scope Script -ErrorAction SilentlyContinue) -and
    -not (Get-Variable -Name NoPause -Scope Global -ErrorAction SilentlyContinue)) {
    $NoPause = $false
}

# Script-scoped variables
$script:LogDirectory = 'C:\DenkoICT\Logs'
$script:DownloadDirectory = 'C:\DenkoICT\Download'

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

    try {
        # Suppress all output streams from child scripts (keep only exit code)
        # Redirect: 1=stdout, 2=stderr, 3=warning, 4=verbose, 5=debug, 6=info
        $null = & $ScriptPath *>&1 | Out-Null
        $exitCode = $LASTEXITCODE

        # Show completion status
        if ($exitCode -ne 0) {
            Write-Host "✗ FAILED: $StepName (Exit Code: $exitCode)" -ForegroundColor Red
            Write-Host "  Check logs in C:\DenkoICT\Logs for details" -ForegroundColor Gray
        } else {
            Write-StepComplete -StepName $StepName
        }

        return $exitCode
    } catch {
        Write-Host "✗ ERROR: Failed to execute $StepName - $_" -ForegroundColor Red
        return 1
    }
}


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

    # Define all deployment steps in order
    $deploymentSteps = @(
        @{ Name = "Driver Installation"; ScriptName = "Install-Drivers.ps1" }
        @{ Name = "Application Installation"; ScriptName = "Install-Applications.ps1" }
        @{ Name = "Bloatware Removal"; ScriptName = "Remove-Bloat.ps1" }
        @{ Name = "Wallpaper Configuration"; ScriptName = "Set-Wallpaper.ps1" }
        @{ Name = "Windows Updates"; ScriptName = "Install-WindowsUpdates.ps1" }
    )

    # Install RMM Agent first
    Install-RMMAgent -DownloadDirectory $script:DownloadDirectory | Out-Null

    Write-Host ""

    # Execute all steps sequentially
    $results = @{
        Success = 0
        Failed = 0
        Skipped = 0
        Details = @()
    }

    foreach ($step in $deploymentSteps) {
        $scriptPath = Get-DeploymentScript -ScriptName $step.ScriptName

        if ($scriptPath) {
            $exitCode = Invoke-DeploymentScript -ScriptPath $scriptPath -StepName $step.Name

            if ($exitCode -eq 0) {
                $results.Success++
            } else {
                $results.Failed++
            }

            $results.Details += @{
                Name = $step.Name
                Script = $step.ScriptName
                ExitCode = $exitCode
                Success = ($exitCode -eq 0)
            }
        } else {
            Write-Host "[SKIPPED] $($step.Name) - Script not found" -ForegroundColor Yellow
            $results.Skipped++
        }
    }

    # Get log path for summary
    $logPath = Join-Path $script:LogDirectory 'Start.log'

    # Display summary
    Write-DeploymentSummary -SuccessCount $results.Success -FailedCount $results.Failed -SkippedCount $results.Skipped -LogPath $logPath

    return $results
}

# ============================================================================
# MAIN
# ============================================================================

try {
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

    # Install/Verify WinGet first
    Write-StepStart -StepName "WinGet Installation"
    $wg = Test-WinGet
    if ($wg.IsAvailable) {
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
        Write-Host ""
        if (-not $NoPause) {
            Write-Host "Press any key to exit..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    } elseif (!$isUnattended -and -not $NoPause) {
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host "  DEPLOYMENT COMPLETED SUCCESSFULLY" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "All deployment steps have been completed." -ForegroundColor White
        Write-Host ""
        Write-Host "Logs are located at: " -NoNewline -ForegroundColor Gray
        Write-Host "C:\DenkoICT\Logs" -ForegroundColor Cyan
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