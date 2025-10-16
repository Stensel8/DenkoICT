<#PSScriptInfo

.VERSION 3.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Serial ComputerName Hostname Naming Convention

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Gets serial number and formats as PC name.
[Version 1.0.1] - Improved error handling and logging using try/catch.
[Version 1.0.2] - Changed naming conventions of script.
[Version 1.1.0] - Added -SerialOnly parameter to return actual serial number. Improved documentation.
[Version 2.0.0] - Renamed to Generate-Hostname.ps1. Simplified to only return hostname. Changed to last 5 digits.
[Version 3.0.0] - Refactored to use modular utilities, removed parameters for simplicity.
#>

#requires -Version 5.1

<#
.SYNOPSIS
    Generates a new hostname based on the computer's serial number.

.DESCRIPTION
    Retrieves the system's BIOS serial number and formats it using the last 5 characters
    prefixed with 'PC-' to create a standardized hostname following Denko ICT naming convention.

.EXAMPLE
    .\Generate-Hostname.ps1

.EXAMPLE
    $newHostname = & .\Generate-Hostname.ps1
    Rename-Computer -NewName $newHostname -Force

.OUTPUTS
    String. Returns the formatted hostname (e.g., "PC-12345").

.NOTES
    Version      : 3.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import required modules
$possiblePaths = @(
    (Join-Path $PSScriptRoot 'Utilities'),
    'C:\DenkoICT\Download\Utilities',
    'C:\DenkoICT\Utilities'
)
$utilitiesPath = $null
foreach ($p in $possiblePaths) { if (Test-Path $p) { $utilitiesPath = $p; break } }
if (-not $utilitiesPath) { Write-Error "Could not find Utilities folder"; exit 1 }

Import-Module (Join-Path $utilitiesPath 'Logging.psm1') -Force -Global

Start-EmergencyTranscript -LogName 'Generate-Hostname.log'
Initialize-Script

try {
    $serial = (Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber

    if ([string]::IsNullOrWhiteSpace($serial)) {
        Write-Log "Serial number not found, returning PC-UNKNOWN" -Level Warning
        return 'PC-UNKNOWN'
    }

    $serial = $serial.Trim()

    if ($serial.Length -lt 5) {
        $hostname = "PC-$serial"
    } else {
        $hostname = 'PC-{0}' -f $serial.Substring($serial.Length - 5)
    }

    Write-Log "Generated hostname: $hostname" -Level Success
    return $hostname

} catch {
    Write-Log "Failed to generate hostname: $_" -Level Error
    return 'PC-ERROR'
} finally {
    Complete-Script
}
