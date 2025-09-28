<#PSScriptInfo

.VERSION 1.0.2

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows WinGet Applications Installation Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Installs applications using WinGet package manager.
[Version 1.0.1] - Added 7zip to default applications.
[Version 1.0.2] - Improved error handling and logging.
#>

<#
.SYNOPSIS
    Installs specified applications using WinGet package manager.

.DESCRIPTION
    This script automates the installation of multiple applications using WinGet.
    It includes error handling, progress tracking, and detailed logging of installation results.
    The script can install applications silently and accepts all required agreements automatically.

.PARAMETER Applications
    Array of application IDs to install. Uses default list if not specified.

.PARAMETER LogPath
    Path for installation log file. Creates log in temp directory by default.

.PARAMETER Force
    Forces installation even if application is already installed.

.EXAMPLE
    .\ps_Install-Applications.ps1
    
    Installs default applications (VCRedist and Office).

.EXAMPLE
    .\ps_Install-Applications.ps1 -Applications @("7zip.7zip", "Mozilla.Firefox")
    
    Installs specific applications.

.EXAMPLE
    .\ps_Install-Applications.ps1 -Force
    
    Forces reinstallation of all applications.

.OUTPUTS
    Installation log file with detailed results.

.NOTES
    Version      : 1.0.2
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    
    Requires WinGet to be installed and configured.
    Run ps_Install-Winget.ps1 first if WinGet is not available.
    
    Default applications:
    - Microsoft.VCRedist.2015+.x64 (Visual C++ Redistributable)
    - Microsoft.Office (Microsoft Office Suite)

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Applications = @(
        "Microsoft.VCRedist.2015+.x64",
        "Microsoft.Office",
        "7zip.7zip"
    ),
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\DenkoICT-Applications-$(Get-Date -Format 'yyyyMMdd-HHmmss').log",
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Initialize logging
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $LogPath -Value $logMessage -Force
    
    # Write to console with color
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        default { 'Cyan' }
    }
    
    Write-Host $logMessage -ForegroundColor $color
}

# Check if WinGet is available
function Test-WinGetAvailable {
    try {
        # First check if winget command exists
        $wingetExists = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $wingetExists) {
            Write-Log "WinGet command not found." -Level 'Error'
            return $false
        }
        
        $wingetVersion = & winget --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "WinGet version: $wingetVersion" -Level 'Info'
            return $true
        } else {
            Write-Log "WinGet command exists but returned error code: $LASTEXITCODE" -Level 'Error'
            return $false
        }
    } catch {
        Write-Log "WinGet is not available: $_" -Level 'Error'
        return $false
    }
}

# Install application using WinGet
function Install-Application {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId
    )
    
    Write-Log "Installing $AppId..." -Level 'Info'
    
    try {
        # Build WinGet arguments
        $arguments = @(
            "install"
            "--id", $AppId
            "--accept-source-agreements"
            "--accept-package-agreements"
            "--exact"
            "--silent"
        )
        
        if ($Force) {
            $arguments += "--force"
        }
        
        # Run WinGet
        $process = Start-Process -FilePath "winget" -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        
        # Check exit code
        switch ($process.ExitCode) {
            0 { 
                Write-Log "$AppId installed successfully." -Level 'Success'
                return $true
            }
            -1978335189 { # Already installed
                Write-Log "$AppId is already installed." -Level 'Warning'
                return $true
            }
            -1978335153 { # No applicable update
                Write-Log "$AppId is up to date." -Level 'Info'
                return $true
            }
            default {
                Write-Log "Failed to install $AppId. Exit code: $($process.ExitCode)" -Level 'Error'
                return $false
            }
        }
    }
    catch {
        Write-Log "Exception installing $($AppId): $_" -Level 'Error'
        return $false
    }
}

# Main execution
Write-Log "=== Application Installation Started ===" -Level 'Info'
Write-Log "User: $env:USERNAME" -Level 'Info'
Write-Log "Computer: $env:COMPUTERNAME" -Level 'Info'
Write-Log "Applications to install: $($Applications -join ', ')" -Level 'Info'

# Check WinGet availability
if (-not (Test-WinGetAvailable)) {
    Write-Log "WinGet is not installed. Please run ps_Install-Winget.ps1 first." -Level 'Error'
    exit 1
}

# Install applications
$successCount = 0
$failCount = 0

foreach ($app in $Applications) {
    if (Install-Application -AppId $app) {
        $successCount++
    } else {
        $failCount++
    }
}

# Summary
Write-Log "=== Installation Summary ===" -Level 'Info'
Write-Log "Total applications: $($Applications.Count)" -Level 'Info'
Write-Log "Successful: $successCount" -Level $(if ($successCount -gt 0) { 'Success' } else { 'Info' })
Write-Log "Failed: $failCount" -Level $(if ($failCount -gt 0) { 'Error' } else { 'Info' })
Write-Log "Log file: $LogPath" -Level 'Info'

# Set exit code
$exitCode = if ($failCount -gt 0) { 1 } else { 0 }
exit $exitCode