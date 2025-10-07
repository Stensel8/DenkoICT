<#PSScriptInfo

.VERSION 2.1.0

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
[Version 2.1.0] - Resolved conflicts, improved PS7 switching, better error handling
#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Orchestrates Denko ICT device deployment by running child scripts in sequence.

.DESCRIPTION
    Ensures PowerShell 7 is installed, downloads deployment scripts from GitHub, and executes them.
    All logs are saved to C:\DenkoICT\Logs. All downloads go to C:\DenkoICT\Download.

.PARAMETER ScriptBaseUrl
    Base URL for downloading scripts from GitHub.

.PARAMETER SkipPS7Restart
    Internal parameter to prevent infinite restart loops.

.EXAMPLE
    .\ps_Deploy-Device.ps1
    Runs full deployment with default settings.

.NOTES
    Version      : 2.1.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : PowerShell 5.1+, Admin rights
#>

[CmdletBinding()]
param (
    [string]$ScriptBaseUrl = "https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts",
    [int]$NetworkRetryCount = 5,
    [int]$NetworkRetryDelaySeconds = 10,
    [switch]$SkipPS7Restart
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
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:TranscriptPath = Join-Path $script:LogDirectory "ps_Deploy-Device_$timestamp.log"
    
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

function Save-DeploymentScript {
    $deployScriptPath = Join-Path $script:DownloadDirectory "ps_Deploy-Device.ps1"
    
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        if ($PSCommandPath -ne $deployScriptPath) {
            Copy-Item -Path $PSCommandPath -Destination $deployScriptPath -Force
            Write-Host "[INFO] Deployment script saved to: $deployScriptPath" -ForegroundColor Green
        }
        return $deployScriptPath
    }
    
    Write-Host "[INFO] Downloading deployment script from GitHub..." -ForegroundColor Cyan
    $downloaded = Get-ScriptFromGitHub -ScriptName "ps_Deploy-Device.ps1"
    
    if ($downloaded -and (Test-Path $deployScriptPath)) {
        Write-Host "[INFO] Deployment script saved to: $deployScriptPath" -ForegroundColor Green
        return $deployScriptPath
    }
    
    Write-Host "[ERROR] Failed to save deployment script to disk" -ForegroundColor Red
    return $null
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
        Write-Host "[ERROR] ps_Install-Winget.ps1 not found" -ForegroundColor Red
        return $false
    }
    
    $result = Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$wingetScript`"" -Wait -PassThru
    
    if ($result.ExitCode -eq 0) {
        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        return Test-WinGetAvailable
    }
    return $false
}

# ============================================================================
# POWERSHELL 7 FUNCTIONS
# ============================================================================

function Test-PowerShell7 {
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

function Install-PowerShell7ViaWinGet {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  INSTALLING POWERSHELL 7" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    if (!(Test-WinGetAvailable)) {
        Write-Host "[PS7] Cannot install - WinGet not available" -ForegroundColor Red
        return $false
    }
    
    try {
        Write-Host "[PS7] Installing via WinGet..." -ForegroundColor Cyan
        $result = Start-Process winget -ArgumentList "install", "--id", "Microsoft.PowerShell", "--silent", "--accept-package-agreements", "--accept-source-agreements" -Wait -PassThru -NoNewWindow
        
        if ($result.ExitCode -in @(0, -1978335189, -1978335135)) {
            Write-Host "[PS7] Installation successful" -ForegroundColor Green
            Start-Sleep -Seconds 3
            return Test-PowerShell7
        } else {
            Write-Host "[PS7] Installation failed (exit code: $($result.ExitCode))" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "[PS7] Installation error: $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# RMM AGENT FUNCTIONS
# ============================================================================

function Find-AndInstallRMMAgent {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  SEARCHING FOR RMM AGENT" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # First check C:\DenkoICT for agent
    $agentPath = Join-Path 'C:\DenkoICT' 'RMM-Agent.exe'
    if (Test-Path $agentPath) {
        Write-Host "[RMM] Agent found at: $agentPath" -ForegroundColor Green
        Write-Host "[RMM] Installing agent..." -ForegroundColor Cyan
        
        try {
            $result = Start-Process $agentPath -ArgumentList "/S", "/v/qn" -Wait -PassThru
            if ($result.ExitCode -eq 0) {
                Write-Host "[RMM] Agent installed successfully" -ForegroundColor Green
                return $true
            } else {
                Write-Host "[RMM] Agent installation failed (exit code: $($result.ExitCode))" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "[RMM] Agent installation error: $_" -ForegroundColor Yellow
        }
    }
    
    # Search for agent installers
    $searchPaths = @('C:\DenkoICT', 'D:\', 'E:\', 'F:\', 'G:\', 'H:\')
    foreach ($path in $searchPaths) {
        if (!(Test-Path $path)) { continue }
        
        $agents = Get-ChildItem -Path $path -Filter "*Agent*.exe" -File -ErrorAction SilentlyContinue
        if ($agents) {
            $agent = $agents | Select-Object -First 1
            Write-Host "[RMM] Agent executable found: $($agent.FullName)" -ForegroundColor Green
            Write-Host "[RMM] Now installing agent..." -ForegroundColor Cyan
            
            try {
                $result = Start-Process $agent.FullName -ArgumentList "/S", "/v/qn" -Wait -PassThru
                if ($result.ExitCode -eq 0) {
                    Write-Host "[RMM] Agent installed successfully" -ForegroundColor Green
                    return $true
                }
            } catch {
                Write-Host "[RMM] Installation error: $_" -ForegroundColor Yellow
            }
        }
    }
    
    # Fallback: search for PS1 scripts
    Write-Host "[RMM] No agent executable found, searching for installation scripts..." -ForegroundColor Yellow
    $rmmScript = Join-Path $script:DownloadDirectory "ps_Install-RMM.ps1"
    if (Test-Path $rmmScript) {
        Write-Host "[RMM] Running ps_Install-RMM.ps1..." -ForegroundColor Cyan
        & $rmmScript
        return $true
    }
    
    Write-Host "[RMM] No RMM agent or installation script found" -ForegroundColor Yellow
    return $false
}

# ============================================================================
# MAIN DEPLOYMENT
# ============================================================================

function Start-Deployment {
    # Download all required scripts first
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  DOWNLOADING DEPLOYMENT SCRIPTS" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $scripts = @(
        'ps_Custom-Functions.ps1',
        'ps_Install-Winget.ps1',
        'ps_Install-Drivers.ps1', 
        'ps_Install-Applications.ps1',
        'ps_Install-RMM.ps1',
        'ps_Set-Wallpaper.ps1',
        'ps_Remove-Bloat.ps1',
        'ps_Install-WindowsUpdates.ps1'
    )
    
    $hasNetwork = Test-NetworkConnection
    
    foreach ($script in $scripts) {
        $localPath = Join-Path $script:DownloadDirectory $script
        
        if (Test-Path $localPath) {
            Write-Host "Already exists: $script" -ForegroundColor Gray
            continue
        }
        
        if ($hasNetwork) {
            Get-ScriptFromGitHub -ScriptName $script | Out-Null
        } else {
            Write-Host "Cannot download $script - no network" -ForegroundColor Yellow
        }
    }
    
    # Step 1: Ensure WinGet is installed
    if (!(Test-WinGetAvailable)) {
        if (Install-WinGet) {
            Write-Host "[WINGET] Installation successful" -ForegroundColor Green
        } else {
            Write-Host "[WINGET] Installation failed - continuing without WinGet" -ForegroundColor Yellow
        }
    }
    
    # Step 2: Install PowerShell 7 if needed
    $hasPS7 = Test-PowerShell7
    if (!$hasPS7 -and !$SkipPS7Restart) {
        if (Test-WinGetAvailable) {
            $hasPS7 = Install-PowerShell7ViaWinGet
        }
    }
    
    # Step 3: Install RMM Agent
    Find-AndInstallRMMAgent
    
    # Step 4: Define and execute deployment steps
    $steps = @(
        @{ Script = 'ps_Install-Drivers.ps1'; Name = 'Driver Updates'; UsePS7 = $true }
        @{ Script = 'ps_Install-Applications.ps1'; Name = 'Applications'; UsePS7 = $true }
        @{ Script = 'ps_Remove-Bloat.ps1'; Name = 'Bloatware Removal'; UsePS7 = $true }
        @{ Script = 'ps_Set-Wallpaper.ps1'; Name = 'Wallpaper Configuration'; UsePS7 = $false }
        @{ Script = 'ps_Install-WindowsUpdates.ps1'; Name = 'Windows Updates'; UsePS7 = $true }
    )
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  EXECUTING DEPLOYMENT STEPS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    $results = @{ Success = 0; Failed = 0; Skipped = 0 }
    
    foreach ($step in $steps) {
        $scriptPath = Join-Path $script:DownloadDirectory $step.Script
        
        if (!(Test-Path $scriptPath)) {
            Write-Host "`n[SKIPPED] $($step.Name) - Script not found" -ForegroundColor Yellow
            $results.Skipped++
            continue
        }
        
        Write-Host "`n[RUNNING] $($step.Name)" -ForegroundColor Yellow
        
        if ($step.UsePS7 -and $hasPS7) {
            $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
            if ($pwshPath) {
                $result = Start-Process $pwshPath -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"" -Wait -PassThru
            } else {
                $result = Start-Process powershell.exe -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"" -Wait -PassThru
            }
        } else {
            $result = Start-Process powershell.exe -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"" -Wait -PassThru
        }
        
        if ($result.ExitCode -eq 0 -or $null -eq $result.ExitCode) {
            Write-Host "  ✓ Completed: $($step.Name)" -ForegroundColor Green
            $results.Success++
        } else {
            Write-Host "  ✗ Failed: $($step.Name) (exit code: $($result.ExitCode))" -ForegroundColor Red
            $results.Failed++
        }
    }
    
    # Summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Success: $($results.Success)" -ForegroundColor Green
    Write-Host "Failed: $($results.Failed)" -ForegroundColor $(if ($results.Failed -gt 0) { 'Red' } else { 'Gray' })
    Write-Host "Skipped: $($results.Skipped)" -ForegroundColor $(if ($results.Skipped -gt 0) { 'Yellow' } else { 'Gray' })
    Write-Host "Log: $script:TranscriptPath" -ForegroundColor Cyan
    
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
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
    Write-Host "Script Path: $PSCommandPath" -ForegroundColor Cyan
    
    # Check if we should restart in PS7
    if ($PSVersionTable.PSVersion.Major -lt 7 -and !$SkipPS7Restart) {
        # Ensure deployment script is saved
        $deployScriptPath = Save-DeploymentScript
        
        if (Test-PowerShell7) {
            Write-Host "`nPowerShell 7 detected. Restarting deployment in PS7..." -ForegroundColor Cyan
            Stop-DeploymentLogging
            
            $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
            if (!$pwshPath) {
                $pwshPath = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
            }
            
            if (Test-Path $pwshPath) {
                $arguments = @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", "`"$deployScriptPath`"",
                    "-SkipPS7Restart"
                )
                
                $ps7Process = Start-Process -FilePath $pwshPath -ArgumentList $arguments -Verb RunAs -Wait -PassThru
                exit $ps7Process.ExitCode
            }
        }
    }
    
    # Run deployment
    $deploymentResults = Start-Deployment
    
    $exitCode = if ($deploymentResults.Failed -gt 0) { 1 } else { 0 }
    
    # Check if unattended
    $isUnattended = $env:USERNAME -eq 'defaultuser0' -or $env:USERNAME -eq 'SYSTEM' -or [Environment]::UserInteractive -eq $false
    
    if (!$isUnattended -and $deploymentResults.Failed -gt 0) {
        Write-Host "`n[WARNING] Some deployment steps failed!" -ForegroundColor Yellow
        Write-Host "Press any key to continue..." -ForegroundColor Yellow
        $null = [System.Console]::ReadKey($true)
    } elseif (!$isUnattended) {
        Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
        $null = [System.Console]::ReadKey($true)
    } else {
        Start-Sleep -Seconds 5
    }
    
    exit $exitCode
    
} catch {
    Write-Host "`n[CRITICAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Error details: $($_.ScriptStackTrace)" -ForegroundColor Red
    
    $isUnattended = $env:USERNAME -eq 'defaultuser0' -or $env:USERNAME -eq 'SYSTEM' -or [Environment]::UserInteractive -eq $false
    
    if (!$isUnattended) {
        Write-Host "`nPress any key to exit..." -ForegroundColor Red
        $null = [System.Console]::ReadKey($true)
    } else {
        Start-Sleep -Seconds 10
    }
    
    exit 1
} finally {
    Stop-DeploymentLogging
}