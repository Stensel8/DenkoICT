#requires -Version 5.1

<#
.SYNOPSIS
    Common script initialization and cleanup functions for deployment scripts.

.DESCRIPTION
    Consolidates repetitive initialization patterns:
    - Utilities path resolution
    - Module loading
    - Transcript initialization
    - Script completion/cleanup
#>

function Find-UtilitiesPath {
    <#
    .SYNOPSIS
        Locates the Utilities folder from standard locations.

    .DESCRIPTION
        Searches for the Utilities folder in the following order:
        1. PSScriptRoot/Utilities (same directory as calling script)
        2. C:\DenkoICT\Download\Utilities (download location)
        3. C:\DenkoICT\Utilities (standard install location)

    .OUTPUTS
        String path to Utilities folder, or $null if not found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$CallerScriptRoot = $PSScriptRoot
    )

    $possiblePaths = @(
        (Join-Path $CallerScriptRoot 'Utilities'),
        'C:\DenkoICT\Download\Utilities',
        'C:\DenkoICT\Utilities'
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-Verbose "Found Utilities folder at: $path"
            return $path
        }
    }

    return $null
}

function Initialize-DeploymentScript {
    <#
    .SYNOPSIS
        Performs standard deployment script initialization.

    .DESCRIPTION
        Consolidates common initialization tasks:
        - Locates and validates Utilities path
        - Imports required modules (Logging first, then others)
        - Starts emergency transcript
        - Initializes script (admin check, etc.)

    .PARAMETER RequiredModules
        Array of module names (without .psm1) to import.
        Logging.psm1 is always imported first if in this list.

    .PARAMETER LogName
        Name of the log file (e.g., 'Install-Applications.log').

    .PARAMETER RequireAdmin
        If specified, requires administrator privileges.

    .PARAMETER CallerScriptRoot
        The $PSScriptRoot of the calling script (auto-detected if not specified).

    .OUTPUTS
        Hashtable with UtilitiesPath and imported module information.

    .EXAMPLE
        $init = Initialize-DeploymentScript -LogName 'MyScript.log' -RequiredModules @('Logging','System','Winget') -RequireAdmin
    #>
    [CmdletBinding()]
    param(
        [string[]]$RequiredModules = @('Logging', 'System'),
        [string]$LogName = 'Script.log',
        [switch]$RequireAdmin,
        [string]$CallerScriptRoot
    )

    # Get caller's script root if not provided
    if (-not $CallerScriptRoot) {
        $CallerScriptRoot = (Get-PSCallStack)[1].ScriptName | Split-Path -Parent
    }

    # Find Utilities folder
    $utilitiesPath = Find-UtilitiesPath -CallerScriptRoot $CallerScriptRoot
    if (-not $utilitiesPath) {
        Write-Error "Utilities folder not found in any expected location"
        exit 1
    }

    # Ensure Logging is imported first (if requested)
    $modulesToLoad = @()
    if ($RequiredModules -contains 'Logging') {
        $modulesToLoad += 'Logging'
        $RequiredModules = $RequiredModules | Where-Object { $_ -ne 'Logging' }
    }
    $modulesToLoad += $RequiredModules

    # Import modules
    $importedModules = @()
    foreach ($moduleName in $modulesToLoad) {
        $modulePath = Join-Path $utilitiesPath "$moduleName.psm1"
        if (-not (Test-Path $modulePath)) {
            Write-Error "Required module '$moduleName.psm1' not found in '$utilitiesPath'"
            exit 1
        }

        try {
            Import-Module $modulePath -Force -Global -ErrorAction Stop
            $importedModules += $moduleName
            Write-Verbose "Imported module: $moduleName"
        } catch {
            Write-Error "Failed to import module '$moduleName': $_"
            exit 1
        }
    }

    # Start emergency transcript (if Logging module was loaded)
    if ($importedModules -contains 'Logging') {
        if (Get-Command Start-EmergencyTranscript -ErrorAction SilentlyContinue) {
            Start-EmergencyTranscript -LogName $LogName
        }

        # Initialize script (if System module was loaded)
        if (Get-Command Initialize-Script -ErrorAction SilentlyContinue) {
            if ($RequireAdmin) {
                Initialize-Script -RequireAdmin
            } else {
                Initialize-Script
            }
        }
    }

    return @{
        UtilitiesPath = $utilitiesPath
        ImportedModules = $importedModules
    }
}

function Complete-DeploymentScript {
    <#
    .SYNOPSIS
        Performs standard deployment script cleanup and transcript finalization.

    .DESCRIPTION
        Consolidates the common finally block pattern used across all scripts.
        Tries Complete-Script first (preferred), falls back to Stop-EmergencyTranscript.

    .EXAMPLE
        try {
            # Script logic
        } finally {
            Complete-DeploymentScript
        }
    #>
    [CmdletBinding()]
    param()

    if (Get-Command Complete-Script -ErrorAction SilentlyContinue) {
        try {
            Complete-Script
        } catch {
            # Fallback to emergency transcript stop
            if (Get-Command Stop-EmergencyTranscript -ErrorAction SilentlyContinue) {
                Stop-EmergencyTranscript
            }
        }
    } elseif (Get-Command Stop-EmergencyTranscript -ErrorAction SilentlyContinue) {
        Stop-EmergencyTranscript
    }
}

Export-ModuleMember -Function @(
    'Find-UtilitiesPath',
    'Initialize-DeploymentScript',
    'Complete-DeploymentScript'
)
