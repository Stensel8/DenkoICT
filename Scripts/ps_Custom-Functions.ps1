<#
.SYNOPSIS
    Core utility functions for DenkoICT PowerShell scripts.

.DESCRIPTION
    Provides common logging, admin validation, and registry functions
    used across DenkoICT deployment scripts.

.NOTES
    Version:  2.0.0
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
        Writes timestamped log messages with color support.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info','Success','Warning','Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $color = @{
        'Success' = 'Green'
        'Warning' = 'Yellow'  
        'Error'   = 'Red'
        'Info'    = 'White'
    }[$Level]
    
    Write-Host $logEntry -ForegroundColor $color
    
    if ($Level -eq 'Error') {
        Write-Error $Message -ErrorAction Continue
    }
}

function Test-AdminRights {
    <#
    .SYNOPSIS
        Checks if script is running with admin privileges.
    #>
    [CmdletBinding()]
    param()
    
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        Write-Log "Created log directory: $Path" -Level Info
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
    
    Initialize-LogDirectory -Path $LogPath
    
    $logFile = Join-Path -Path $LogPath -ChildPath $LogName
    
    # Check log size and rotate if needed (>10MB)
    if (Test-Path $logFile) {
        $size = (Get-Item $logFile).Length / 1MB
        if ($size -gt 10) {
            $backupName = $LogName -replace '\.log$', "-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
            Move-Item -Path $logFile -Destination (Join-Path $LogPath $backupName) -Force
            Write-Log "Rotated log file (was $([math]::Round($size,2))MB)" -Level Info
        }
    }
    
    try {
        Start-Transcript -Path $logFile -Append -ErrorAction Stop | Out-Null
        $Global:DenkoConfig.TranscriptActive = $true
        Write-Log "Started logging to: $logFile" -Level Info
    } catch {
        Write-Log "Failed to start transcript: $_" -Level Warning
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
            # Already stopped or never started
        }
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
    
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
        Write-Log "Created registry path: $Path" -Level Info
    }
    
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
    Write-Log "Set registry value: $Path\$Name = $Value" -Level Success
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
    Set-RegistryValue -Path $intuneKey -Name $AppName -Value $Version
    Write-Log "Recorded Intune success for $AppName ($Version)" -Level Success
}

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Gets basic system information.
    #>
    [CmdletBinding()]
    param()
    
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $os = Get-CimInstance Win32_OperatingSystem
        
        return @{
            ComputerName = $cs.Name
            Domain = $cs.Domain
            Manufacturer = $cs.Manufacturer
            Model = $cs.Model
            OS = $os.Caption
            OSVersion = $os.Version
            LastBoot = $os.LastBootUpTime
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
    param(
        [string]$TestUrl = 'http://www.msftncsi.com/ncsi.txt',
        [string]$ExpectedContent = 'Microsoft NCSI'
    )
    
    try {
        $response = Invoke-WebRequest -Uri $TestUrl -UseBasicParsing -TimeoutSec 5
        return $response.Content -eq $ExpectedContent
    } catch {
        return $false
    }
}

function Install-RequiredModule {
    <#
    .SYNOPSIS
        Installs a PowerShell module if not present.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,
        
        [string]$MinimumVersion
    )
    
    $module = Get-Module -ListAvailable -Name $ModuleName | 
              Sort-Object Version -Descending | 
              Select-Object -First 1
    
    if (-not $module -or ($MinimumVersion -and $module.Version -lt $MinimumVersion)) {
        Write-Log "Installing module $ModuleName..." -Level Info
        
        try {
            Install-Module -Name $ModuleName -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
            Write-Log "Installed $ModuleName successfully" -Level Success
            return $true
        } catch {
            Write-Log "Failed to install $($ModuleName): $_" -Level Error
            return $false
        }
    }

    Write-Log "$($ModuleName) already installed (v$($module.Version))" -Level Info
    return $true
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
            return $result
        } catch {
            if ($i -eq $MaxAttempts) {
                throw
            }
            Write-Log "Attempt $i failed, retrying in $DelaySeconds seconds..." -Level Warning
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}
