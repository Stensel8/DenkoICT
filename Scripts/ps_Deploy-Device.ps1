<#PSScriptInfo

.VERSION 2.2.0

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
    Version      : 2.2.0
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
    param([switch]$Silent)
    
    try {
        $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetPath) {
            $version = winget --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                if (-not $Silent) {
                    Write-Host "[WINGET] Available - Version: $version" -ForegroundColor Green
                }
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
        return Test-WinGetAvailable -Silent
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
    
    if (!(Test-WinGetAvailable -Silent)) {
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

function Test-RMMAgentInstalled {
    <#
    .SYNOPSIS
        Checks if the RMM agent (Datto RMM / CentraStage) is installed.
    .DESCRIPTION
        Checks for the CagService.exe file and/or the service running.
    #>
    
    $agentExePath = "C:\Program Files (x86)\CentraStage\CagService.exe"
    $fileExists = Test-Path $agentExePath
    
    $serviceExists = $false
    try {
        $service = Get-Service -Name "CagService" -ErrorAction SilentlyContinue
        if ($service) {
            $serviceExists = $true
        } else {
            # Try alternative service name
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
    <#
    .SYNOPSIS
        Waits up to 30 seconds for the RMM agent to be installed.
    .DESCRIPTION
        Checks every second for the agent files or service to appear.
    #>
    param(
        [int]$MaxWaitSeconds = 30
    )
    
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
    <#
    .SYNOPSIS
        Finds RMM agent and moves/renames it to Agent.exe in Download folder.
    .DESCRIPTION
        Searches for agent files and ensures they are properly named and located.
    #>
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  PREPARING RMM AGENT" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $targetAgentPath = Join-Path $script:DownloadDirectory 'Agent.exe'
    
    # Check if Agent.exe already exists in Download folder
    if (Test-Path $targetAgentPath) {
        Write-Host "[RMM] Agent.exe already present in Download folder" -ForegroundColor Green
        return $targetAgentPath
    }
    
    # Search for RMM-Agent.exe in C:\DenkoICT root
    $oldAgentPath = Join-Path 'C:\DenkoICT' 'RMM-Agent.exe'
    if (Test-Path $oldAgentPath) {
        Write-Host "[RMM] Found RMM-Agent.exe, moving to Download folder as Agent.exe..." -ForegroundColor Cyan
        try {
            Move-Item -Path $oldAgentPath -Destination $targetAgentPath -Force
            Write-Host "[RMM] Agent moved successfully" -ForegroundColor Green
            
            # Consolidate logs to Logs folder
            $agentInfoPath = Join-Path 'C:\DenkoICT' 'agent-info.txt'
            $agentCopyLogPath = Join-Path 'C:\DenkoICT' 'agent-copy.log'
            
            # Merge agent-info.txt and agent-copy.log into a single consolidated log
            $consolidatedLogPath = Join-Path $script:LogDirectory 'agent-deployment.log'
            
            if (Test-Path $agentInfoPath) {
                Add-Content -Path $consolidatedLogPath -Value "`n=== Agent Information ===" -Force
                Get-Content $agentInfoPath | Add-Content -Path $consolidatedLogPath -Force
                Remove-Item $agentInfoPath -Force -ErrorAction SilentlyContinue
            }
            
            if (Test-Path $agentCopyLogPath) {
                Add-Content -Path $consolidatedLogPath -Value "`n=== Agent Copy Log ===" -Force
                Get-Content $agentCopyLogPath | Add-Content -Path $consolidatedLogPath -Force
                Remove-Item $agentCopyLogPath -Force -ErrorAction SilentlyContinue
            }
            
            if (Test-Path $consolidatedLogPath) {
                Write-Host "[RMM] Agent logs consolidated to: $consolidatedLogPath" -ForegroundColor Green
            }
            
            return $targetAgentPath
        } catch {
            Write-Host "[RMM] Failed to move agent: $_" -ForegroundColor Red
        }
    }
    
    # Search other locations for agent files
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
    <#
    .SYNOPSIS
        Installs the RMM agent and verifies installation.
    #>
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  INSTALLING RMM AGENT" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Check if already installed
    if (Test-RMMAgentInstalled) {
        Write-Host "[RMM] Agent is already installed" -ForegroundColor Green
        return $true
    }
    
    # Prepare the agent
    $agentPath = Find-AndPrepareRMMAgent
    
    if (!$agentPath -or !(Test-Path $agentPath)) {
        Write-Host "[RMM] Cannot install - Agent.exe not found" -ForegroundColor Yellow
        return $false
    }
    
    Write-Host "[RMM] Starting agent installation..." -ForegroundColor Cyan
    Write-Host "[RMM] Executing: $agentPath" -ForegroundColor Gray
    
    try {
        # Start the agent installer without waiting for it to complete
        # The agent doesn't return proper exit codes, so we don't use -Wait
        Start-Process -FilePath $agentPath -ArgumentList "/S", "/v/qn" -PassThru -NoNewWindow
        
        # Wait for the agent to be installed (check for files/service)
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
    $wingetAvailable = Test-WinGetAvailable
    if (!$wingetAvailable) {
        if (Install-WinGet) {
            Write-Host "[WINGET] Installation successful" -ForegroundColor Green
            $wingetAvailable = $true
        } else {
            Write-Host "[WINGET] Installation failed - continuing without WinGet" -ForegroundColor Yellow
        }
    }
    
    # Step 2: Install PowerShell 7 if needed
    $hasPS7 = Test-PowerShell7
    if (!$hasPS7 -and !$SkipPS7Restart) {
        if ($wingetAvailable) {
            $hasPS7 = Install-PowerShell7ViaWinGet
        }
    }
    
    # Step 3: Install RMM Agent
    Install-RMMAgent
    
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
    Write-Host ""
    Write-Host "Each step will run in a separate PowerShell window." -ForegroundColor Gray
    Write-Host "You can monitor progress in each window." -ForegroundColor Gray
    Write-Host ""
    
    $results = @{ Success = 0; Failed = 0; Skipped = 0 }
    
    foreach ($step in $steps) {
        $scriptPath = Join-Path $script:DownloadDirectory $step.Script
        
        if (!(Test-Path $scriptPath)) {
            Write-Host "[SKIPPED] $($step.Name) - Script not found" -ForegroundColor Yellow
            $results.Skipped++
            continue
        }
        
        Write-Host "[RUNNING] $($step.Name)..." -ForegroundColor Cyan
        
        # Determine which PowerShell to use
        $psExecutable = "powershell.exe"
        if ($step.UsePS7 -and $hasPS7) {
            $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
            if ($pwshCommand -and $pwshCommand.Source) {
                $psExecutable = $pwshCommand.Source
            }
        }
        
        Write-Host "  → Executing with $psExecutable" -ForegroundColor Gray
        
        # Run in a new visible window (non-blocking)
        try {
            $processArgs = @{
                FilePath = $psExecutable
                ArgumentList = @(
                    "-NoProfile"
                    "-ExecutionPolicy", "Bypass"
                    "-NoExit"
                    "-Command"
                    "& { `$Host.UI.RawUI.WindowTitle = '$($step.Name)'; Write-Host '========================================' -ForegroundColor Cyan; Write-Host '  $($step.Name)' -ForegroundColor Cyan; Write-Host '========================================' -ForegroundColor Cyan; Write-Host ''; & '$scriptPath'; Write-Host ''; Write-Host '========================================' -ForegroundColor Cyan; Write-Host 'Script completed. Exit code: `$LASTEXITCODE' -ForegroundColor $(if (`$LASTEXITCODE -eq 0) { 'Green' } else { 'Red' }); Write-Host 'You can close this window or press any key...' -ForegroundColor Gray; `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown'); exit `$LASTEXITCODE }"
                )
                PassThru = $false
                Wait = $false
            }
            
            Start-Process @processArgs | Out-Null
            
            Write-Host "  ✓ Completed: $($step.Name)" -ForegroundColor Green
            $results.Success++
        } catch {
            Write-Host "  ✗ Error running $($step.Name): $_" -ForegroundColor Red
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