<#PSScriptInfo

.VERSION 3.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Utilities Logging Functions Framework Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial release with basic logging and admin checks
[Version 2.0.0] - Added registry functions and Intune integration
[Version 2.1.0] - Added WinGet detection and module installation
[Version 3.0.0] - Major update: Added network stability functions, WinGet/MSI exit code descriptions, graceful error handling, completion banners
#>

#requires -Version 5.1

<#
.SYNOPSIS
    Core utility functions for DenkoICT PowerShell deployment scripts.

.DESCRIPTION
    Comprehensive function library providing common functionality across all
    DenkoICT deployment scripts. Includes logging, error handling, network
    validation, exit code interpretation, and system utilities.

    Key Features:
    - Advanced logging with color-coded output and transcript support
    - Network connectivity testing and stability validation
    - WinGet and MSI exit code interpretation
    - Graceful error handling with retry logic
    - Admin rights validation
    - Registry manipulation helpers
    - Intune deployment tracking
    - Module installation helpers

.NOTES
    Version      : 3.0.0
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
        
        # Write to appropriate PowerShell stream for pipeline compatibility
        switch ($Level) {
            'Error' { 
                Write-Error $Message -ErrorAction Continue 
            }
            'Warning' { 
                Write-Warning $Message 
            }
            'Verbose' { 
                Write-Verbose $Message 
            }
            'Debug' { 
                Write-Debug $Message 
            }
            'Success' { 
                Write-Information $Message -InformationAction Continue
            }
            'Info' { 
                Write-Information $Message -InformationAction Continue
            }
        }
    }
}

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

function Initialize-LogDirectory {
    <#
    .SYNOPSIS
        Creates log directory if it doesn't exist.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = $Global:DenkoConfig.LogPath
    )
    
    try {
        if (-not (Test-Path $Path)) {
            $null = New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
            Write-Log "Created log directory: $Path" -Level Info
        }
    } catch {
        Write-Warning "Failed to create log directory '$Path': $_"
        throw
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
                $backupName = $LogName -replace '\.log$', "-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
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
            # Transcript already stopped or never started
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

function Test-InternetConnection {
    <#
    .SYNOPSIS
        Tests if internet connection is available.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$TestUrl = 'http://www.msftncsi.com/ncsi.txt',
        [string]$ExpectedContent = 'Microsoft NCSI',
        [int]$TimeoutSec = 5
    )
    
    try {
        $response = Invoke-WebRequest -Uri $TestUrl -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        return $response.Content -eq $ExpectedContent
    } catch {
        Write-Log "Internet connectivity test failed: $_" -Level Debug
        return $false
    }
}

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
        Executes a script block with retry logic.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 2
    )
    
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            $result = & $ScriptBlock
            Write-Log "Operation succeeded on attempt $i" -Level Verbose
            return $result
        } catch {
            if ($i -eq $MaxAttempts) {
                Write-Log "All $MaxAttempts attempts failed" -Level Error
                throw
            }
            Write-Log "Attempt $i/$MaxAttempts failed: $($_.Exception.Message)" -Level Warning
            Write-Log "Retrying in $DelaySeconds seconds..." -Level Info
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Get-WinGetPath {
    <#
    .SYNOPSIS
        Finds the WinGet executable path.
    
    .DESCRIPTION
        Locates winget.exe by checking common installation paths.
        Useful for SYSTEM context or troubleshooting.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    # Try to find winget in PATH first
    $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        return $wingetCmd.Source
    }
    
    # Search WindowsApps folder
    $wingetPaths = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    )
    
    foreach ($path in $wingetPaths) {
        $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
        if ($resolved) {
            # If multiple, get the latest version
            if ($resolved -is [array]) {
                $resolved = $resolved | Sort-Object { 
                    [version]($_.Path -replace '^.*_(\d+\.\d+\.\d+\.\d+)_.*', '$1') 
                } -Descending | Select-Object -First 1
            }
            return $resolved.Path
        }
    }
    
    return $null
}

