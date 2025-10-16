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
    .\Install-PowerShell7.ps1
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

# Load utility modules
$utilitiesPath = Join-Path $PSScriptRoot 'Utilities'
Get-ChildItem "$utilitiesPath\*.psm1" | ForEach-Object {
    Import-Module $_.FullName -Force -Global
}

Start-EmergencyTranscript -LogName 'Install-PowerShell7.log'
Initialize-Script -RequireAdmin

# ============================================================================
# FUNCTIONS
# ============================================================================

# Functions are now in utility modules:
# - Test-PowerShell7 (System.psm1)
# - Test-WinGetFunctional (WinGet.psm1)

function Install-PowerShell7 {
    <#
    .SYNOPSIS
        Installs PowerShell 7 via WinGet.
    #>

    Write-Log "========================================" -Level Info
    Write-Log "  INSTALLING POWERSHELL 7" -Level Info
    Write-Log "========================================" -Level Info

    try {
        $wg = Test-WinGetFunctional
        $wingetPath = $wg.Path
    Write-Log "Installing PowerShell 7 via WinGet..." -Level Info

    $result = Start-Process $wingetPath -ArgumentList "install", "--id", "Microsoft.PowerShell", "--silent", "--accept-package-agreements", "--accept-source-agreements" -Wait -PassThru -NoNewWindow

        # WinGet exit codes:
        # 0 = Success
        # -1978335189 = Already installed
        # -1978335135 = Update available
        if ($result.ExitCode -in @(0, -1978335189, -1978335135)) {
            Write-Log "PowerShell 7 installation successful" -Level Success

            # Refresh PATH environment variable
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

            # Wait a moment for installation to complete
            Start-Sleep -Seconds 3

            # Verify installation
            if (Test-PowerShell7) {
                Write-Log "PowerShell 7 installation verified" -Level Success
                return $true
            } else {
                Write-Log "Installation completed but PowerShell 7 not detected (restart may be required)" -Level Warning
                return $true
            }
        } else {
            Write-Log "Installation failed with exit code: $($result.ExitCode)" -Level Error
            return $false
        }
    } catch {
        Write-Log "Installation error: $_" -Level Error
        Write-Log "Exception details: $($_.Exception.Message)" -Level Error
        return $false
    }
}

# ============================================================================
# MAIN
# ============================================================================

try {
    Write-Log "========================================" -Level Info
    Write-Log "  POWERSHELL 7 INSTALLER (v1.0.0)" -Level Info
    Write-Log "========================================" -Level Info
    Write-Log "Current PowerShell Version: $($PSVersionTable.PSVersion)" -Level Info

    # Check if already installed
    if (Test-PowerShell7) {
        Write-Log "PowerShell 7 is already installed" -Level Success
        exit 0
    }



    # Install PowerShell 7
    $installSuccess = Install-PowerShell7

    if ($installSuccess) {
        Write-Log "PowerShell 7 installation completed" -Level Success
        Write-Log "To use PowerShell 7, open a new terminal and run: pwsh" -Level Info
        exit 0
    } else {
        Write-Log "PowerShell 7 installation failed" -Level Error
        exit 1
    }

} catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" -Level Error
    Write-Log "Error details: $($_.ScriptStackTrace)" -Level Error
    exit 1
} finally {
    Complete-Script
}
