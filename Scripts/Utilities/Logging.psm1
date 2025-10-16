#requires -Version 5.1

# Global configuration
if (-not $Global:DenkoConfig) {
    $Global:DenkoConfig = @{
        LogPath = 'C:\DenkoICT\Logs'
        LogName = 'Deployment.log'
        TranscriptActive = $false
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes log messages with dual-mode support: clean console output and detailed transcript logging.

    .DESCRIPTION
        Supports two output modes:
        - Clean console output (no timestamps) for user-facing messages
        - Detailed transcript logging (with timestamps) for background logs

        The -NoTimestamp switch enables clean console output matching the deployment flow.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info','Success','Warning','Error','Verbose','Debug')]
        [string]$Level = 'Info',

        [switch]$NoTimestamp
    )
    process {
        if ([string]::IsNullOrEmpty($Message)) {
            Write-Host ""
            return
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $color = @{
            Success = 'Green'; Warning = 'Yellow'; Error = 'Red'
            Info = 'Cyan'; Verbose = 'Gray'; Debug = 'Magenta'
        }[$Level]

        # Console output (clean or with timestamp based on switch)
        if ($NoTimestamp) {
            Write-Host $Message -ForegroundColor $color
        } else {
            $logEntry = "[$timestamp] [$Level] $Message"
            Write-Host $logEntry -ForegroundColor $color
        }
    }
}

function Initialize-LogDirectory {
    [CmdletBinding()]
    param([string]$Path = $Global:DenkoConfig.LogPath)
    if (-not (Test-Path $Path)) {
        $null = New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
        Write-Log "Created log directory: $Path" -Level Info
    }
}

function Start-Logging {
    [CmdletBinding()]
    param(
        [string]$LogPath = $Global:DenkoConfig.LogPath,
        [string]$LogName = $Global:DenkoConfig.LogName
    )
    Initialize-LogDirectory -Path $LogPath
    $logFile = Join-Path -Path $LogPath -ChildPath $LogName
    if (Test-Path $logFile) {
        $size = (Get-Item $logFile).Length / 1MB
        if ($size -gt 10) {
            $backupPath = Join-Path $LogPath ($LogName -replace '\.log$', ".old.log")
            Move-Item -Path $logFile -Destination $backupPath -Force
            Write-Log "Rotated log file (was $([math]::Round($size,2))MB)" -Level Info
        }
    }
    try {
        # If a transcript is already active, Stop-Transcript first to avoid errors
        if ($Global:DenkoConfig.TranscriptActive) {
            try { Stop-Transcript | Out-Null } catch {}
            $Global:DenkoConfig.TranscriptActive = $false
        }
        Start-Transcript -Path $logFile -Append -ErrorAction Stop | Out-Null
        $Global:DenkoConfig.TranscriptActive = $true
        Write-Log "Started logging to: $logFile" -Level Info
    } catch {
        # If Start-Transcript throws because a transcript is already active (or other benign reasons), mark as active
        $Global:DenkoConfig.TranscriptActive = $true
        Write-Log "Transcript already active; continuing logging to: $logFile" -Level Info
    }
}

function Stop-Logging {
    [CmdletBinding()]
    param()
    if ($Global:DenkoConfig.TranscriptActive) {
        try {
            Stop-Transcript | Out-Null
            $Global:DenkoConfig.TranscriptActive = $false
        } catch {}
    }
}

function Initialize-Script {
    <#
    .SYNOPSIS
        Centralized initialization for DenkoICT scripts with per-script logging.

    .PARAMETER LogName
        Optional. Log file name. If not provided, uses calling script name with .log extension.

    .PARAMETER RequireAdmin
        When provided, enforces elevation check via Test-AdminRights.
    #>
    [CmdletBinding()]
    param(
        [string]$LogName,
        [switch]$RequireAdmin
    )

    if ($RequireAdmin -and -not (Test-AdminRights)) {
        throw "This script requires administrative privileges"
    }

    # Auto-detect log name from calling script if not provided
    if (-not $LogName) {
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 1) {
            $callingScript = $callStack[1].ScriptName
            if ($callingScript) {
                $LogName = [System.IO.Path]::GetFileNameWithoutExtension($callingScript) + '.log'
            } else {
                $LogName = 'Deployment.log'
            }
        } else {
            $LogName = 'Deployment.log'
        }
    }

    $Global:DenkoConfig.LogName = $LogName
    Initialize-LogDirectory
    Start-Logging
}

