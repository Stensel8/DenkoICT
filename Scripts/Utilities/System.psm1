#requires -Version 5.1

function Test-AdminRights {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Assert-AdminRights {
    [CmdletBinding()]
    param()
    if (-not (Test-AdminRights)) {
        throw "This script requires administrative privileges"
    }
}

function Get-SystemInfo {
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
        return @{}
    }
}

function Test-PowerShell7 {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Check if we're already running in PS7+
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        return $true
    }

    # Check if pwsh is in PATH
    $pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshPath) {
        return $true
    }

    # Check common installation paths
    $commonPaths = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return $true
        }
    }

    return $false
}

function Get-PowerShell7Path {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCommand -and $pwshCommand.Source) {
        return $pwshCommand.Source
    }

    $commonPaths = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function Test-OOBEContext {
    <#
    .SYNOPSIS
        Checks if script is running in OOBE context.

    .DESCRIPTION
        Verifies that the current user is either defaultuser0 or SYSTEM,
        which indicates Windows OOBE/Autopilot context.

    .OUTPUTS
        Boolean indicating if running in OOBE context.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return ($env:USERNAME -eq 'defaultuser0' -or $env:USERNAME -eq 'SYSTEM')
}

function Test-UnattendedMode {
    <#
    .SYNOPSIS
        Checks if script is running in unattended mode (OOBE/SYSTEM context).

    .DESCRIPTION
        Alias for Test-OOBEContext. Verifies that the current user is either
        defaultuser0 or SYSTEM, indicating an unattended deployment scenario.

    .OUTPUTS
        Boolean indicating if running in unattended mode.

    .EXAMPLE
        if (Test-UnattendedMode) {
            # Skip interactive prompts
        }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return Test-OOBEContext
}

function New-ElevationArgumentList {
    <#
    .SYNOPSIS
        Builds an argument list for script re-launch with elevation or PS7.

    .DESCRIPTION
        Processes bound parameters and builds a properly formatted argument string
        for relaunching the script with Start-Process.

    .PARAMETER BoundParameters
        The $PSBoundParameters from the calling script.

    .OUTPUTS
        String array suitable for Start-Process -ArgumentList.

    .EXAMPLE
        $argList = New-ElevationArgumentList -BoundParameters $PSBoundParameters
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$BoundParameters
    )

    $argList = @()
    foreach ($param in $BoundParameters.GetEnumerator()) {
        if ($param.Value -is [switch] -and $param.Value) {
            $argList += "-$($param.Key)"
        } elseif ($param.Value -is [array]) {
            $argList += "-$($param.Key) $($param.Value -join ',')"
        } elseif ($param.Value) {
            $argList += "-$($param.Key) '$($param.Value)'"
        }
    }

    return $argList
}

Export-ModuleMember -Function @(
    'Test-AdminRights', 'Assert-AdminRights', 'Get-SystemInfo',
    'Test-PowerShell7', 'Get-PowerShell7Path', 'Test-OOBEContext',
    'Test-UnattendedMode', 'New-ElevationArgumentList'
)