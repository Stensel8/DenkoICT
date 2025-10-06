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
    [switch]$SkipPS7Restart  # Internal parameter to prevent restart loops
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Script-scoped variables
$script:LogDirectory = 'C:\DenkoICT\Logs'
$script:DownloadDirectory = 'C:\DenkoICT\Download'
$script:TranscriptPath = $null

# ============================================================================
# NETWORK FUNCTIONS
# ============================================================================

function Test-NetworkConnection {
    <#
    .SYNOPSIS
        Tests network connectivity with retry logic.
    #>
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

# ============================================================================
# POWERSHELL 7 DETECTION AND INSTALLATION
# ============================================================================

function Test-PowerShell7 {
    <#
    .SYNOPSIS
        Checks if PowerShell 7 is installed and available.
    #>
    
    # Check if we're already running in PowerShell 7+
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Host "[PS7] Already running in PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green
        return $true
    }
    
    # Check if pwsh.exe exists
    $pwshPath = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwshPath) {
        Write-Host "[PS7] PowerShell 7 found at: $($pwshPath.Source)" -ForegroundColor Green
        return $true
    }
    
    # Check common installation paths
    $commonPaths = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            Write-Host "[PS7] PowerShell 7 found at: $path" -ForegroundColor Green
            return $true
        }
    }
    
    Write-Host "[PS7] PowerShell 7 not found" -ForegroundColor Yellow
    return $false
}

function Install-PowerShell7 {
    <#
    .SYNOPSIS
        Installs PowerShell 7 using WinGet package manager.
    #>
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  INSTALLING POWERSHELL 7" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Ensure network connectivity
    if (!(Test-NetworkConnection)) {
        Write-Host "[PS7] Cannot install - no network connectivity" -ForegroundColor Red
        return $false
    }
    
    # Ensure WinGet is available first
    Write-Host "[PS7] Checking WinGet availability..." -ForegroundColor Cyan
    
    # Refresh environment PATH to ensure WinGet is available
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
    
    # Find WinGet executable with robust path detection (same logic as applications script)
    $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    
    if (-not $wingetCmd) {
        Write-Host "[PS7] WinGet not in PATH - searching common installation paths..." -ForegroundColor Yellow
        $wingetPaths = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
        )
        
        foreach ($path in $wingetPaths) {
            $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
            if ($resolved) {
                if ($resolved -is [array]) {
                    $resolved = $resolved | Sort-Object {
                        [version]($_.Path -replace '^.*_(\d+\.\d+\.\d+\.\d+)_.*', '$1')
                    } -Descending | Select-Object -First 1
                }
                $wingetCmd = Get-Command $resolved.Path -ErrorAction SilentlyContinue
                if ($wingetCmd) {
                    Write-Host "[PS7] Found WinGet at: $($resolved.Path)" -ForegroundColor Green
                    break
                }
            }
        }
    }
    
    if (-not $wingetCmd) {
        Write-Host "[PS7] Cannot install PowerShell 7 - WinGet is not available" -ForegroundColor Red
        Write-Host "[PS7] Please ensure WinGet is installed or run ps_Install-Winget.ps1 first" -ForegroundColor Red
        return $false
    }
    
    # Validate WinGet is functional
    try {
        $wingetVersion = & $wingetCmd.Source --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet not functional (exit: $LASTEXITCODE)"
        }
        Write-Host "[PS7] WinGet version: $wingetVersion" -ForegroundColor Green
    } catch {
        Write-Host "[PS7] WinGet not functional: $_" -ForegroundColor Red
        return $false
    }
    
    # Install PowerShell 7 via WinGet
    Write-Host "[PS7] Installing PowerShell 7 via WinGet..." -ForegroundColor Cyan
    try {
        # Build winget arguments
        $wingetArgs = @(
            "install"
            "--id", "Microsoft.PowerShell"
            "--silent"
            "--accept-package-agreements"
            "--accept-source-agreements"
        )
        
        Write-Host "[PS7] Executing: winget $($wingetArgs -join ' ')" -ForegroundColor Cyan
        $startTime = Get-Date
        
        # Execute winget and capture output
        $output = & $wingetCmd.Source $wingetArgs 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        Write-Host "[PS7] Installation completed in $([math]::Round($duration, 1)) seconds" -ForegroundColor Cyan
        
        # Handle exit codes
        if ($exitCode -eq 0) {
            Write-Host "[PS7] Successfully installed via WinGet" -ForegroundColor Green
            Start-Sleep -Seconds 3
            return $true
        } elseif ($exitCode -in @(-1978335189, -1978335135)) {
            Write-Host "[PS7] Already installed (WinGet exit code: $exitCode)" -ForegroundColor Green
            return $true
        } elseif ($exitCode -in @(-1978334967, -1978334966)) {
            Write-Host "[PS7] Installed but reboot required (exit code: $exitCode)" -ForegroundColor Yellow
            return $true
        } else {
            Write-Host "[PS7] WinGet installation failed with exit code: $exitCode" -ForegroundColor Red
            Write-Host "[PS7] Output: $($output.Trim())" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "[PS7] Installation failed: $_" -ForegroundColor Red
        return $false
    }
}