function Complete-Script {
    [CmdletBinding()]
    param()
    Stop-Logging
}

function Start-EmergencyTranscript {
    <#
    .SYNOPSIS
        Starts a transcript for logging even if modules fail to import.
    .PARAMETER LogName
        Optional log file name. Defaults to script name.
    #>
    param([string]$LogName)
    $logRoot = 'C:\DenkoICT\Logs'
    if (-not (Test-Path $logRoot)) { $null = New-Item -Path $logRoot -ItemType Directory -Force }
    if (-not $LogName) {
        $LogName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath) + '.log'
    }
    $bootstrapLog = Join-Path $logRoot $LogName
    try {
        if (-not (Get-Variable -Name DenkoBootstrapTranscript -Scope Script -ErrorAction SilentlyContinue)) {
            Start-Transcript -Path $bootstrapLog -Append -ErrorAction SilentlyContinue | Out-Null
            $script:DenkoBootstrapTranscript = $true
        }
    } catch {}
}

function Stop-EmergencyTranscript {
    <#
    .SYNOPSIS
        Stops the emergency transcript if started.
    #>
    try {
        if (Get-Variable -Name DenkoBootstrapTranscript -Scope Script -ErrorAction SilentlyContinue) {
            Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
            Remove-Variable -Name DenkoBootstrapTranscript -Scope Script -ErrorAction SilentlyContinue
        }
    } catch {}
}

# ============================================================================
# DEPLOYMENT FLOW OUTPUT HELPERS
# ============================================================================

function Write-SectionBanner {
    <#
    .SYNOPSIS
        Displays a section banner matching the deployment flow format.
    .EXAMPLE
        Write-SectionBanner -Title "EXECUTING DEPLOYMENT STEPS"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    $separator = "=" * 60
    Write-Host ""
    Write-Host $separator -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host $separator -ForegroundColor Cyan
    Write-Host ""
}

function Write-StepStart {
    <#
    .SYNOPSIS
        Displays the start of a deployment step.
    .EXAMPLE
        Write-StepStart -StepName "WinGet Installation"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepName
    )

    Write-Host "[RUNNING] $StepName" -ForegroundColor Cyan
}

function Write-StepComplete {
    <#
    .SYNOPSIS
        Displays the completion of a deployment step.
    .EXAMPLE
        Write-StepComplete -StepName "WinGet Installation"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepName
    )

    Write-Host "$([char]0x221A) Completed: $StepName" -ForegroundColor Green
}

function Write-StepExecuting {
    <#
    .SYNOPSIS
        Displays a sub-step execution message.
    .EXAMPLE
        Write-StepExecuting -Message "Executing with PowerShell 7"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host " -> $Message" -ForegroundColor Cyan
}

function Write-DeploymentSummary {
    <#
    .SYNOPSIS
        Displays the final deployment summary matching the expected format.
    .EXAMPLE
        Write-DeploymentSummary -SuccessCount 6 -FailedCount 0 -SkippedCount 0 -LogPath "C:\DenkoICT\Logs\Deploy-Device.log"
    #>
    [CmdletBinding()]
    param(
        [int]$SuccessCount = 0,
        [int]$FailedCount = 0,
        [int]$SkippedCount = 0,
        [string]$LogPath
    )

    $separator = "=" * 60
    Write-Host ""
    Write-Host $separator -ForegroundColor Cyan
    Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Green
    Write-Host $separator -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Success: $SuccessCount" -ForegroundColor Green
    Write-Host "Failed: $FailedCount" -ForegroundColor $(if ($FailedCount -gt 0) { 'Red' } else { 'Gray' })
    Write-Host "Skipped: $SkippedCount" -ForegroundColor $(if ($SkippedCount -gt 0) { 'Yellow' } else { 'Gray' })

    if ($LogPath) {
        Write-Host ""
        Write-Host "Log: $LogPath" -ForegroundColor Cyan
    }

    Write-Host ""
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

Export-ModuleMember -Function @(
    'Write-Log', 'Initialize-LogDirectory', 'Start-Logging', 'Stop-Logging',
    'Initialize-Script', 'Complete-Script',
    'Start-EmergencyTranscript', 'Stop-EmergencyTranscript',
    'Write-SectionBanner', 'Write-StepStart', 'Write-StepComplete', 'Write-StepExecuting',
    'Write-DeploymentSummary', 'Test-AdminRights'
) -Variable 'DenkoConfig'