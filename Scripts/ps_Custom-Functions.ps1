<#PSScriptInfo

.VERSION 5.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Utilities Logging Functions Framework Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial release with basic logging and admin checks
[Version 2.0.0] - Added registry functions and Intune integration
[Version 2.1.0] - Added WinGet detection and module installation
[Version 3.0.0] - Major update: Added network stability functions, WinGet/MSI exit code descriptions, graceful error handling, completion banners
[Version 4.0.0] - Stability release: Consolidated network functions, refactored retry logic with do-while/until patterns, removed duplicates, simplified code
[Version 5.0.0] - Minification: Removed unnecessary functions, merged Test-WinGet with Get-WinGetPath, merged Import-FunctionsFromGitHub into Get-RemoteScript, renamed deployment functions, converted MSI functions to comments
#>

#requires -Version 5.1

<#
.SYNOPSIS
    Core utility functions for DenkoICT PowerShell deployment scripts.

.DESCRIPTION
    Comprehensive function library providing common functionality across all
    DenkoICT deployment scripts. Includes logging, error handling, network
    validation, exit code interpretation, and system utilities.

.NOTES
    Version      : 5.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    Requires     : PowerShell 5.1+

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT

.EXAMPLE
    . .\ps_Custom-Functions.ps1
    Dot-source this file to import all functions into your script.

.EXAMPLE
    Start-Logging -LogName 'MyScript.log'
    Write-Log "Processing started" -Level Info
    Stop-Logging
    Standard logging pattern for scripts.
#>

Set-StrictMode -Version Latest

# Global configuration
$Global:DenkoConfig = @{
    LogPath = 'C:\DenkoICT\Logs'
    LogName = "$($MyInvocation.MyCommand.Name).log"
    TranscriptActive = $false
}

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Write-Log {
    <#
    .SYNOPSIS
        Writes timestamped log messages with color support and proper PowerShell streams.

    .DESCRIPTION
        Enhanced logging function that writes to console with colors, uses appropriate
        PowerShell streams for pipeline compatibility, and integrates with transcript logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info','Success','Warning','Error','Verbose','Debug')]
        [string]$Level = 'Info'
    )

    process {
        # Handle empty strings for blank lines
        if ([string]::IsNullOrEmpty($Message)) {
            Write-Host ""
            return
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logEntry = "[$timestamp] [$Level] $Message"

        # Color mapping
        $color = @{
            Success = 'Green'
            Warning = 'Yellow'
            Error   = 'Red'
            Info    = 'Cyan'
            Verbose = 'Gray'
            Debug   = 'Magenta'
        }[$Level]

        # Write to console with color
        Write-Host $logEntry -ForegroundColor $color
    }
}

function Initialize-LogDirectory {
    <#
    .SYNOPSIS
        Creates log directory if it doesn't exist.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = $Global:DenkoConfig.LogPath
    )

    if (-not (Test-Path $Path)) {
        try {
            $null = New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
            Write-Log "Created log directory: $Path" -Level Info
        } catch {
            Write-Warning "Failed to create log directory '$Path': $_"
            throw
        }
    }
}

function Start-Logging {
    <#
    .SYNOPSIS
        Starts transcript logging for the current script.
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath = $Global:DenkoConfig.LogPath,
        [string]$LogName = $Global:DenkoConfig.LogName
    )

    try {
        Initialize-LogDirectory -Path $LogPath

        $logFile = Join-Path -Path $LogPath -ChildPath $LogName

        # Rotate log if too large (>10MB)
        if (Test-Path $logFile) {
            $size = (Get-Item $logFile).Length / 1MB
            if ($size -gt 10) {
                $backupName = $LogName -replace '\.log$', ".old.log"
                $backupPath = Join-Path $LogPath $backupName
                Move-Item -Path $logFile -Destination $backupPath -Force
                Write-Log "Rotated log file (was $([math]::Round($size,2))MB)" -Level Info
            }
        }

        Start-Transcript -Path $logFile -Append -ErrorAction Stop | Out-Null
        $Global:DenkoConfig.TranscriptActive = $true
        Write-Log "Started logging to: $logFile" -Level Info
    } catch {
        Write-Warning "Failed to start transcript: $_"
        $Global:DenkoConfig.TranscriptActive = $false
    }
}

function Stop-Logging {
    <#
    .SYNOPSIS
        Stops transcript logging if active.
    #>
    [CmdletBinding()]
    param()

    if ($Global:DenkoConfig.TranscriptActive) {
        try {
            Stop-Transcript | Out-Null
            $Global:DenkoConfig.TranscriptActive = $false
        } catch {
            Write-Verbose "Transcript stop failed or was not active: $_"
        }
    }
}

