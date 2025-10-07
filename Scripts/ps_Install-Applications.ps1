<#PSScriptInfo

.VERSION 2.4.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows WinGet Applications Deployment Installation

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial release
[Version 1.1.0] - Added PowerShell 7 installation and improved logging
[Version 2.0.0] - Added WinGet support and enhanced error handling
[Version 2.1.0] - Improved the handling of Teams installation
[Version 2.1.1] - Bugfix: Fixed installation not executing (Start-Process issue) + improved logging with output capture
[Version 2.1.2] - Improved logging and exit code handling for WinGet installations
[Version 2.1.3] - Added refresh of environment PATH after winget installation
[Version 2.2.0] - Simplified installation flow
[Version 2.3.0] - Refactored to use centralized WinGet exit code descriptions from ps_Custom-Functions.ps1
[Version 2.4.0] - Modularized code with helper functions, simplified logging, improved WinGet detection, better error handling
#>

#requires -Version 5.1

<#
.SYNOPSIS
    Installs applications via WinGet package manager.

.DESCRIPTION
    Automates application installation using Windows Package Manager (WinGet).
    Supports ARM64 architecture detection, exit code interpretation, and detailed logging.

    Features:
    - Automatic architecture detection (x64/ARM64)
    - Intelligent exit code handling
    - Detailed installation logging with duration tracking
    - Force reinstall capability
    - Integration with Intune deployment tracking

.PARAMETER Applications
    Array of WinGet application IDs to install.
    Default: Microsoft.PowerShell, VCRedist, Office, Teams, OneDrive, 7zip

.PARAMETER Force
    Force reinstall applications even if already installed.

.PARAMETER SkipLogging
    Skip transcript logging to file.

.EXAMPLE
    .\ps_Install-Applications.ps1
    Installs default application bundle.

.EXAMPLE
    .\ps_Install-Applications.ps1 -Applications @("7zip.7zip", "Microsoft.PowerShell")
    Installs only specified applications.

.EXAMPLE
    .\ps_Install-Applications.ps1 -Force
    Reinstalls all default applications even if already installed.

.NOTES
    Version      : 2.4.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : Admin rights, WinGet installed

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

[CmdletBinding()]
param(
    [string[]]$Applications = @(
        "Microsoft.VCRedist.2015+.x64",
        "Microsoft.Office",
        "Microsoft.Teams",
        "Microsoft.OneDrive",
        "7zip.7zip"
    ),
    
    [switch]$Force,
    [switch]$SkipLogging
)

#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Load custom functions
$functionsPath = Join-Path $PSScriptRoot 'ps_Custom-Functions.ps1'
if (-not (Test-Path $functionsPath)) {
    Write-Error "Required functions file not found: $functionsPath"
    exit 1
}
. $functionsPath

