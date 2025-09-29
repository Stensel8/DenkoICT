<#
.SYNOPSIS
    Gets all installed software including Store apps and Win32 programs.

.DESCRIPTION
    Queries registry for traditional Win32 apps and Windows Store for UWP/MSIX apps.
    Combines results into unified list with consistent properties.

.PARAMETER ExportPath
    Export results to CSV file.

.PARAMETER IncludeUpdates
    Include Windows Updates in results.

.PARAMETER StoreAppsOnly
    Show only Store/UWP apps.

.PARAMETER Win32Only
    Show only traditional Win32 apps.

.PARAMETER SkipLogging
    Skip transcript logging.

.EXAMPLE
    .\ps_Get-InstalledSoftware.ps1
    Shows all installed software.

.EXAMPLE
    .\ps_Get-InstalledSoftware.ps1 -StoreAppsOnly
    Shows only Store apps.

.EXAMPLE
    .\ps_Get-InstalledSoftware.ps1 -ExportPath "C:\software.csv"
    Exports all software to CSV.

.NOTES
    Version:  1.1.0
    Author:   Sten Tijhuis
    Company:  Denko ICT
#>

[CmdletBinding()]
param(
    [string]$ExportPath,
    [switch]$IncludeUpdates,
    [switch]$StoreAppsOnly,
    [switch]$Win32Only,
    [switch]$SkipLogging
)

#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# Load custom functions
$functionsPath = Join-Path $PSScriptRoot 'ps_Custom-Functions.ps1'
if (Test-Path $functionsPath) {
    . $functionsPath
    $useCustomFunctions = $true
} else {
    $useCustomFunctions = $false
    function Write-Log {
        param($Message, $Level = 'Info')
        Write-Host "[$Level] $Message"
    }
}

if ($useCustomFunctions -and -not $SkipLogging) {
    Start-Logging -LogName 'Get-InstalledSoftware.log'
}

try {
    $allSoftware = @()
    
    # Get Win32 apps from registry
    if (-not $StoreAppsOnly) {
        Write-Log "Scanning registry for Win32 applications..." -Level Info
        
        $registryPaths = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        $win32Apps = foreach ($path in $registryPaths) {
            Get-ItemProperty $path -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.DisplayName -and 
                ($IncludeUpdates -or ($_.DisplayName -notlike "*Update*" -and $_.DisplayName -notlike "KB*"))
            } |
            ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.DisplayName
                    Version = $_.DisplayVersion
                    Publisher = $_.Publisher
                    InstallDate = if ($_.InstallDate) {
                        try {
                            [datetime]::ParseExact($_.InstallDate, "yyyyMMdd", $null).ToString("yyyy-MM-dd")
                        } catch {
                            $_.InstallDate
                        }
                    } else { $null }
                    Type = "Win32"
                    Location = $_.InstallLocation
                }
            }
        }
        
        $allSoftware += $win32Apps
        Write-Log "Found $($win32Apps.Count) Win32 applications" -Level Info
    }
    
    # Get Store/UWP apps
    if (-not $Win32Only) {
        Write-Log "Scanning for Store/UWP applications..." -Level Info
        
        $storeApps = Get-AppxPackage -AllUsers | 
        Where-Object { 
            $_.Name -and 
            ($IncludeUpdates -or $_.Name -notlike "*Update*")
        } |
        ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Version = $_.Version
                Publisher = $_.Publisher
                InstallDate = if ($_.InstallDate) {
                    $_.InstallDate.ToString("yyyy-MM-dd")
                } else { $null }
                Type = "Store"
                Location = $_.InstallLocation
            }
        }
        
        $allSoftware += $storeApps
        Write-Log "Found $($storeApps.Count) Store applications" -Level Info
    }
    
    # Remove duplicates
    $allSoftware = $allSoftware | Sort-Object Name, Version -Unique
    
    Write-Log "Total unique applications: $($allSoftware.Count)" -Level Success
    
    # Export or display
    if ($ExportPath) {
        $allSoftware | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
        Write-Log "Exported to: $ExportPath" -Level Success
    } else {
        # Display summary
        $summary = $allSoftware | Group-Object Type | Select-Object Name, Count
        Write-Host "`nSummary:" -ForegroundColor Cyan
        $summary | Format-Table -AutoSize
        
        # Display apps
        Write-Host "`nInstalled Software:" -ForegroundColor Cyan
        $allSoftware | Sort-Object Type, Name | Format-Table Name, Version, Publisher, Type -AutoSize
    }
    
    # Return for pipeline
    return $allSoftware
    
} catch {
    Write-Log "Error: $_" -Level Error
} finally {
    if ($useCustomFunctions -and -not $SkipLogging) {
        Stop-Logging
    }
}