function Initialize-Environment {
    <#
    .SYNOPSIS
        Initializes the script environment with logging.
    #>
    [CmdletBinding()]
    param()

    try {
        Initialize-LogDirectory -Path $Global:DenkoConfig.LogPath

        if (-not $Global:DenkoConfig.TranscriptActive) {
            Start-Logging
        }

        Write-Log "Environment initialized" -Level Verbose
    } catch {
        Write-Warning "Failed to initialize environment: $_"
    }
}

function Stop-Environment {
    <#
    .SYNOPSIS
        Cleans up the script environment and stops logging.
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Log "Stopping environment" -Level Verbose
        Stop-Logging
    } catch {
        Write-Warning "Failed to stop environment: $_"
    }
}

function Copy-ExternalLogs {
    <#
    .SYNOPSIS
        Collects logs from autounattend.xml setup scripts.

    .DESCRIPTION
        Copies logs created during Windows setup (WinPE/Specialize/FirstLogon) to the central log directory.
    #>
    [CmdletBinding()]
    param(
        [string]$LogDirectory = $Global:DenkoConfig.LogPath
    )

    if (-not $LogDirectory -or -not (Test-Path $LogDirectory)) {
        Write-Log "Log directory not available. Skipping external logs." -Level Warning
        return
    }

    $logPaths = @(
        'C:\Windows\Setup\Scripts\SetComputerName.log'
        'C:\Windows\Setup\Scripts\RemovePackages.log'
        'C:\Windows\Setup\Scripts\RemoveCapabilities.log'
        'C:\Windows\Setup\Scripts\RemoveFeatures.log'
        'C:\Windows\Setup\Scripts\Specialize.log'
        (Join-Path $env:TEMP 'UserOnce.log')
        'C:\Windows\Setup\Scripts\DefaultUser.log'
        'C:\Windows\Setup\Scripts\FirstLogon.log'
    )

    $collected = 0
    foreach ($path in ($logPaths | Sort-Object -Unique)) {
        if (-not $path -or -not (Test-Path $path -PathType Leaf)) {
            continue
        }

        try {
            $item = Get-Item -Path $path -ErrorAction Stop
            $destination = Join-Path $LogDirectory $item.Name

            if (Test-Path $destination) {
                # Overwrite existing log file
                Remove-Item -Path $destination -Force -ErrorAction SilentlyContinue
            }

            Copy-Item -Path $item.FullName -Destination $destination -Force
            $collected++
        } catch {
            Write-Log "Failed to copy log '$path': $_" -Level Debug
        }
    }

    if ($collected -gt 0) {
        Write-Log "Copied $collected external log(s)" -Level Info
    }
}

# ============================================================================
# ADMIN & SYSTEM FUNCTIONS
# ============================================================================

function Test-AdminRights {
    <#
    .SYNOPSIS
        Checks if script is running with admin privileges.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        Write-Warning "Unable to determine admin status: $_"
        return $false
    }
}

function Assert-AdminRights {
    <#
    .SYNOPSIS
        Ensures script has admin rights or throws error.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-AdminRights)) {
        throw "This script requires administrative privileges. Please run as Administrator."
    }
    Write-Log "Running with administrative privileges" -Level Verbose
}

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Gets basic system information.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop

        return @{
            ComputerName = $cs.Name
            Domain = $cs.Domain
            Manufacturer = $cs.Manufacturer
            Model = $cs.Model
            OS = $os.Caption
            OSVersion = $os.Version
            LastBoot = $os.LastBootUpTime
            Architecture = $env:PROCESSOR_ARCHITECTURE
        }
    } catch {
        Write-Log "Failed to get system info: $_" -Level Warning
        return @{}
    }
}

# ============================================================================
# REGISTRY FUNCTIONS
# ============================================================================

function Set-RegistryValue {
    <#
    .SYNOPSIS
        Sets a registry value, creating the path if needed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        $Value,

        [ValidateSet('String','DWord','Binary','ExpandString','MultiString','QWord')]
        [string]$Type = 'String'
    )

    try {
        if (-not (Test-Path $Path)) {
            $null = New-Item -Path $Path -Force -ErrorAction Stop
            Write-Log "Created registry path: $Path" -Level Verbose
        }

        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        Write-Log "Set registry value: $Path\$Name = $Value" -Level Success
    } catch {
        Write-Log "Failed to set registry value '$Name' at '$Path': $_" -Level Error
        throw
    }
}

function Set-IntuneSuccess {
    <#
    .SYNOPSIS
        Records Intune deployment success in registry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [string]$Version = '1.0.0'
    )

    $intuneKey = 'HKLM:\SOFTWARE\DenkoICT\Intune'

    try {
        Set-RegistryValue -Path $intuneKey -Name $AppName -Value $Version
        Write-Log "Recorded Intune success for $AppName ($Version)" -Level Success
    } catch {
        Write-Log "Failed to record Intune success for $AppName : $_" -Level Warning
    }
}

# ============================================================================
# NETWORK FUNCTIONS
# ============================================================================

