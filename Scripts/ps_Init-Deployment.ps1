<#PSScriptInfo

.VERSION 1.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Deployment Initialization

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Combined WinGet + PowerShell 7 installer that launches deployment.
#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Initializes device deployment by installing WinGet and PowerShell 7, then launching ps_Deploy-Device.ps1.

.DESCRIPTION
    This script is designed to run on a fresh Windows installation with PowerShell 5.1.
    It installs WinGet and PowerShell 7 as prerequisites, then launches the main deployment script.
    All logs are saved to C:\DenkoICT\Logs. All downloads go to C:\DenkoICT\Download.

.PARAMETER ScriptBaseUrl
    Base URL for downloading scripts from GitHub.

.EXAMPLE
    .\ps_Init-Deployment.ps1
    Runs initialization and starts full deployment.

.NOTES
    Version      : 1.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : PowerShell 5.1+, Admin rights
#>

[CmdletBinding()]
param (
    [string]$ScriptBaseUrl = "https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts"
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

function Start-InitLogging {
    $script:TranscriptPath = Join-Path $script:LogDirectory "ps_Init-Deployment.ps1.log"

    try {
        Start-Transcript -Path $script:TranscriptPath -Force | Out-Null
        Write-Host "[INFO] Logging to: $script:TranscriptPath" -ForegroundColor Cyan
    } catch {
        Write-Warning "Failed to start transcript: $_"
    }
}

function Stop-InitLogging {
    try {
        Stop-Transcript | Out-Null
    } catch {
        # Silently ignore
    }
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
# WINGET FUNCTIONS
# ============================================================================

function Test-WinGetAvailable {
    try {
        $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetPath) {
            $version = winget --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[WINGET] Available - Version: $version" -ForegroundColor Green
                return $true
            }
        }
        return $false
    } catch {
        return $false
    }
}

function Install-WinGet {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  INSTALLING WINGET" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    $wingetScript = Join-Path $script:DownloadDirectory "ps_Install-Winget.ps1"

    if (!(Test-Path $wingetScript)) {
        Write-Host "[ERROR] ps_Install-Winget.ps1 not found, downloading..." -ForegroundColor Yellow
        $downloaded = Get-ScriptFromGitHub -ScriptName "ps_Install-Winget.ps1"
        if (!$downloaded) {
            Write-Host "[ERROR] Failed to download ps_Install-Winget.ps1" -ForegroundColor Red
            return $false
        }
    }

    Write-Host "[WINGET] Executing ps_Install-Winget.ps1..." -ForegroundColor Cyan
    $result = Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$wingetScript`"" -Wait -PassThru -WindowStyle Normal

    if ($result.ExitCode -eq 0) {
        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        Start-Sleep -Seconds 2
        return Test-WinGetAvailable
    }
    return $false
}

# ============================================================================
# POWERSHELL 7 FUNCTIONS
# ============================================================================

function Test-PowerShell7Installed {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Host "[PS7] Already running in PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green
        return $true
    }

    $pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshPath) {
        Write-Host "[PS7] Found at: $($pwshPath.Source)" -ForegroundColor Green
        return $true
    }

    $commonPaths = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            Write-Host "[PS7] Found at: $path" -ForegroundColor Green
            return $true
        }
    }

    return $false
}

function Install-PowerShell7 {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  INSTALLING POWERSHELL 7" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    $ps7Script = Join-Path $script:DownloadDirectory "ps_Install-PowerShell7.ps1"

    if (!(Test-Path $ps7Script)) {
        Write-Host "[ERROR] ps_Install-PowerShell7.ps1 not found, downloading..." -ForegroundColor Yellow
        $downloaded = Get-ScriptFromGitHub -ScriptName "ps_Install-PowerShell7.ps1"
        if (!$downloaded) {
            Write-Host "[ERROR] Failed to download ps_Install-PowerShell7.ps1" -ForegroundColor Red
            return $false
        }
    }

    Write-Host "[PS7] Executing ps_Install-PowerShell7.ps1..." -ForegroundColor Cyan
    $result = Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ps7Script`"" -Wait -PassThru -WindowStyle Normal

    if ($result.ExitCode -eq 0) {
        Write-Host "[PS7] Installation successful" -ForegroundColor Green

        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

        Start-Sleep -Seconds 2
        return Test-PowerShell7Installed
    } else {
        Write-Host "[PS7] Installation failed (exit code: $($result.ExitCode))" -ForegroundColor Red
        return $false
    }
}