# Initialize logging
if (-not $SkipLogging) {
    $Global:DenkoConfig.LogName = "$($MyInvocation.MyCommand.Name).log"
    Start-Logging
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Test-WinGetCommand {
    <#
    .SYNOPSIS
        Locates WinGet executable path from common installation locations.
    
    .DESCRIPTION
        Searches for winget.exe in PATH and common installation directories.
        Returns the path to the first valid WinGet executable found.
    
    .OUTPUTS
        String path to winget.exe, or $null if not found.
    #>
    [CmdletBinding()]
    param()
    
    Write-Log "Searching for WinGet executable..." -Level Info
    
    # Refresh PATH to ensure latest changes are reflected
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + 
                [System.Environment]::GetEnvironmentVariable("PATH", "User")
    
    # Define search paths in priority order
    $wingetPaths = @(
        # Check if winget is in PATH
        (Get-Command winget.exe -ErrorAction SilentlyContinue).Source,
        
        # Common user installation path
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        
        # System-wide installation (resolve to latest version)
        (Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue | 
         Sort-Object { [version]($_.Path -replace '^.*_(\d+\.\d+\.\d+\.\d+)_.*', '$1') } -Descending | 
         Select-Object -First 1).Path
    )
    
    # Test each path and return first valid one
    foreach ($path in $wingetPaths | Where-Object { $_ }) {
        if (Test-Path $path) {
            Write-Log "Found WinGet at: $path" -Level Success
            return $path
        }
    }
    
    Write-Log "WinGet executable not found in any known location" -Level Error
    return $null
}

function Install-Application {
    <#
    .SYNOPSIS
        Installs a single application using WinGet.
    
    .DESCRIPTION
        Executes WinGet installation for specified application ID with proper
        error handling, exit code interpretation, and duration tracking.
    
    .PARAMETER AppId
        WinGet application ID to install.
    
    .PARAMETER WinGetPath
        Full path to winget.exe executable.
    
    .PARAMETER ForceInstall
        Force reinstall even if already installed.
    
    .OUTPUTS
        Hashtable with installation results including success status, exit code, and duration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,
        
        [Parameter(Mandatory)]
        [string]$WinGetPath,
        
        [switch]$ForceInstall
    )
    
    Write-Log "Installing: $AppId" -Level Info
    
    # Build WinGet arguments
    $wingetArgs = @(
        "install"
        "--id", $AppId
        "--silent"
        "--accept-package-agreements"
        "--accept-source-agreements"
    )
    
    if ($ForceInstall) { 
        $wingetArgs += "--force"
        Write-Log "  Force reinstall enabled" -Level Info
    }
    
    # Execute installation
    $startTime = Get-Date
    
    try {
        $process = Start-Process $WinGetPath -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow `
                                 -RedirectStandardOutput "$env:TEMP\winget_out.txt" `
                                 -RedirectStandardError "$env:TEMP\winget_err.txt"
        
        $exitCode = $process.ExitCode
        $duration = ((Get-Date) - $startTime).TotalSeconds
        
        # Get exit code description
        $exitDescription = Get-WinGetExitCodeDescription -ExitCode $exitCode
        
        # Determine success based on exit codes
        # Success codes: 0 (installed), -1978335189/-1978335135 (already installed), 
        #                -1978334967/-1978334966 (needs reboot but installed)
        $isSuccess = $exitCode -in @(0, -1978335189, -1978335135, -1978334967, -1978334966)
        
        # Build result object
        $result = @{
            AppId = $AppId
            ExitCode = $exitCode
            Description = $exitDescription
            Duration = [math]::Round($duration, 1)
            Success = $isSuccess
        }
        
        # Log result
        if ($isSuccess) {
            Write-Log "  ✓ $exitDescription (${duration}s)" -Level Success
        } else {
            Write-Log "  ✗ $exitDescription (exit: $exitCode, ${duration}s)" -Level Warning
        }
        
        return $result
        
    } catch {
        Write-Log "  ✗ Exception during installation: $($_.Exception.Message)" -Level Error
        
        return @{
            AppId = $AppId
            ExitCode = -1
            Description = "Exception: $($_.Exception.Message)"
            Duration = ((Get-Date) - $startTime).TotalSeconds
            Success = $false
        }
        
    } finally {
        # Clean up temporary output files
        Remove-Item "$env:TEMP\winget_out.txt", "$env:TEMP\winget_err.txt" -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

try {
    Assert-AdminRights
    
    # Detect architecture and adjust package names if needed
    $isARM64 = $env:PROCESSOR_ARCHITECTURE -eq "ARM64"
    Write-Log "System architecture: $env:PROCESSOR_ARCHITECTURE" -Level Info
    
    if ($isARM64) {
        Write-Log "ARM64 detected - adjusting package names" -Level Info
        $Applications = $Applications | ForEach-Object {
            # Use regex to replace .x64 suffix pattern (e.g., VCRedist.2015+.x64 -> VCRedist.2015+.arm64)
            # This prevents unintended replacements in package names containing "x64"
            if ($_ -match '\.x64(\.|$)') {
                $_ -replace '\.x64(\.|$)', '.arm64$1'
            } else {
                $_
            }
        }
        Write-Log "Adjusted applications: $($Applications -join ', ')" -Level Info
    }
    
    # Locate WinGet executable
    $wingetPath = Test-WinGetCommand
    if (-not $wingetPath) {
        Write-Log "WinGet not found - cannot proceed" -Level Error
        Write-Log "Please ensure Windows App Installer (WinGet) is installed" -Level Error
        exit 1
    }
    
    # Verify WinGet functionality
    Write-Log "Verifying WinGet functionality..." -Level Info
    try {
        $wingetVersion = & $wingetPath --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet returned non-zero exit code: $LASTEXITCODE"
        }
        Write-Log "WinGet version: $wingetVersion" -Level Success
    } catch {
        Write-Log "WinGet not functional: $_" -Level Error
        exit 1
    }
    
    # Install applications
    Write-Log "======================================" -Level Info
    Write-Log "Starting installation of $($Applications.Count) applications..." -Level Info
    Write-Log "======================================" -Level Info
    
    $results = @()
    foreach ($app in $Applications) {
        $result = Install-Application -AppId $app -WinGetPath $wingetPath -ForceInstall:$Force
        $results += $result
    }
    
    # Generate summary
    $successResults = @($results | Where-Object { $_.Success })
    $failedResults = @($results | Where-Object { -not $_.Success })
    $successCount = $successResults.Count
    $failedCount = $failedResults.Count
    $totalDuration = ($results | Measure-Object -Property Duration -Sum).Sum
    
    Write-Log "" -Level Info
    Write-Log "======================================" -Level Info
    Write-Log "Installation Summary:" -Level Info
    Write-Log "  Total applications: $($Applications.Count)" -Level Info
    Write-Log "  Successfully installed: $successCount" -Level $(if ($successCount -gt 0) { 'Success' } else { 'Info' })
    Write-Log "  Failed: $failedCount" -Level $(if ($failedCount -gt 0) { 'Warning' } else { 'Info' })
    Write-Log "  Total duration: $([math]::Round($totalDuration, 1))s" -Level Info
    Write-Log "======================================" -Level Info
    
    # Set Intune success marker if all installations succeeded
    if ($failedCount -eq 0) {
        Set-IntuneSuccess -AppName 'ApplicationBundle' -Version (Get-Date -Format 'yyyy.MM.dd')
        Write-Log "All applications installed successfully" -Level Success
    } else {
        Write-Log "Some applications failed to install" -Level Warning
    }
    
    exit $(if ($failedCount -gt 0) { 1 } else { 0 })
    
} catch {
    Write-Log "Critical error: $($_.Exception.Message)" -Level Error
    if ($_.ScriptStackTrace) {
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    }
    exit 1
} finally {
    if (-not $SkipLogging) {
        Stop-Logging
    }
}