function Get-PowerShell7Path {
    <#
    .SYNOPSIS
        Gets the path to pwsh.exe.
    #>
    
    # Check if pwsh is in PATH
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) {
        return $pwsh.Source
    }
    
    # Check common locations
    $paths = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe"
    )
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    return $null
}

# ============================================================================
# BASIC FUNCTIONS
# ============================================================================

function Initialize-Directories {
    if (!(Test-Path $script:LogDirectory)) {
        New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
    }
    if (!(Test-Path $script:DownloadDirectory)) {
        New-Item -Path $script:DownloadDirectory -ItemType Directory -Force | Out-Null
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

function Invoke-DeploymentScript {
    param(
        [string]$ScriptPath,
        [string]$DisplayName,
        [switch]$UsePS7
    )

    Write-Host "`n[RUNNING] $DisplayName" -ForegroundColor Yellow

    # Determine how to run the script
    if ($UsePS7) {
        $pwshPath = Get-PowerShell7Path
        if ($pwshPath) {
            Write-Host "  → Executing with PowerShell 7" -ForegroundColor Cyan
            # Use -NoLogo to reduce output, ensure clean module state with fresh session
            $result = Start-Process -FilePath $pwshPath -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"" -Wait -PassThru
        } else {
            Write-Host "  → PS7 not available, using Windows PowerShell" -ForegroundColor Yellow
            $result = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"" -Wait -PassThru
        }
    } else {
        # Run directly in current session
        & $ScriptPath
        $result = [PSCustomObject]@{ ExitCode = $LASTEXITCODE }
    }

    if ($result.ExitCode -eq 0 -or $null -eq $result.ExitCode) {
        Write-Host "  ✓ Completed: $DisplayName" -ForegroundColor Green
        return $true
    } elseif ($result.ExitCode -eq 3010) {
        Write-Host "  ✓ Completed: $DisplayName (reboot required)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  ✗ Failed: $DisplayName (exit code: $($result.ExitCode))" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# MAIN ORCHESTRATION
# ============================================================================

function Start-Deployment {
    # Test network connectivity first
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  CHECKING NETWORK CONNECTIVITY" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $hasNetwork = Test-NetworkConnection
    if (!$hasNetwork) {
        Write-Host "`n[WARNING] Limited or no network connectivity - some features may not work" -ForegroundColor Yellow
    }
    
    # Download all required scripts first
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  DOWNLOADING DEPLOYMENT SCRIPTS" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $scripts = @(
        'ps_Custom-Functions.ps1',
        'ps_Install-Winget.ps1',
        'ps_Install-Drivers.ps1', 
        'ps_Install-Applications.ps1',
        'ps_Set-Wallpaper.ps1',
        'ps_Remove-Bloat.ps1',
        'ps_Install-WindowsUpdates.ps1'
    )
    
    foreach ($script in $scripts) {
        $localPath = Join-Path $script:DownloadDirectory $script
        
        # Check if already exists locally
        if (Test-Path $localPath) {
            Write-Host "Already exists: $script" -ForegroundColor Gray
            continue
        }
        
        # Try script directory
        if ($PSCommandPath) {
            $scriptDirPath = Join-Path (Split-Path $PSCommandPath -Parent) $script
            if (Test-Path $scriptDirPath) {
                Copy-Item $scriptDirPath $localPath
                Write-Host "Copied from local: $script" -ForegroundColor Green
                continue
            }
        }
        
        # Download from GitHub if network is available
        if ($hasNetwork) {
            Get-ScriptFromGitHub -ScriptName $script | Out-Null
        } else {
            Write-Host "Cannot download $script - no network" -ForegroundColor Yellow
        }
    }
    
    # Check if PowerShell 7 is available
    $hasPS7 = Test-PowerShell7
    
    # Define deployment steps
    $steps = @(
        @{ Script = 'ps_Install-Winget.ps1'; Name = 'WinGet Installation'; UsePS7 = $false }
        @{ Script = 'ps_Install-Drivers.ps1'; Name = 'Driver Updates for HP and Dell'; UsePS7 = $true }
        @{ Script = 'ps_Install-Applications.ps1'; Name = 'Applications'; UsePS7 = $true }
        @{ Script = 'ps_Remove-Bloat.ps1'; Name = 'Bloatware Removal'; UsePS7 = $true }
        @{ Script = 'ps_Set-Wallpaper.ps1'; Name = 'Wallpaper Configuration'; UsePS7 = $true }
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
        
        $success = Invoke-DeploymentScript -ScriptPath $scriptPath -DisplayName $step.Name -UsePS7:($step.UsePS7 -and $hasPS7)
        
        if ($success) {
            $results.Success++
        } else {
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
    # Initialize
    Initialize-Directories
    Start-DeploymentLogging
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  DENKO ICT DEVICE DEPLOYMENT" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
    Write-Host "Script Path: $PSCommandPath" -ForegroundColor Cyan
    if ($SkipPS7Restart) {
        Write-Host "PS7 Restart: Skipped (already restarted)" -ForegroundColor Gray
    }
    
    # PowerShell 7 check and installation (only if not already restarted)
    if ($PSVersionTable.PSVersion.Major -lt 7 -and !$SkipPS7Restart) {
        Write-Host "`nRunning in Windows PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" -ForegroundColor Yellow
        
        if (!(Test-PowerShell7)) {
            Write-Host "PowerShell 7 is recommended for optimal deployment" -ForegroundColor Yellow
            Write-Host "Attempting to install PowerShell 7..." -ForegroundColor Cyan
            
            $install = Install-PowerShell7
            if ($install -and (Test-PowerShell7)) {
                Write-Host "`nPowerShell 7 installed successfully!" -ForegroundColor Green
                
                # Restart in PS7
                $pwshPath = Get-PowerShell7Path
                if ($pwshPath -and (Test-Path $pwshPath)) {
                    Write-Host "`nRestarting deployment in PowerShell 7..." -ForegroundColor Cyan
                    Write-Host "This window will remain open until deployment completes." -ForegroundColor Cyan
                    
                    # Build arguments including our custom parameters
                    $arguments = @(
                        "-NoProfile",
                        "-ExecutionPolicy", "Bypass",
                        "-File", "`"$PSCommandPath`"",
                        "-ScriptBaseUrl", "`"$ScriptBaseUrl`"",
                        "-NetworkRetryCount", $NetworkRetryCount,
                        "-NetworkRetryDelaySeconds", $NetworkRetryDelaySeconds,
                        "-SkipPS7Restart"  # Prevent infinite restart loop
                    )
                    
                    # Start PS7 process and WAIT for it to complete
                    $ps7Process = Start-Process -FilePath $pwshPath -ArgumentList $arguments -Verb RunAs -Wait -PassThru
                    
                    # Exit with the same code as the PS7 process
                    exit $ps7Process.ExitCode
                }
            } else {
                Write-Host "`nContinuing with Windows PowerShell (some features may be limited)" -ForegroundColor Yellow
                Write-Host "Note: Some deployment steps may have reduced functionality" -ForegroundColor Yellow
            }
        } else {
            # PS7 exists but we're in PS5 - restart in PS7
            $pwshPath = Get-PowerShell7Path
            if ($pwshPath -and (Test-Path $pwshPath)) {
                Write-Host "`nPowerShell 7 detected. Restarting deployment in PS7..." -ForegroundColor Cyan
                Write-Host "This window will remain open until deployment completes." -ForegroundColor Cyan
                
                # Build arguments including our custom parameters
                $arguments = @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", "`"$PSCommandPath`"",
                    "-ScriptBaseUrl", "`"$ScriptBaseUrl`"",
                    "-NetworkRetryCount", $NetworkRetryCount,
                    "-NetworkRetryDelaySeconds", $NetworkRetryDelaySeconds,
                    "-SkipPS7Restart"  # Prevent infinite restart loop
                )
                
                # Start PS7 process and WAIT for it to complete
                $ps7Process = Start-Process -FilePath $pwshPath -ArgumentList $arguments -Verb RunAs -Wait -PassThru
                
                # Exit with the same code as the PS7 process
                exit $ps7Process.ExitCode
            }
        }
    }
    
    # Run deployment
    $deploymentResults = Start-Deployment
    
    # Determine exit code based on results
    $exitCode = 0
    if ($deploymentResults.Failed -gt 0) {
        $exitCode = 1
    }
    
    # For unattended scenarios, don't wait for key press
    $isUnattended = $env:USERNAME -eq 'defaultuser0' -or 
                    $env:USERNAME -eq 'SYSTEM' -or 
                    [Environment]::UserInteractive -eq $false
    
    if (!$isUnattended) {
        Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
        $null = [System.Console]::ReadKey($true)
    } else {
        Write-Host "`nRunning in unattended mode - exiting automatically" -ForegroundColor Cyan
        Start-Sleep -Seconds 5
    }
    
    exit $exitCode
    
} catch {
    Write-Host "`n[CRITICAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Error details: $($_.ScriptStackTrace)" -ForegroundColor Red
    
    # Log the full error
    if ($script:TranscriptPath) {
        $_ | Out-String | Add-Content -Path $script:TranscriptPath
    }
    
    # For unattended scenarios, don't wait for key press
    $isUnattended = $env:USERNAME -eq 'defaultuser0' -or 
                    $env:USERNAME -eq 'SYSTEM' -or 
                    [Environment]::UserInteractive -eq $false
    
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