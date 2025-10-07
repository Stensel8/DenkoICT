<#PSScriptInfo

.VERSION 1.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Installation WinGet

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Installs PowerShell 7 via WinGet.
#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs PowerShell 7 via WinGet.

.DESCRIPTION
    Checks if PowerShell 7 is installed, and if not, installs it using WinGet.
    Requires WinGet to be installed first.

.EXAMPLE
    .\ps_Install-PowerShell7.ps1
    Installs PowerShell 7 if not present.

.NOTES
    Version      : 1.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : PowerShell 5.1+, Admin rights, WinGet
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# FUNCTIONS
# ============================================================================

function Test-WinGetAvailable {
    <#
    .SYNOPSIS
        Checks if WinGet is available and functional.
    #>
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

function Test-PowerShell7Installed {
    <#
    .SYNOPSIS
        Checks if PowerShell 7 is installed.
    #>

    # Check if we're already running in PS7
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Host "[PS7] Already running in PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green
        return $true
    }

    # Check if pwsh is in PATH
    $pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshPath) {
        Write-Host "[PS7] Found at: $($pwshPath.Source)" -ForegroundColor Green
        return $true
    }

    # Check common installation paths
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

    Write-Host "[PS7] Not installed" -ForegroundColor Yellow
    return $false
}

function Install-PowerShell7 {
    <#
    .SYNOPSIS
        Installs PowerShell 7 via WinGet.
    #>

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  INSTALLING POWERSHELL 7" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    if (!(Test-WinGetAvailable)) {
        Write-Host "[ERROR] WinGet is not available - cannot install PowerShell 7" -ForegroundColor Red
        Write-Host "[ERROR] Please install WinGet first using ps_Install-Winget.ps1" -ForegroundColor Red
        return $false
    }

    try {
        Write-Host "[PS7] Installing via WinGet..." -ForegroundColor Cyan
        Write-Host "[PS7] This may take a few minutes..." -ForegroundColor Gray

        $result = Start-Process winget -ArgumentList "install", "--id", "Microsoft.PowerShell", "--silent", "--accept-package-agreements", "--accept-source-agreements" -Wait -PassThru -NoNewWindow

        # WinGet exit codes:
        # 0 = Success
        # -1978335189 = Already installed
        # -1978335135 = Update available
        if ($result.ExitCode -in @(0, -1978335189, -1978335135)) {
            Write-Host "[PS7] Installation successful" -ForegroundColor Green

            # Refresh PATH environment variable
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

            # Wait a moment for installation to complete
            Start-Sleep -Seconds 3

            # Verify installation
            if (Test-PowerShell7Installed) {
                Write-Host "[PS7] Installation verified" -ForegroundColor Green
                return $true
            } else {
                Write-Host "[WARNING] Installation completed but PowerShell 7 not detected" -ForegroundColor Yellow
                Write-Host "[WARNING] You may need to restart your terminal or computer" -ForegroundColor Yellow
                return $true
            }
        } else {
            Write-Host "[ERROR] Installation failed with exit code: $($result.ExitCode)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "[ERROR] Installation error: $_" -ForegroundColor Red
        Write-Host "[ERROR] Exception details: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# MAIN
# ============================================================================

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  POWERSHELL 7 INSTALLER" -ForegroundColor Cyan
    Write-Host "  Version 1.0.0" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    Write-Host "Current PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan

    # Check if already installed
    if (Test-PowerShell7Installed) {
        Write-Host "`n[SUCCESS] PowerShell 7 is already installed" -ForegroundColor Green
        exit 0
    }

    # Install PowerShell 7
    $installSuccess = Install-PowerShell7

    if ($installSuccess) {
        Write-Host "`n[SUCCESS] PowerShell 7 installation completed" -ForegroundColor Green
        Write-Host "`nTo use PowerShell 7, open a new terminal and run: pwsh" -ForegroundColor Cyan
        exit 0
    } else {
        Write-Host "`n[FAILED] PowerShell 7 installation failed" -ForegroundColor Red
        exit 1
    }

} catch {
    Write-Host "`n[CRITICAL ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Error details: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