function Test-NetworkConnectivity {
    <#
    .SYNOPSIS
        Tests if network connection is available.

    .DESCRIPTION
        Performs a lightweight network connectivity test by attempting to reach a known URL.
        Uses HEAD request to minimize data transfer.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$TestUrl = "https://raw.githubusercontent.com",
        [int]$TimeoutSeconds = 5
    )

    try {
        $request = [System.Net.WebRequest]::Create($TestUrl)
        $request.Timeout = $TimeoutSeconds * 1000
        $request.Method = "HEAD"
        $response = $request.GetResponse()
        $response.Close()
        return $true
    } catch {
        Write-Log "Network connectivity test failed: $_" -Level Debug
        return $false
    }
}

function Wait-ForNetworkStability {
    <#
    .SYNOPSIS
        Waits for stable network connectivity using robust retry pattern.

    .DESCRIPTION
        Uses do-until loop to wait for network connectivity with configurable retries.
        Returns true if network becomes available, false if max retries exceeded.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [int]$MaxRetries = 5,
        [int]$DelaySeconds = 10,
        [switch]$ContinuousCheck
    )

    Write-Log "Checking network connectivity..." -Level Info

    $attempt = 0

    do {
        $attempt++

        if (Test-NetworkConnectivity) {
            Write-Log "Network connectivity confirmed (attempt $attempt/$MaxRetries)" -Level Success

            if ($ContinuousCheck) {
                Write-Log "Performing stability check..." -Level Verbose

                $stableChecks = 0
                do {
                    Start-Sleep -Seconds 2
                    if (Test-NetworkConnectivity) {
                        $stableChecks++
                    } else {
                        Write-Log "Network unstable, retrying..." -Level Warning
                        break
                    }
                } until ($stableChecks -ge 3)

                if ($stableChecks -ge 3) {
                    Write-Log "Network connection is stable" -Level Success
                    return $true
                }
            } else {
                return $true
            }
        }

        if ($attempt -lt $MaxRetries) {
            Write-Log "Network not available (attempt $attempt/$MaxRetries). Waiting $DelaySeconds seconds..." -Level Warning
            Start-Sleep -Seconds $DelaySeconds
        }

    } until ($attempt -ge $MaxRetries)

    Write-Log "Network connectivity check failed after $MaxRetries attempts" -Level Error
    return $false
}

# ============================================================================
# MODULE & PACKAGE FUNCTIONS
# ============================================================================

function Install-RequiredModule {
    <#
    .SYNOPSIS
        Installs a PowerShell module if not present.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [string]$MinimumVersion
    )

    try {
        $module = Get-Module -ListAvailable -Name $ModuleName |
                  Sort-Object Version -Descending |
                  Select-Object -First 1

        if (-not $module -or ($MinimumVersion -and $module.Version -lt $MinimumVersion)) {
            Write-Log "Installing module $ModuleName..." -Level Info

            Install-Module -Name $ModuleName -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
            Write-Log "Installed $ModuleName successfully" -Level Success
            return $true
        }

        Write-Log "$ModuleName already installed (v$($module.Version))" -Level Verbose
        return $true
    } catch {
        Write-Log "Failed to install $ModuleName : $_" -Level Error
        return $false
    }
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes a script block with retry logic using do-while pattern.

    .DESCRIPTION
        Implements robust retry mechanism with exponential backoff option.
        Validates network connectivity before network-dependent operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 2,
        [switch]$ExponentialBackoff,
        [switch]$RequiresNetwork
    )

    $attempt = 0

    do {
        $attempt++

        try {
            # Validate network if required
            if ($RequiresNetwork -and $attempt -gt 1) {
                Write-Log "Validating network connectivity before retry..." -Level Verbose
                if (-not (Test-NetworkConnectivity)) {
                    Write-Log "Network unavailable - waiting before retry..." -Level Warning
                    Start-Sleep -Seconds 5
                    if (-not (Test-NetworkConnectivity)) {
                        throw "Network connectivity required but unavailable"
                    }
                }
            }

            $result = & $ScriptBlock
            Write-Log "Operation succeeded on attempt $attempt" -Level Verbose
            return $result
        } catch {
            if ($attempt -ge $MaxAttempts) {
                Write-Log "All $MaxAttempts attempts failed" -Level Error
                Write-Log "Last error: $($_.Exception.Message)" -Level Error
                throw
            }

            $delay = if ($ExponentialBackoff) {
                $DelaySeconds * [Math]::Pow(2, $attempt - 1)
            } else {
                $DelaySeconds
            }

            Write-Log "Attempt $attempt/$MaxAttempts failed: $($_.Exception.Message)" -Level Warning
            Write-Log "Retrying in $delay seconds..." -Level Info
            Start-Sleep -Seconds $delay
        }
    } while ($attempt -lt $MaxAttempts)
}

# ============================================================================
# WINGET FUNCTIONS
# ============================================================================