function Get-PowerShell7Path {
    # Check if pwsh is in PATH
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCommand -and $pwshCommand.Source) {
        return $pwshCommand.Source
    }

    # Check common installation paths
    $commonPaths = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

# ============================================================================
# DEPLOYMENT LAUNCH FUNCTION
# ============================================================================

function Start-DeploymentScript {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  LAUNCHING DEPLOYMENT" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # Get PS7 path
    $pwshPath = Get-PowerShell7Path

    if (!$pwshPath) {
        Write-Host "[ERROR] PowerShell 7 not found" -ForegroundColor Red
        return $false
    }

    # Ensure Deploy-Device script exists
    $deployScript = Join-Path $script:DownloadDirectory "ps_Deploy-Device.ps1"

    if (!(Test-Path $deployScript)) {
        Write-Host "[INFO] ps_Deploy-Device.ps1 not found, downloading..." -ForegroundColor Yellow
        $downloaded = Get-ScriptFromGitHub -ScriptName "ps_Deploy-Device.ps1"
        if (!$downloaded) {
            Write-Host "[ERROR] Failed to download ps_Deploy-Device.ps1" -ForegroundColor Red
            return $false
        }
    }

    Write-Host "[DEPLOYMENT] Launching ps_Deploy-Device.ps1 in PowerShell 7..." -ForegroundColor Cyan
    Write-Host "[DEPLOYMENT] PowerShell 7 Path: $pwshPath" -ForegroundColor Gray
    Write-Host "[DEPLOYMENT] Deployment Script: $deployScript" -ForegroundColor Gray
    Write-Host ""

    Stop-InitLogging

    # Launch deployment in PowerShell 7
    try {
        $deployProcess = Start-Process -FilePath $pwshPath -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$deployScript`"" -Verb RunAs -Wait -PassThru
        return ($deployProcess.ExitCode -eq 0)
    } catch {
        Write-Host "[ERROR] Failed to launch deployment: $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

try {
    Initialize-Directories
    Start-InitLogging

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  DENKO ICT DEPLOYMENT INITIALIZER" -ForegroundColor Cyan
    Write-Host "  Version 1.0.0" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
    Write-Host "Script Path: $PSCommandPath" -ForegroundColor Cyan

    # Step 1: Check/Install WinGet
    Write-Host "`n[STEP 1/3] Checking WinGet..." -ForegroundColor Yellow
    if (!(Test-WinGetAvailable)) {
        Write-Host "[WINGET] Not found, installing..." -ForegroundColor Yellow
        $wingetInstalled = Install-WinGet
        if (!$wingetInstalled) {
            Write-Host "`n[ERROR] WinGet installation failed" -ForegroundColor Red
            Write-Host "[ERROR] Cannot continue without WinGet" -ForegroundColor Red
            Write-Host "`nPress any key to exit..." -ForegroundColor Red
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit 1
        }
    } else {
        Write-Host "[WINGET] Already installed" -ForegroundColor Green
    }

    # Step 2: Check/Install PowerShell 7
    Write-Host "`n[STEP 2/3] Checking PowerShell 7..." -ForegroundColor Yellow
    if (!(Test-PowerShell7Installed)) {
        Write-Host "[PS7] Not found, installing..." -ForegroundColor Yellow
        $ps7Installed = Install-PowerShell7
        if (!$ps7Installed) {
            Write-Host "`n[ERROR] PowerShell 7 installation failed" -ForegroundColor Red
            Write-Host "[ERROR] Cannot continue without PowerShell 7" -ForegroundColor Red
            Write-Host "`nPress any key to exit..." -ForegroundColor Red
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit 1
        }
    } else {
        Write-Host "[PS7] Already installed" -ForegroundColor Green
    }

    # Step 3: Launch Deployment
    Write-Host "`n[STEP 3/3] Starting deployment..." -ForegroundColor Yellow
    $deploymentSuccess = Start-DeploymentScript

    if ($deploymentSuccess) {
        Write-Host "`n[SUCCESS] Deployment completed successfully" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`n[ERROR] Deployment failed or was cancelled" -ForegroundColor Red
        exit 1
    }

} catch {
    Write-Host "`n[CRITICAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Error details: $($_.ScriptStackTrace)" -ForegroundColor Red

    Write-Host "`nPress any key to exit..." -ForegroundColor Red
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

    exit 1
} finally {
    Stop-InitLogging
}
