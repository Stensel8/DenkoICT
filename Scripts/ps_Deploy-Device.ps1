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

.EXAMPLE
    .\ps_Deploy-Device.ps1
    Runs full deployment with default settings.

.NOTES
    Version      : 2.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : PowerShell 5.1+, Admin rights
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
        Installs PowerShell 7 using various methods.
    #>
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  INSTALLING POWERSHELL 7" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Method 1: Try WinGet first (if available)
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "[PS7] Installing via WinGet..." -ForegroundColor Cyan
        try {
            $result = Start-Process -FilePath "winget" -ArgumentList "install --id Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements" -Wait -PassThru
            if ($result.ExitCode -eq 0) {
                Write-Host "[PS7] Successfully installed via WinGet" -ForegroundColor Green
                return $true
            }
        } catch {
            Write-Host "[PS7] WinGet installation failed: $_" -ForegroundColor Yellow
        }
    }
    
    # Method 2: Direct MSI download
    Write-Host "[PS7] Downloading PowerShell 7 MSI installer..." -ForegroundColor Cyan
    $msiUrl = "https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7-win-x64.msi"
    $msiPath = Join-Path $script:DownloadDirectory "PowerShell-7.msi"
    
    try {
        # Ensure download directory exists
        if (!(Test-Path $script:DownloadDirectory)) {
            New-Item -Path $script:DownloadDirectory -ItemType Directory -Force | Out-Null
        }
        
        # Download MSI
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($msiUrl, $msiPath)
        
        if (Test-Path $msiPath) {
            Write-Host "[PS7] Installing from MSI..." -ForegroundColor Cyan
            $msiArguments = "/i `"$msiPath`" /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=0 REGISTER_MANIFEST=1"
            $result = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -Wait -PassThru
            
            if ($result.ExitCode -eq 0) {
                Write-Host "[PS7] Successfully installed from MSI" -ForegroundColor Green
                
                # Update PATH immediately
                $pwshPath = "$env:ProgramFiles\PowerShell\7"
                $env:PATH = "$pwshPath;$env:PATH"
                
                return $true
            } else {
                Write-Host "[PS7] MSI installation failed with code: $($result.ExitCode)" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "[PS7] Failed to download/install MSI: $_" -ForegroundColor Red
    }
    
    # Method 3: Install script from PowerShell Gallery
    Write-Host "[PS7] Trying PowerShell Gallery install script..." -ForegroundColor Cyan
    try {
        Invoke-Expression "& { $(Invoke-RestMethod 'https://aka.ms/install-powershell.ps1') } -UseMSI -Quiet"
        Write-Host "[PS7] Installation script completed" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[PS7] Gallery script failed: $_" -ForegroundColor Red
    }
    
    return $false
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
        
        # Download from GitHub
        Get-ScriptFromGitHub -ScriptName $script | Out-Null
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
    
    # PowerShell 7 check and installation
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "`nRunning in Windows PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" -ForegroundColor Yellow
        
        if (!(Test-PowerShell7)) {
            Write-Host "PowerShell 7 is required for optimal deployment" -ForegroundColor Yellow
            
            $install = Install-PowerShell7
            if ($install -and (Test-PowerShell7)) {
                Write-Host "`nPowerShell 7 installed successfully!" -ForegroundColor Green
                
                # Option to restart in PS7
                $pwshPath = Get-PowerShell7Path
                if ($pwshPath) {
                    Write-Host "`nRestarting deployment in PowerShell 7..." -ForegroundColor Cyan
                    Start-Process -FilePath $pwshPath -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"" -Verb RunAs
                    exit 0
                }
            } else {
                Write-Host "`nContinuing with Windows PowerShell (some features may be limited)" -ForegroundColor Yellow
            }
        }
    }
    
    # Run deployment
    Start-Deployment
    
    Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
    $null = [System.Console]::ReadKey($true)
    exit 0
    
} catch {
    Write-Host "`n[CRITICAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nPress any key to exit..." -ForegroundColor Red
    $null = [System.Console]::ReadKey($true)
    exit 1
} finally {
    Stop-DeploymentLogging
}