function Test-WinGet {
    <#
    .SYNOPSIS
        Checks if WinGet is installed, functional, and returns path and version info.

    .DESCRIPTION
        Unified WinGet detection function that locates winget.exe, verifies it works,
        and includes exit code descriptions for troubleshooting. Replaces Get-WinGetPath
        and Test-WinGetAvailable with a single comprehensive function.

    .PARAMETER ReturnPath
        If specified, returns the path to winget.exe instead of boolean.

    .OUTPUTS
        Returns PSCustomObject with WinGetPath, IsAvailable, Version properties.
        If ReturnPath is specified and WinGet is not found, returns $null.

    .EXAMPLE
        $winget = Test-WinGet
        if ($winget.IsAvailable) {
            Write-Host "WinGet v$($winget.Version) found at $($winget.WinGetPath)"
        }

    .NOTES
        WinGet Exit Codes:
        0 = Success
        -1978335231 = Internal Error
        -1978335230 = Invalid command line arguments
        -1978335229 = Executing command failed
        -1978335226 = Running ShellExecute failed (installer failed)
        -1978335224 = Downloading installer failed
        -1978335216 = No applicable installer for the current system
        -1978335215 = Installer hash mismatch
        -1978335212 = No packages found
        -1978335210 = Multiple packages found
        -1978335207 = Command requires administrator privileges
        -1978335189 = No applicable update found (already up-to-date)
        -1978335188 = Upgrade all completed with failures
        -1978335174 = Operation blocked by Group Policy
        -1978335135 = Package already installed
        -1978334975 = Application currently running
        -1978334974 = Another installation in progress
        -1978334973 = File in use
        -1978334972 = Missing dependency
        -1978334971 = Disk full
        -1978334970 = Insufficient memory
        -1978334969 = No network connection
        -1978334967 = Reboot required to finish
        -1978334966 = Reboot required to install
        -1978334964 = Cancelled by user
        -1978334963 = Another version already installed
        -1978334962 = Downgrade attempt (higher version installed)
        -1978334961 = Blocked by policy
        -1978334960 = Failed to install dependencies
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [switch]$ReturnPath
    )

    $result = [PSCustomObject]@{
        WinGetPath = $null
        IsAvailable = $false
        Version = $null
    }

    try {
        # Try to find winget in PATH first
        $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            $result.WinGetPath = $wingetCmd.Source
        } else {
            # Search WindowsApps folder
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
                    $result.WinGetPath = $resolved.Path
                    break
                }
            }
        }

        # If path found, test if it works
        if ($result.WinGetPath) {
            $versionOutput = & $result.WinGetPath --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                $result.IsAvailable = $true
                $result.Version = $versionOutput -replace '^v', ''
                Write-Log "WinGet is available - Version: $($result.Version)" -Level Verbose
            } else {
                Write-Log "WinGet found but not functional (exit code: $LASTEXITCODE)" -Level Debug
            }
        } else {
            Write-Log "WinGet executable not found" -Level Debug
        }
    } catch {
        Write-Log "WinGet check failed: $_" -Level Debug
    }

    # Return based on parameter
    if ($ReturnPath) {
        return $result.WinGetPath
    }
    return $result
}

function Get-WinGetExitCodeDescription {
    <#
    .SYNOPSIS
        Translates WinGet exit codes to human-readable descriptions.

    .DESCRIPTION
        Provides detailed error descriptions for WinGet exit codes.
        Useful for logging and troubleshooting installation issues.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int]$ExitCode
    )

    $exitCodes = @{
        0 = "Success"
        -1978335231 = "Internal Error"
        -1978335230 = "Invalid command line arguments"
        -1978335229 = "Executing command failed"
        -1978335226 = "Running ShellExecute failed (installer failed)"
        -1978335224 = "Downloading installer failed"
        -1978335216 = "No applicable installer for the current system"
        -1978335215 = "Installer hash mismatch"
        -1978335212 = "No packages found"
        -1978335210 = "Multiple packages found"
        -1978335207 = "Command requires administrator privileges"
        -1978335189 = "No applicable update found (already up-to-date)"
        -1978335188 = "Upgrade all completed with failures"
        -1978335174 = "Operation blocked by Group Policy"
        -1978335135 = "Package already installed"
        -1978334975 = "Application currently running"
        -1978334974 = "Another installation in progress"
        -1978334973 = "File in use"
        -1978334972 = "Missing dependency"
        -1978334971 = "Disk full"
        -1978334970 = "Insufficient memory"
        -1978334969 = "No network connection"
        -1978334967 = "Reboot required to finish"
        -1978334966 = "Reboot required to install"
        -1978334964 = "Cancelled by user"
        -1978334963 = "Another version already installed"
        -1978334962 = "Downgrade attempt (higher version installed)"
        -1978334961 = "Blocked by policy"
        -1978334960 = "Failed to install dependencies"
    }

    if ($exitCodes.ContainsKey($ExitCode)) {
        return $exitCodes[$ExitCode]
    }
    return "Unknown exit code"
}

