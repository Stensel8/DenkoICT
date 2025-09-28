<#PSScriptInfo

.VERSION 1.0.1

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Serial ComputerName Naming Convention

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Gets serial number and formats as PC name.
[Version 1.0.1] - Improved error handling and logging using try/catch.
#>

<#
.SYNOPSIS
    Gets the computer serial number and formats it as a PC name.

.DESCRIPTION
    Retrieves the system's BIOS serial number and formats it using the last 4 characters
    prefixed with 'PC-' to create a standardized computer name following Denko ICT naming convention.

.EXAMPLE
    .\ps_Get-Serial.ps1
    
    Returns the formatted PC name, e.g., "PC-1234" based on serial number.

.EXAMPLE
    $computerName = & .\ps_Get-Serial.ps1
    Rename-Computer -NewName $computerName -Force
    
    Stores the generated name and uses it to rename the computer.

.OUTPUTS
    String. Returns the formatted computer name (e.g., "PC-1234").

.NOTES
    Version      : 1.0.1
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    
    This script is typically used during device deployment to generate consistent computer names
    based on hardware serial numbers.

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

[CmdletBinding()]
param()

# Get the serial number of the machine via the CIMInstance cmdlet
try {
    $serial = (Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber
    
    if ([string]::IsNullOrWhiteSpace($serial)) {
        Write-Warning "Serial number is empty or null"
        return 'PC-UNKNOWN'
    }
    
    # Check if serial is at least 4 characters
    if ($serial.Length -lt 4) {
        Write-Warning "Serial number is shorter than 4 characters, using full serial"
        return "PC-$serial"
    }
    
    # Format the serial number to give back the last 4 characters prefixed with 'PC-'
    $computerName = 'PC-{0}' -f $serial.Substring($serial.Length - 4)
    
    Write-Verbose "Serial Number: $serial"
    Write-Verbose "Generated Name: $computerName"
    
    return $computerName
    
} catch {
    Write-Error "Failed to retrieve serial number: $_"
    return 'PC-ERROR'
}