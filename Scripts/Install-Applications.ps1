# Denko ICT Application Installer
# Part of the Denko ICT Deployment Toolkit
# See RELEASES.md for current version and CHANGELOG.md for changes

#requires -Version 5.1
#requires -RunAsAdministrator

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
    - Integration with Intune deployment tracking

.EXAMPLE
    .\Install-Applications.ps1

.NOTES
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : Admin rights (WinGet will be auto-installed if missing)
    Version Info : See RELEASES.md and CHANGELOG.md in repository root

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Bootstrap initialization using consolidated function
Import-Module (Join-Path $PSScriptRoot 'Utilities\ScriptBootstrap.psm1') -Force -Global
Initialize-DeploymentScript -LogName 'Install-Applications.log' -RequiredModules @('Logging','System','Winget') -RequireAdmin

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

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

    # Build WinGet arguments using helper
    $wingetArgs = New-WinGetInstallArgs -AppId $AppId -AdditionalArgs '--disable-interactivity'
    if ($ForceInstall) {
        $wingetArgs = New-WinGetInstallArgs -AppId $AppId -Force -AdditionalArgs '--disable-interactivity'
        Write-Log "  Force reinstall enabled" -Level Verbose
    }

    # Execute installation
    $startTime = Get-Date
    $tempOut = Join-Path $env:TEMP "winget_$([guid]::NewGuid()).out"
    $tempErr = Join-Path $env:TEMP "winget_$([guid]::NewGuid()).err"

    try {
        $process = Start-Process $WinGetPath -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow `
                                 -RedirectStandardOutput $tempOut `
                                 -RedirectStandardError $tempErr

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
            Write-Log "  ✓ $exitDescription ($([math]::Round($duration, 1))s)" -Level Success
        } else {
            Write-Log "  ✗ $exitDescription (exit: $exitCode, $([math]::Round($duration, 1))s)" -Level Warning

            # Only log critical error messages (skip progress bars and verbose output)
            if (Test-Path $tempErr) {
                $stderrContent = Get-Content $tempErr -Raw -ErrorAction SilentlyContinue
                if ($stderrContent -and $stderrContent.Trim()) {
                    # Filter out progress indicators and keep only actual errors
                    $errorLines = $stderrContent -split "`n" | Where-Object {
                        $_ -match 'error|failed|exception|denied' -and
                        $_ -notmatch '▒|█|%|\['
                    }
                    if ($errorLines) {
                        Write-Log "    Error: $($errorLines -join '; ')" -Level Verbose
                    }
                }
            }
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
        Remove-Item $tempOut, $tempErr -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

try {

    # Ensure WinGet is available and functional (installs if missing)
    Write-Log "Ensuring WinGet is available..." -Level Info
    $wg = Initialize-WinGet
    $wingetPath = $wg.Path
    Write-Log "WinGet ready (v$($wg.Version))" -Level Success

    # Detect architecture
    $isARM64 = $env:PROCESSOR_ARCHITECTURE -eq "ARM64"
    Write-Log "System architecture: $env:PROCESSOR_ARCHITECTURE" -Level Info

    # Install WinGet/CompanyPortal dependencies FIRST using comprehensive dependency installer
    Write-Log "======================================" -Level Info
    Write-Log "Installing Company Portal Dependencies..." -Level Info
    Write-Log "======================================" -Level Info

    $dependencies = @(
        @{
            Id = 'Microsoft.VCLibs.140.00.UWPDesktop'
            DisplayName = 'VC Libraries'
            AppxName = 'Microsoft.VCLibs.140.00.UWPDesktop'
        },
        @{
            Id = 'Microsoft.UI.Xaml.2.8'
            DisplayName = 'UI.Xaml 2.8'
            AppxName = 'Microsoft.UI.Xaml.2.8'
            FallbackSources = @('msstore')
        }
    )

    # Install dependencies (result logged by Install-WinGetDependencies)
    $null = Install-WinGetDependencies -Dependencies $dependencies -WinGetPath $wingetPath

    # Default application set (no parameters accepted)
    $Applications = @(
        "Microsoft.VCRedist.2015+.x64",      # Install VCRedist first (common dependency)
        "Microsoft.Office",
        "Microsoft.Teams",
        "Microsoft.OneDrive",
        "7zip.7zip",
        "Microsoft.WindowsApp",
        "Microsoft.CompanyPortal"            # Dependencies installed above
    )

    # Adjust for ARM64 architecture
    if ($isARM64) {
        Write-Log "ARM64 detected - adjusting package names" -Level Info
        $Applications = $Applications | ForEach-Object {
            # Use regex to replace .x64 suffix pattern
            if ($_ -match '\.x64(\.|$)') {
                $_ -replace '\.x64(\.|$)', '.arm64$1'
            } else {
                $_
            }
        }
        Write-Log "Adjusted applications: $($Applications -join ', ')" -Level Info
    }

    # Install applications
    Write-Log "" -Level Info
    Write-Log "======================================" -Level Info
    Write-Log "Starting installation of $($Applications.Count) applications..." -Level Info
    Write-Log "======================================" -Level Info

    $results = @()
    foreach ($app in $Applications) {
        $result = Install-Application -AppId $app -WinGetPath $wingetPath
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
    Complete-DeploymentScript
}