function Get-MSIExitCodeDescription {
    <#
    .SYNOPSIS
        Translates MSI installer exit codes to human-readable descriptions.

    .DESCRIPTION
        Provides detailed error descriptions for Windows Installer (MSI) exit codes.
        Useful for logging and troubleshooting MSI installation issues.

    .NOTES
        MSI Exit Codes Reference:
        0 = ERROR_SUCCESS - Action completed successfully
        1602 = ERROR_INSTALL_USEREXIT - User cancelled installation
        1603 = ERROR_INSTALL_FAILURE - Fatal error during installation
        1608 = ERROR_UNKNOWN_PROPERTY - Unknown property
        1609 = ERROR_INVALID_HANDLE_STATE - Handle is in an invalid state
        1614 = ERROR_PRODUCT_UNINSTALLED - Product is uninstalled
        1618 = ERROR_INSTALL_ALREADY_RUNNING - Another installation is already in progress
        1619 = ERROR_INSTALL_PACKAGE_OPEN_FAILED - Installation package could not be opened
        1620 = ERROR_INSTALL_PACKAGE_INVALID - Installation package is invalid
        1624 = ERROR_INSTALL_TRANSFORM_FAILURE - Error applying transforms
        1635 = ERROR_PATCH_PACKAGE_OPEN_FAILED - Patch package could not be opened
        1636 = ERROR_PATCH_PACKAGE_INVALID - Patch package is invalid
        1638 = ERROR_PRODUCT_VERSION - Another version of this product is already installed
        1639 = ERROR_INVALID_COMMAND_LINE - Invalid command line argument
        1640 = ERROR_INSTALL_REMOTE_DISALLOWED - Installation from Terminal Server not permitted
        1641 = ERROR_SUCCESS_REBOOT_INITIATED - The installer has started a reboot
        1644 = ERROR_INSTALL_TRANSFORM_REJECTED - Customizations not permitted by policy
        1707 = ERROR_SUCCESS_PRODUCT_INSTALLED - Product already installed
        3010 = ERROR_SUCCESS_REBOOT_REQUIRED - A reboot is required to complete the install
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [int]$ExitCode
    )

    $exitCodes = @{
        0 = @{ Name = "ERROR_SUCCESS"; Description = "Action completed successfully" }
        1602 = @{ Name = "ERROR_INSTALL_USEREXIT"; Description = "User cancelled installation" }
        1603 = @{ Name = "ERROR_INSTALL_FAILURE"; Description = "Fatal error during installation" }
        1608 = @{ Name = "ERROR_UNKNOWN_PROPERTY"; Description = "Unknown property" }
        1609 = @{ Name = "ERROR_INVALID_HANDLE_STATE"; Description = "Handle is in an invalid state" }
        1614 = @{ Name = "ERROR_PRODUCT_UNINSTALLED"; Description = "Product is uninstalled" }
        1618 = @{ Name = "ERROR_INSTALL_ALREADY_RUNNING"; Description = "Another installation is already in progress" }
        1619 = @{ Name = "ERROR_INSTALL_PACKAGE_OPEN_FAILED"; Description = "Installation package could not be opened" }
        1620 = @{ Name = "ERROR_INSTALL_PACKAGE_INVALID"; Description = "Installation package is invalid" }
        1624 = @{ Name = "ERROR_INSTALL_TRANSFORM_FAILURE"; Description = "Error applying transforms" }
        1635 = @{ Name = "ERROR_PATCH_PACKAGE_OPEN_FAILED"; Description = "Patch package could not be opened" }
        1636 = @{ Name = "ERROR_PATCH_PACKAGE_INVALID"; Description = "Patch package is invalid" }
        1638 = @{ Name = "ERROR_PRODUCT_VERSION"; Description = "Another version of this product is already installed" }
        1639 = @{ Name = "ERROR_INVALID_COMMAND_LINE"; Description = "Invalid command line argument" }
        1640 = @{ Name = "ERROR_INSTALL_REMOTE_DISALLOWED"; Description = "Installation from Terminal Server not permitted" }
        1641 = @{ Name = "ERROR_SUCCESS_REBOOT_INITIATED"; Description = "The installer has started a reboot" }
        1644 = @{ Name = "ERROR_INSTALL_TRANSFORM_REJECTED"; Description = "Customizations not permitted by policy" }
        1707 = @{ Name = "ERROR_SUCCESS_PRODUCT_INSTALLED"; Description = "Product already installed" }
        3010 = @{ Name = "ERROR_SUCCESS_REBOOT_REQUIRED"; Description = "A reboot is required to complete the install" }
    }

    if ($exitCodes.ContainsKey($ExitCode)) {
        return [PSCustomObject]@{
            ExitCode = $ExitCode
            Name = $exitCodes[$ExitCode].Name
            Description = $exitCodes[$ExitCode].Description
        }
    }

    return [PSCustomObject]@{
        ExitCode = $ExitCode
        Name = "UNKNOWN_ERROR"
        Description = "Unknown exit code"
    }
}

