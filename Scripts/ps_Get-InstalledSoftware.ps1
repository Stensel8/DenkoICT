<#PSScriptInfo

.VERSION 1.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Software Inventory Registry InstalledPrograms

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Gets installed software from registry with Dutch labels.

#>

<#
.SYNOPSIS
    Retrieves a list of installed software from Windows registry.

.DESCRIPTION
    This script queries multiple registry locations to get a comprehensive list of installed
    software on the system. It checks both 32-bit and 64-bit registry paths as well as
    user-specific installations. Results are displayed with Dutch column headers.

.PARAMETER ExportPath
    Optional path to export results to CSV file.

.PARAMETER IncludeUpdates
    Include Windows Updates and patches in the results.

.EXAMPLE
    .\ps_Get-InstalledSoftware.ps1
    
    Displays all installed software in a formatted table.

.EXAMPLE
    .\ps_Get-InstalledSoftware.ps1 -ExportPath "C:\Reports\Software.csv"
    
    Exports installed software list to CSV file.

.EXAMPLE
    .\ps_Get-InstalledSoftware.ps1 | Where-Object Publisher -like "*Microsoft*"
    
    Shows only Microsoft software.

.OUTPUTS
    PSCustomObject with properties: Naam, Versie, Publisher, InstallatieDatum

.NOTES
    Version      : 1.0.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    
    Registry paths checked:
    - HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*
    - HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* (64-bit systems)
    - HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ExportPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeUpdates
)

# Registry paths to check for installed software
$registryPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

Write-Verbose "Scanning registry for installed software..."

$installedApps = foreach ($path in $registryPaths) {
    Write-Verbose "Checking: $path"
    
    Get-ItemProperty $path -ErrorAction SilentlyContinue | 
    Where-Object { 
        $_.DisplayName -and 
        ($IncludeUpdates -or $_.DisplayName -notlike "*Update*" -and $_.DisplayName -notlike "KB*")
    } |
    Select-Object @{Name="Naam";Expression={$_.DisplayName}},
                  @{Name="Versie";Expression={$_.DisplayVersion}},
                  @{Name="Publisher";Expression={$_.Publisher}},
                  @{Name="InstallatieDatum";Expression={
                      if ($_.InstallDate) {
                          try {
                              [datetime]::ParseExact($_.InstallDate, "yyyyMMdd", $null).ToString("yyyy-MM-dd")
                          } catch {
                              $_.InstallDate
                          }
                      }
                  }}
}

# Remove duplicates based on name
$installedApps = $installedApps | Sort-Object Naam -Unique

Write-Host "Found $($installedApps.Count) installed applications" -ForegroundColor Green

if ($ExportPath) {
    try {
        $installedApps | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
        Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to export to CSV: $_"
    }
} else {
    # Display results
    $installedApps | Sort-Object Naam | Format-Table -AutoSize
}

# Return the objects for pipeline use
return $installedApps