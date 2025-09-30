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
    
.RELEASENOTES
    1.0.0 Initial release
    1.1.0 Added filtering for updates and improved date parsing
    1.2.0 Added option to export to CSV
    1.2.1 Fixed minor bugs regarding sorting/filtering and display

.NOTES
    Version:  1.2.1
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
                $_.PSObject.properties.Name -contains 'DisplayName' -and
                $_.DisplayName -and 
                ($IncludeUpdates -or ($_.DisplayName -notlike "*Update*" -and $_.DisplayName -notlike "KB*"))
            } |
            ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.DisplayName
                    Version = if ($_.PSObject.Properties.Name -contains 'DisplayVersion') { $_.DisplayVersion } else { $null }
                    Publisher = if ($_.PSObject.Properties.Name -contains 'Publisher') { $_.Publisher } else { $null }
                    InstallDate = if ($_.PSObject.Properties.Name -contains 'InstallDate' -and $_.InstallDate) {
                        try {
                            [datetime]::ParseExact($_.InstallDate, "yyyyMMdd", $null).ToString("yyyy-MM-dd")
                        } catch {
                            $_.InstallDate
                        }
                    } else { $null }
                    Type = "Win32"
                    Location = if ($_.PSObject.Properties.Name -contains 'InstallLocation') { $_.InstallLocation } else { $null }
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
                Version = if ($_.PSObject.Properties.Name -contains 'Version') { $_.Version } else { $null }
                Publisher = if ($_.PSObject.Properties.Name -contains 'Publisher') { $_.Publisher } else { $null }
                InstallDate = if ($_.PSObject.Properties.Name -contains 'InstallDate' -and $_.InstallDate) {
                    $_.InstallDate.ToString("yyyy-MM-dd")
                } else { $null }
                Type = "Store"
                Location = if ($_.PSObject.Properties.Name -contains 'InstallLocation') { $_.InstallLocation } else { $null }
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
        # Separate by type - ensure proper filtering
        $storeList = @($allSoftware | Where-Object { $_.Type -eq "Store" } | Sort-Object Name)
        $win32List = @($allSoftware | Where-Object { $_.Type -eq "Win32" } | Sort-Object Name)
        
        # Display summary
        Write-Host "`nSummary:" -ForegroundColor Cyan
        Write-Host "Name  Count" -ForegroundColor White
        Write-Host "----  -----" -ForegroundColor White
        Write-Host "Store   $($storeList.Count)" -ForegroundColor White
        Write-Host "Win32    $($win32List.Count)" -ForegroundColor White
        Write-Host "Total apps: $($allSoftware.Count)`n" -ForegroundColor Green
        
        # Display Store apps
        if ($storeList.Count -gt 0) {
            Write-Host "`n=== STORE APPLICATIONS ===" -ForegroundColor Cyan
            Write-Host ""
            foreach ($app in $storeList) {
                Write-Host "Name        : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.Name)"
                Write-Host "Version     : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.Version)"
                Write-Host "Publisher   : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.Publisher)"
                Write-Host "InstallDate : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.InstallDate)"
                Write-Host "Type        : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.Type)"
                Write-Host "Location    : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.Location)"
                Write-Host ""
            }
        }
        
        # Display Win32 apps
        if ($win32List.Count -gt 0) {
            Write-Host "`n=== WIN32 APPLICATIONS ===" -ForegroundColor Cyan
            Write-Host ""
            foreach ($app in $win32List) {
                Write-Host "Name        : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.Name)"
                Write-Host "Version     : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.Version)"
                Write-Host "Publisher   : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.Publisher)"
                Write-Host "InstallDate : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.InstallDate)"
                Write-Host "Type        : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.Type)"
                Write-Host "Location    : " -ForegroundColor Green -NoNewline
                Write-Host "$($app.Location)"
                Write-Host ""
            }
        }
    }
    
} catch {
    Write-Log "Error: $_" -Level Error
} finally {
    if ($useCustomFunctions -and -not $SkipLogging) {
        Stop-Logging
    }
}