# ============================================================================
# DOWNLOAD & IMPORT FUNCTIONS
# ============================================================================

function Get-RemoteScript {
    <#
    .SYNOPSIS
        Downloads scripts from GitHub with retry logic and optional hash verification.

    .DESCRIPTION
        Enhanced download function that can download single or multiple scripts.
        Uses BITS transfer for modern, fast downloading. Falls back to WebClient if needed.
        Preserves UTF-8 encoding for PowerShell compatibility.
        Supports SHA256 hash verification for security.
        Can automatically download all missing deployment scripts from GitHub.

    .PARAMETER ScriptName
        Name of the script to download. If not specified, checks for all missing scripts.

    .PARAMETER ScriptUrl
        Full URL to download script from. If not specified, builds from GitHub repo.

    .PARAMETER SavePath
        Local path to save the script. If not specified, saves to Download directory.

    .PARAMETER ExpectedHash
        Optional SHA256 hash for verification.

    .PARAMETER DownloadAll
        Downloads all missing scripts from the GitHub repository.

    .PARAMETER BaseUrl
        Base URL for GitHub repository (default: main branch).

    .PARAMETER MaxRetries
        Maximum retry attempts (default: 3).

    .PARAMETER TimeoutSeconds
        Timeout for each download attempt (default: 30).

    .EXAMPLE
        Get-RemoteScript -ScriptName "ps_Custom-Functions.ps1"
        Downloads the custom functions script.

    .EXAMPLE
        Get-RemoteScript -DownloadAll
        Downloads all missing deployment scripts from GitHub.

    .NOTES
        Scripts that will be downloaded when using -DownloadAll:
        - ps_Custom-Functions.ps1
        - ps_Deploy-Device.ps1
        - ps_DisableFirstLogonAnimation.ps1
        - ps_Get-InstalledSoftware.ps1
        - ps_Get-SerialNumber.ps1
        - ps_Init-Deployment.ps1
        - ps_Install-Applications.ps1
        - ps_Install-Drivers.ps1
        - ps_Install-MSI.ps1
        - ps_Install-PowerShell7.ps1
        - ps_Install-WindowsUpdates.ps1
        - ps_Install-Winget.ps1
        - ps_OOBE-Requirement.ps1
        - ps_Remove-Bloat.ps1
        - ps_Set-Wallpaper.ps1
        - ps_Update-AllApps.ps1
    #>
    [CmdletBinding(DefaultParameterSetName = 'Single')]
    [OutputType([bool])]
    param(
        [Parameter(ParameterSetName = 'Single')]
        [string]$ScriptName,

        [Parameter(ParameterSetName = 'Single')]
        [string]$ScriptUrl,

        [Parameter(ParameterSetName = 'Single')]
        [string]$SavePath,

        [Parameter(ParameterSetName = 'Single')]
        [string]$ExpectedHash,

        [Parameter(ParameterSetName = 'All', Mandatory)]
        [switch]$DownloadAll,

        [string]$BaseUrl = "https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts",

        [string]$DownloadDir = 'C:\DenkoICT\Download',

        [int]$MaxRetries = 3,

        [int]$TimeoutSeconds = 30
    )

    # List of all deployment scripts
    $allScripts = @(
        'ps_Custom-Functions.ps1'
        'ps_Deploy-Device.ps1'
        'ps_DisableFirstLogonAnimation.ps1'
        'ps_Get-InstalledSoftware.ps1'
        'ps_Get-SerialNumber.ps1'
        'ps_Init-Deployment.ps1'
        'ps_Install-Applications.ps1'
        'ps_Install-Drivers.ps1'
        'ps_Install-MSI.ps1'
        'ps_Install-PowerShell7.ps1'
        'ps_Install-WindowsUpdates.ps1'
        'ps_Install-Winget.ps1'
        'ps_OOBE-Requirement.ps1'
        'ps_Remove-Bloat.ps1'
        'ps_Set-Wallpaper.ps1'
        'ps_Update-AllApps.ps1'
    )

    # Ensure download directory exists
    if (-not (Test-Path $DownloadDir)) {
        $null = New-Item -Path $DownloadDir -ItemType Directory -Force
    }

    # Handle DownloadAll mode
    if ($DownloadAll) {
        Write-Log "Checking for missing scripts in $DownloadDir" -Level Info
        $missingScripts = @()

        foreach ($script in $allScripts) {
            $localPath = Join-Path $DownloadDir $script
            if (-not (Test-Path $localPath)) {
                $missingScripts += $script
            }
        }

        if ($missingScripts.Count -eq 0) {
            Write-Log "All scripts are present, nothing to download" -Level Success
            return $true
        }

        Write-Log "Found $($missingScripts.Count) missing script(s), downloading..." -Level Info
        $successCount = 0
        $failCount = 0

        foreach ($script in $missingScripts) {
            $url = "$BaseUrl/$script"
            $path = Join-Path $DownloadDir $script

            if (Get-RemoteScript -ScriptUrl $url -SavePath $path -MaxRetries $MaxRetries) {
                $successCount++
            } else {
                $failCount++
                Write-Log "Failed to download $script" -Level Warning
            }
        }

        Write-Log "Downloaded $successCount script(s), $failCount failed" -Level Info
        return ($failCount -eq 0)
    }

    # Handle single script download
    if (-not $ScriptUrl -and $ScriptName) {
        $ScriptUrl = "$BaseUrl/$ScriptName"
    }

    if (-not $SavePath -and $ScriptName) {
        $SavePath = Join-Path $DownloadDir $ScriptName
    }

    if (-not $ScriptUrl -or -not $SavePath) {
        Write-Log "Either ScriptUrl and SavePath or ScriptName must be provided" -Level Error
        return $false
    }

    $directory = Split-Path $SavePath -Parent
    if (-not (Test-Path $directory)) {
        $null = New-Item -Path $directory -ItemType Directory -Force
    }

    $attempt = 0

    do {
        $attempt++

        try {
            Write-Log "Downloading from $ScriptUrl (attempt $attempt/$MaxRetries)" -Level Info

            # Try BITS transfer first (modern and fast)
            try {
                Import-Module BitsTransfer -ErrorAction Stop
                Start-BitsTransfer -Source $ScriptUrl -Destination $SavePath -ErrorAction Stop
                Write-Log "Downloaded using BITS transfer" -Level Verbose
            } catch {
                # Fallback to WebClient
                Write-Log "BITS transfer failed, using WebClient..." -Level Debug
                $webClient = New-Object System.Net.WebClient
                $webClient.Encoding = [System.Text.Encoding]::UTF8
                $content = $webClient.DownloadString($ScriptUrl)

                # Write with UTF-8 no-BOM encoding
                [System.IO.File]::WriteAllText($SavePath, $content, (New-Object System.Text.UTF8Encoding $false))
            }

            # Verify hash if provided
            if ($ExpectedHash) {
                Write-Log "Verifying SHA256 hash..." -Level Info
                $fileHash = (Get-FileHash -Path $SavePath -Algorithm SHA256).Hash

                if ($fileHash -ne $ExpectedHash) {
                    Write-Log "Hash verification failed!" -Level Error
                    Write-Log "  Expected: $ExpectedHash" -Level Error
                    Write-Log "  Actual:   $fileHash" -Level Error
                    Remove-Item -Path $SavePath -Force -ErrorAction SilentlyContinue
                    throw "Hash mismatch - file may be corrupted or tampered with"
                }

                Write-Log "Hash verification successful" -Level Success
            }

            Write-Log "Download successful: $(Split-Path $SavePath -Leaf)" -Level Success
            return $true
        } catch {
            if ($attempt -ge $MaxRetries) {
                Write-Log "Download failed after $MaxRetries attempts: $_" -Level Error
                return $false
            }

            Write-Log "Download attempt $attempt failed: $_" -Level Warning
            Start-Sleep -Seconds 5
        }
    } while ($attempt -lt $MaxRetries)

    return $false
}

