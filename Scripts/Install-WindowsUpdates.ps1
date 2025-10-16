<#PSScriptInfo

.VERSION 3.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows WindowsUpdate PSWindowsUpdate

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Basic Windows Update installation.
[Version 2.0.0] - Major refactor: PSWindowsUpdate module support, better error handling, PowerShell 7 compatibility
[Version 2.1.0] - Cleaned up old code and bugs
[Version 3.0.0] - Simplified script, easier usage, minimal logic
#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs all available Windows Updates automatically using PSWindowsUpdate module.

.DESCRIPTION
    Downloads and installs all available Windows Updates. Designed for automated deployment after OOBE.

.EXAMPLE
    .\Install-WindowsUpdates.ps1
    Installs all available updates.

.NOTES
    Version      : 3.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : PowerShell 5.1+, Admin rights
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve Utilities path and import only required modules
$possiblePaths = @(
    (Join-Path $PSScriptRoot 'Utilities'),
    'C:\DenkoICT\Download\Utilities',
    'C:\DenkoICT\Utilities'
)
$utilitiesPath = $null
foreach ($p in $possiblePaths) { if (Test-Path $p) { $utilitiesPath = $p; break } }
if (-not $utilitiesPath) { Write-Error "Could not find Utilities folder in any expected location"; exit 1 }

$loggingModule = Join-Path $utilitiesPath 'Logging.psm1'
$systemModule = Join-Path $utilitiesPath 'System.psm1'
if (-not (Test-Path $loggingModule)) { Write-Error "Logging.psm1 not found in $utilitiesPath"; exit 1 }
if (-not (Test-Path $systemModule)) { Write-Error "System.psm1 not found in $utilitiesPath"; exit 1 }
Import-Module $loggingModule -Force -Global
Import-Module $systemModule -Force -Global
Start-EmergencyTranscript -LogName 'Install-WindowsUpdates.log'

# Verify required functions are available
if (-not (Get-Command Initialize-Script -ErrorAction SilentlyContinue)) {
    Write-Error "Initialize-Script function not available after importing modules"
    exit 1
}
if (-not (Get-Command Complete-Script -ErrorAction SilentlyContinue)) {
    Write-Error "Complete-Script function not available after importing modules"
    exit 1
}

Initialize-Script -RequireAdmin

# Set execution policy for this session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Trust PSGallery to avoid prompts (best-effort)
try { Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}

# Ensure NuGet provider available
if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
}

# Ensure PSWindowsUpdate module installed
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -Scope AllUsers -ErrorAction Stop
}

# Import the module
Import-Module PSWindowsUpdate -Force

try {
    Write-Log "Scanning for Windows Updates..." -Level Info
    $updates = Get-WindowsUpdate -ErrorAction SilentlyContinue

    if (-not $updates) {
        Write-Log "No updates available." -Level Success
        exit 0
    }

    Write-Log "Found $($updates.Count) update(s). Installing..." -Level Info

    # Install all available updates, ignore reboot
    Install-WindowsUpdate -AcceptAll -IgnoreReboot -ErrorAction SilentlyContinue

    Write-Log "Windows Update installation complete." -Level Success
    exit 0
} catch {
    Write-Log "Windows Update installation failed: $($_.Exception.Message)" -Level Error
    exit 1
} finally {
    # Prefer Complete-Script; if unavailable, stop transcript silently
    if (Get-Command Complete-Script -ErrorAction SilentlyContinue) {
        try { Complete-Script } catch { Stop-EmergencyTranscript }
    } else {
        Stop-EmergencyTranscript
    }
}
