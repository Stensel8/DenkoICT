<#
.SYNOPSIS
    Core utility functions for DenkoICT PowerShell scripts.

.DESCRIPTION
    Provides common logging, admin validation, and registry functions
    used across DenkoICT deployment scripts.

.NOTES
    Version:  2.1.0
    Author:   Sten Tijhuis
    Company:  Denko ICT
#>

#requires -Version 5.1

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