# ============================================================================
# DEPLOYMENT TRACKING FUNCTIONS
# ============================================================================

function Set-DeploymentStatus {
    <#
    .SYNOPSIS
        Records deployment step status in registry.

    .DESCRIPTION
        Stores deployment step status, timestamp, and details in registry
        for tracking and reporting purposes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepName,

        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failed', 'Skipped', 'Running')]
        [string]$Status,

        [string]$ErrorMessage,

        [int]$ExitCode,

        [string]$Version
    )

    $deploymentKey = 'HKLM:\SOFTWARE\DenkoICT\Deployment\Steps'

    try {
        if (-not (Test-Path $deploymentKey)) {
            $null = New-Item -Path $deploymentKey -Force -ErrorAction Stop
        }

        $stepKey = Join-Path $deploymentKey $StepName
        if (-not (Test-Path $stepKey)) {
            $null = New-Item -Path $stepKey -Force -ErrorAction Stop
        }

        Set-ItemProperty -Path $stepKey -Name 'Status' -Value $Status -Type String -Force
        Set-ItemProperty -Path $stepKey -Name 'Timestamp' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Type String -Force

        if ($ExitCode) {
            Set-ItemProperty -Path $stepKey -Name 'ExitCode' -Value $ExitCode -Type DWord -Force
        } else {
            # Clear ExitCode if not provided (e.g., on success without exit code)
            if ((Get-ItemProperty -Path $stepKey -ErrorAction SilentlyContinue).PSObject.Properties['ExitCode']) {
                Remove-ItemProperty -Path $stepKey -Name 'ExitCode' -ErrorAction SilentlyContinue
            }
        }

        if ($ErrorMessage) {
            Set-ItemProperty -Path $stepKey -Name 'ErrorMessage' -Value $ErrorMessage -Type String -Force
        } else {
            # Clear ErrorMessage if not provided (e.g., on success)
            if ((Get-ItemProperty -Path $stepKey -ErrorAction SilentlyContinue).PSObject.Properties['ErrorMessage']) {
                Remove-ItemProperty -Path $stepKey -Name 'ErrorMessage' -ErrorAction SilentlyContinue
            }
        }

        if ($Version) {
            Set-ItemProperty -Path $stepKey -Name 'Version' -Value $Version -Type String -Force
        }

        Write-Log "Recorded deployment step status: $StepName = $Status" -Level Verbose

    } catch {
        Write-Log "Failed to record deployment step status for '$StepName': $_" -Level Warning
    }
}