function Test-WinGetAvailable {
    <#
    .SYNOPSIS
        Checks if WinGet is installed and functional.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $wingetPath = Get-WinGetPath
        if (-not $wingetPath) {
            Write-Log "WinGet executable not found" -Level Debug
            return $false
        }

        $version = & $wingetPath --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "WinGet is available: $version" -Level Verbose
            return $true
        }

        Write-Log "WinGet found but not functional (exit code: $LASTEXITCODE)" -Level Debug
        return $false
    } catch {
        Write-Log "WinGet availability check failed: $_" -Level Debug
        return $false
    }
}

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
        Waits for stable network connectivity with retry logic.

    .DESCRIPTION
        Performs multiple network checks with delays between attempts.
        Optionally performs continuous stability checks to ensure connection is reliable.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [int]$MaxRetries = 5,
        [int]$DelaySeconds = 10,
        [switch]$ContinuousCheck
    )

    Write-Log "Checking network connectivity..." -Level Info

    for ($i = 1; $i -le $MaxRetries; $i++) {
        if (Test-NetworkConnectivity) {
            Write-Log "Network connectivity confirmed (attempt $i/$MaxRetries)" -Level Success

            if ($ContinuousCheck) {
                Write-Log "Performing stability check..." -Level Verbose
                $stable = $true
                for ($j = 1; $j -le 3; $j++) {
                    Start-Sleep -Seconds 2
                    if (-not (Test-NetworkConnectivity)) {
                        $stable = $false
                        break
                    }
                }
                if ($stable) {
                    Write-Log "Network connection is stable" -Level Success
                    return $true
                }
                Write-Log "Network unstable, retrying..." -Level Warning
            } else {
                return $true
            }
        }

        if ($i -lt $MaxRetries) {
            Write-Log "Network not available (attempt $i/$MaxRetries). Waiting $DelaySeconds seconds..." -Level Warning
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    Write-Log "Network connectivity check failed after $MaxRetries attempts" -Level Error
    return $false
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

function Invoke-SafeScriptBlock {
    <#
    .SYNOPSIS
        Executes a script block with graceful error handling.

    .DESCRIPTION
        Wraps script block execution with try-catch to enable graceful degradation.
        Logs errors but doesn't throw, allowing deployment to continue on non-critical failures.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory)]
        [string]$OperationName,

        [switch]$Critical,

        [hashtable]$Parameters
    )

    Write-Log "Starting: $OperationName" -Level Info

    try {
        if ($Parameters) {
            $result = & $ScriptBlock @Parameters
        } else {
            $result = & $ScriptBlock
        }

        Write-Log "Completed: $OperationName" -Level Success
        return [PSCustomObject]@{
            Success = $true
            Result = $result
            Error = $null
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Log "Failed: $OperationName - $errorMsg" -Level Error

        if ($_.ScriptStackTrace) {
            Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Debug
        }

        if ($Critical) {
            throw "Critical operation failed: $OperationName - $errorMsg"
        }

        Write-Log "Continuing despite error (non-critical operation)" -Level Warning
        return [PSCustomObject]@{
            Success = $false
            Result = $null
            Error = $errorMsg
        }
    }
}

function Set-DeploymentStepStatus {
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

        # Store status information
        Set-ItemProperty -Path $stepKey -Name 'Status' -Value $Status -Type String -Force
        Set-ItemProperty -Path $stepKey -Name 'Timestamp' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Type String -Force

        if ($ExitCode) {
            Set-ItemProperty -Path $stepKey -Name 'ExitCode' -Value $ExitCode -Type DWord -Force
        }

        if ($ErrorMessage) {
            Set-ItemProperty -Path $stepKey -Name 'ErrorMessage' -Value $ErrorMessage -Type String -Force
        }

        if ($Version) {
            Set-ItemProperty -Path $stepKey -Name 'Version' -Value $Version -Type String -Force
        }

        Write-Log "Recorded deployment step status: $StepName = $Status" -Level Verbose

    } catch {
        Write-Log "Failed to record deployment step status for '$StepName': $_" -Level Warning
    }
}

function Get-DeploymentStepStatus {
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

function Get-AllDeploymentSteps {
    <#
    .SYNOPSIS
        Retrieves all deployment step statuses from registry.

    .DESCRIPTION
        Returns an array of all recorded deployment steps with their status information.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $deploymentKey = 'HKLM:\SOFTWARE\DenkoICT\Deployment\Steps'

    try {
        if (-not (Test-Path $deploymentKey)) {
            return @()
        }

        $steps = Get-ChildItem -Path $deploymentKey -ErrorAction Stop
        $results = @()

        foreach ($step in $steps) {
            $stepName = $step.PSChildName
            $stepStatus = Get-DeploymentStepStatus -StepName $stepName
            if ($stepStatus) {
                $results += $stepStatus
            }
        }

        return $results
    } catch {
        Write-Log "Failed to retrieve deployment steps: $_" -Level Warning
        return @()
    }
}

function Clear-DeploymentHistory {
    <#
    .SYNOPSIS
        Clears all deployment step history from registry.

    .DESCRIPTION
        Removes all deployment step tracking data. Useful for starting fresh deployments.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $deploymentKey = 'HKLM:\SOFTWARE\DenkoICT\Deployment\Steps'

    try {
        if (Test-Path $deploymentKey) {
            if ($PSCmdlet.ShouldProcess($deploymentKey, "Remove deployment history")) {
                Remove-Item -Path $deploymentKey -Recurse -Force -ErrorAction Stop
                Write-Log "Cleared deployment history" -Level Info
            }
        }
    } catch {
        Write-Log "Failed to clear deployment history: $_" -Level Warning
    }
}

function Show-DeploymentSummary {
    <#
    .SYNOPSIS
        Displays comprehensive deployment summary from registry.

    .DESCRIPTION
        Reads all deployment steps from registry and displays a detailed
        summary with status, timestamps, and error information.
    #>
    [CmdletBinding()]
    param(
        [string]$Title = "DENKO ICT DEPLOYMENT SUMMARY"
    )

    $border = "=" * 80
    $steps = Get-AllDeploymentSteps

    Write-Log "" -Level Info
    Write-Log $border -Level Info
    Write-Log "  $Title" -Level Info
    Write-Log $border -Level Info
    Write-Log "" -Level Info

    if ($steps.Count -eq 0) {
        Write-Log "  No deployment steps recorded." -Level Warning
        Write-Log "" -Level Info
        Write-Log $border -Level Info
        return
    }

    # Calculate statistics
    $successCount = ($steps | Where-Object { $_.Status -eq 'Success' }).Count
    $failedCount = ($steps | Where-Object { $_.Status -eq 'Failed' }).Count
    $skippedCount = ($steps | Where-Object { $_.Status -eq 'Skipped' }).Count
    $totalSteps = $steps.Count

    # Display statistics
    Write-Log "  Total Steps: $totalSteps" -Level Info
    Write-Log "  ✓ Successful: $successCount" -Level Success
    if ($failedCount -gt 0) {
        Write-Log "  ✗ Failed: $failedCount" -Level Error
    }
    if ($skippedCount -gt 0) {
        Write-Log "  ⊘ Skipped: $skippedCount" -Level Warning
    }
    Write-Log "" -Level Info

    # Display detailed step information
    Write-Log "  DETAILED STEP RESULTS:" -Level Info
    Write-Log "  " + ("-" * 76) -Level Info

    foreach ($step in $steps) {
        $statusSymbol = switch ($step.Status) {
            'Success' { '✓' }
            'Failed'  { '✗' }
            'Skipped' { '⊘' }
            'Running' { '▶' }
            default   { '?' }
        }

        $statusLevel = switch ($step.Status) {
            'Success' { 'Success' }
            'Failed'  { 'Error' }
            'Skipped' { 'Warning' }
            'Running' { 'Info' }
            default   { 'Info' }
        }

        $stepLine = "  $statusSymbol $($step.StepName)"
        Write-Log $stepLine -Level $statusLevel

        if ($step.Timestamp) {
            Write-Log "      Time: $($step.Timestamp)" -Level Verbose
        }

        if ($step.Version) {
            Write-Log "      Version: $($step.Version)" -Level Verbose
        }

        if ($null -ne $step.ExitCode -and $step.ExitCode -ne 0) {
            Write-Log "      Exit Code: $($step.ExitCode)" -Level Warning
        }

        if ($step.ErrorMessage) {
            Write-Log "      Error: $($step.ErrorMessage)" -Level Error
        }
    }

    Write-Log "" -Level Info
    Write-Log "  " + ("-" * 76) -Level Info
    Write-Log "" -Level Info

    # Overall status message
    if ($failedCount -eq 0 -and $skippedCount -eq 0) {
        Write-Log "  🎉 ALL DEPLOYMENT STEPS COMPLETED SUCCESSFULLY!" -Level Success
        Write-Log "  Your device is fully configured and ready to use." -Level Info
    } elseif ($failedCount -eq 0) {
        Write-Log "  ✓ Deployment completed successfully with some steps skipped." -Level Success
        Write-Log "  Your device is ready to use." -Level Info
        if ($skippedCount -gt 0) {
            Write-Log "  Some optional features may be unavailable (check skipped items above)." -Level Warning
        }
    } else {
        Write-Log "  ⚠ Deployment completed with $failedCount failure(s)." -Level Warning
        Write-Log "  Your device may not be fully configured." -Level Warning
        Write-Log "  Please review the failed steps above and check the log file." -Level Warning
    }

    Write-Log "" -Level Info

    # Registry location
    Write-Log "  Deployment status stored in: HKLM:\SOFTWARE\DenkoICT\Deployment\Steps" -Level Verbose
    Write-Log "" -Level Info
    Write-Log $border -Level Info
}

function Show-CompletionBanner {
    <#
    .SYNOPSIS
        Displays a friendly completion banner with deployment results.

    .DESCRIPTION
        Shows a formatted completion message with success/failure statistics
        and next steps for the user. This is a simplified version.
        Use Show-DeploymentSummary for detailed registry-based reporting.
    #>
    [CmdletBinding()]
    param(
        [int]$SuccessCount = 0,
        [int]$FailedCount = 0,
        [int]$SkippedCount = 0,
        [string]$Title = "Deployment Complete"
    )

    $border = "=" * 70
    $totalSteps = $SuccessCount + $FailedCount + $SkippedCount

    Write-Log "" -Level Info
    Write-Log $border -Level Info
    Write-Log "  $Title" -Level Info
    Write-Log $border -Level Info
    Write-Log "" -Level Info
    Write-Log "  Total Steps: $totalSteps" -Level Info
    Write-Log "  ✓ Successful: $SuccessCount" -Level Success

    if ($FailedCount -gt 0) {
        Write-Log "  ✗ Failed: $FailedCount" -Level Error
    }

    if ($SkippedCount -gt 0) {
        Write-Log "  ⊘ Skipped: $SkippedCount" -Level Warning
    }

    Write-Log "" -Level Info

    if ($FailedCount -eq 0 -and $SkippedCount -eq 0) {
        Write-Log "  🎉 All deployment steps completed successfully!" -Level Success
        Write-Log "  Your device is ready to use." -Level Info
    } elseif ($FailedCount -eq 0) {
        Write-Log "  ✓ Deployment completed with some steps skipped." -Level Success
        Write-Log "  Your device is ready, but some optional features may be unavailable." -Level Warning
    } else {
        Write-Log "  ⚠ Deployment completed with some failures." -Level Warning
        Write-Log "  Please review the log file for details." -Level Warning
    }

    Write-Log "" -Level Info
    Write-Log $border -Level Info
}