function Get-DeploymentStatus {
    <#
    .SYNOPSIS
        Retrieves deployment step status from registry.

    .DESCRIPTION
        Reads deployment step information from registry including status,
        timestamp, and error details.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$StepName
    )

    $stepKey = "HKLM:\SOFTWARE\DenkoICT\Deployment\Steps\$StepName"

    try {
        if (-not (Test-Path $stepKey)) {
            return $null
        }

        $status = Get-ItemProperty -Path $stepKey -ErrorAction Stop

        return [PSCustomObject]@{
            StepName = $StepName
            Status = $status.Status
            Timestamp = $status.Timestamp
            ExitCode = if ($status.PSObject.Properties['ExitCode']) { $status.ExitCode } else { $null }
            ErrorMessage = if ($status.PSObject.Properties['ErrorMessage']) { $status.ErrorMessage } else { $null }
            Version = if ($status.PSObject.Properties['Version']) { $status.Version } else { $null }
        }
    } catch {
        Write-Log "Failed to retrieve deployment step status for '$StepName': $_" -Level Debug
        return $null
    }
}

# ============================================================================
# CLEANUP INFORMATION
# ============================================================================

function Show-CleanupInformation {
    <#
    .SYNOPSIS
        Displays information about where deployment files, logs, and registry keys are located.

    .DESCRIPTION
        Shows paths to all deployment artifacts so users can manually clean them up if desired.
        Displays both file system paths and registry paths.
    #>
    [CmdletBinding()]
    param()

    $border = "=" * 80

    Write-Log "" -Level Info
    Write-Log $border -Level Info
    Write-Log "  DEPLOYMENT CLEANUP INFORMATION" -Level Info
    Write-Log $border -Level Info
    Write-Log "" -Level Info

    Write-Log "  FILE SYSTEM LOCATIONS:" -Level Info
    Write-Log "  ---------------------" -Level Info
    Write-Log "" -Level Info
    Write-Log "  Logs Directory:" -Level Info
    Write-Log "    C:\DenkoICT\Logs" -Level Verbose
    Write-Log "    (Open in Explorer: explorer.exe C:\DenkoICT\Logs)" -Level Verbose
    Write-Log "" -Level Info

    Write-Log "  Downloads Directory:" -Level Info
    Write-Log "    C:\DenkoICT\Download" -Level Verbose
    Write-Log "    (Open in Explorer: explorer.exe C:\DenkoICT\Download)" -Level Verbose
    Write-Log "" -Level Info

    Write-Log "  REGISTRY LOCATIONS:" -Level Info
    Write-Log "  ------------------" -Level Info
    Write-Log "" -Level Info
    Write-Log "  Deployment Status:" -Level Info
    Write-Log "    HKLM:\SOFTWARE\DenkoICT\Deployment\Steps" -Level Verbose
    Write-Log "    (Open in RegEdit: navigate to HKEY_LOCAL_MACHINE\SOFTWARE\DenkoICT\Deployment\Steps)" -Level Verbose
    Write-Log "" -Level Info

    Write-Log "  Intune Tracking:" -Level Info
    Write-Log "    HKLM:\SOFTWARE\DenkoICT\Intune" -Level Verbose
    Write-Log "    (Open in RegEdit: navigate to HKEY_LOCAL_MACHINE\SOFTWARE\DenkoICT\Intune)" -Level Verbose
    Write-Log "" -Level Info

    Write-Log "  TO CLEAN UP MANUALLY:" -Level Warning
    Write-Log "  --------------------" -Level Warning
    Write-Log "" -Level Info
    Write-Log "  1. Delete directories:" -Level Info
    Write-Log "     Remove-Item -Path 'C:\DenkoICT' -Recurse -Force" -Level Verbose
    Write-Log "" -Level Info
    Write-Log "  2. Delete registry keys:" -Level Info
    Write-Log "     Remove-Item -Path 'HKLM:\SOFTWARE\DenkoICT' -Recurse -Force" -Level Verbose
    Write-Log "" -Level Info

    Write-Log $border -Level Info
    Write-Log "" -Level Info
}
