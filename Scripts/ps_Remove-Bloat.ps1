<#PSScriptInfo

.VERSION 1.3.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Bloatware Debloat AppxPackage Cleanup Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Removes bloatware apps from Windows.
[Version 1.1.0] - Added registry modifications to prevent reinstallation of bloatware.
[Version 1.1.1] - Added more known bloatware apps to the removal list.
[Version 1.2.0] - Hardened Start Menu recommendation suppression using additional policy keys.
[Version 1.3.0] - Adopted SupportsShouldProcess, centralized admin elevation, and improved WhatIf consistency.

#>

<#
.SYNOPSIS
    Removes bloatware applications and prevents their automatic reinstallation.

.DESCRIPTION
    This script removes unwanted Windows applications (bloatware) from the system.
    It removes both installed packages (for current users) and provisioned packages 
    (preventing installation for new users). Additionally, it configures registry
    settings to prevent Windows from automatically reinstalling bloatware.

    The script targets:
    - Communication apps (Skype, Teams personal, Your Phone)
    - Games and entertainment (Xbox apps, Candy Crush, Solitaire)
    - Productivity apps (Sticky Notes, Maps, To-Do)
    - News and weather apps
    - Other unnecessary pre-installed apps

.PARAMETER LogPath
    Path for the detailed log file. Default creates log in temp directory.

.EXAMPLE
    .\ps_Remove-Bloat.ps1
    
    Removes all bloatware applications and configures prevention settings.

.EXAMPLE
    .\ps_Remove-Bloat.ps1 -WhatIf
    
    Shows what would be removed without making any changes.

.OUTPUTS
    Console output with removal summary and detailed log file.

.NOTES
    Version      : 1.2.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    
    Supports -WhatIf for safe simulation.
    Requires administrative privileges for full effectiveness.
    Registry changes prevent automatic reinstallation of bloatware.
    
    Registry modifications:
    - DisableWindowsConsumerFeatures: Prevents bloatware auto-installation
    - Start_IrisRecommendations: Disables Start Menu suggestions

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\DenkoICT-Debloat-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
)

# --- Elevate if necessary ---
$currentIdentity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$invokedWithWhatIf = $PSBoundParameters.ContainsKey('WhatIf') -or $WhatIfPreference

if (-not $isAdmin) {
    if ($invokedWithWhatIf) {
    Write-Log "Running in WhatIf mode without elevation. Some operations may be simulated or skipped due to limited permissions." -Level 'Warning'
    } else {
    Write-Log "Elevation required. Restarting script with administrative privileges..." -Level 'Warning'

        try {
            $hostPath     = (Get-Process -Id $PID -ErrorAction Stop).Path
            $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)

            foreach ($param in $PSBoundParameters.GetEnumerator()) {
                switch ($param.Key) {
                    'WhatIf' {
                        if ($param.Value) {
                            $argumentList += '-WhatIf'
                        }
                    }
                    'LogPath' {
                        $argumentList += '-LogPath'
                        $argumentList += $param.Value
                    }
                }
            }

            if ($MyInvocation.UnboundArguments) {
                $argumentList += $MyInvocation.UnboundArguments
            }

            Start-Process -FilePath $hostPath -ArgumentList $argumentList -Verb RunAs | Out-Null
        } catch {
            Write-Log "Failed to restart with elevated privileges: $($_.Exception.Message)" -Level 'Error'
        }

        exit
    }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ShouldExecute = $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Remove Denko ICT bloatware packages and policies')

# List of unwanted apps to remove. Wildcards (*) are supported.
$AppsToRemove = @(
    # Communication and Social
    "Microsoft.SkypeApp",
    "Microsoft.YourPhone",
    "Microsoft.People",

    # Media and Entertainment
    "king.com.CandyCrushSaga",
    "king.com.CandyCrushSodaSaga",
    "Microsoft.GamingApp",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.ZuneMusic",                  # Groove Music (legacy)
    "Microsoft.ZuneVideo",                  # Movies & TV
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.Media.Player",               # New Media Player
    "SpotifyAB.SpotifyMusic",

    # Productivity and Tools
    "Microsoft.Todos",
    "Microsoft.WindowsMaps",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.MicrosoftOfficeHub",         # Office promotion app
    "Microsoft.OneConnect",                 # Mobile Plans
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",                 # Tips app
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.MixedReality.Portal",
    "Microsoft.Clipchamp",
    "9P1J8S7CCWWT",                         # Clipchamp Product ID
    "MicrosoftCorporationII.MicrosoftFamily",
    "Microsoft.WindowsAlarms",
    "Microsoft.ScreenSketch",               # Snip & Sketch
    "Microsoft.Wallet",

    # News and Weather
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.Start",                      # Successor to BingNews
    "Microsoft.BingSearch",
    "Microsoft.WebExperiencePack",          # Widgets and other web content

    # System & Utility (use with caution)
    "Microsoft.PowerAutomateDesktop"
)

# --- Functions ---

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$time] [$Level] $Message"
    
    # Write to file
    Add-Content -Path $LogPath -Value $logMessage -Force
    
    # Write to console via information stream
    Write-Information -MessageData $logMessage -Tags $Level
}

function Remove-AppxByPattern {
    param(
        [string]$Pattern,
        [System.Collections.ArrayList]$Succeeded,
        [System.Collections.ArrayList]$Failed
    )

    Write-Log "Searching installed packages matching: $Pattern"
    $matchedPackages = Get-AppxPackage -AllUsers | Where-Object { 
        $_.Name -like $Pattern -or $_.PackageFullName -like $Pattern 
    }

    if (-not $matchedPackages) {
        Write-Log "No installed packages found for pattern: $Pattern"
        return
    }

    foreach ($pkg in $matchedPackages) {
        $packageName = $pkg.PackageFullName
        Write-Log "Found installed package: $($pkg.Name) | $packageName"
        
        if (-not $script:ShouldExecute) {
            Write-Log "WhatIf: Would remove package $packageName for all users" -Level 'Warning'
            $Succeeded.Add("Would remove: $packageName") | Out-Null
        } else {
            try {
                Remove-AppxPackage -Package $packageName -AllUsers -ErrorAction Stop
                Write-Log "Successfully removed package: $packageName" -Level 'Success'
                $Succeeded.Add("Removed: $packageName") | Out-Null
            } catch {
                Write-Log "Failed to remove package $($packageName): $($_.Exception.Message)" -Level 'Error'
                $Failed.Add("Failed to remove: $packageName") | Out-Null
            }
        }
    }
}

function Remove-ProvisionedByPattern {
    param(
        [string]$Pattern,
        [System.Collections.ArrayList]$Succeeded,
        [System.Collections.ArrayList]$Failed
    )

    Write-Log "Searching provisioned packages matching: $Pattern"
    $provPackages = Get-AppxProvisionedPackage -Online | Where-Object { 
        $_.PackageName -like $Pattern 
    }

    if (-not $provPackages) {
        Write-Log "No provisioned packages found for pattern: $Pattern"
        return
    }

    foreach ($p in $provPackages) {
        $packageName = $p.PackageName
        Write-Log "Found provisioned package: $($p.DisplayName) | $packageName"
        
        if (-not $script:ShouldExecute) {
            Write-Log "WhatIf: Would remove provisioned package $packageName" -Level 'Warning'
            $Succeeded.Add("Would remove provisioned: $packageName") | Out-Null
        } else {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $packageName -ErrorAction Stop
                Write-Log "Successfully removed provisioned package: $packageName" -Level 'Success'
                $Succeeded.Add("Removed provisioned: $packageName") | Out-Null
            } catch {
                Write-Log "Failed to remove provisioned package $($packageName): $($_.Exception.Message)" -Level 'Error'
                $Failed.Add("Failed to remove provisioned: $packageName") | Out-Null
            }
        }
    }
}

# --- Main Execution ---

if (-not $script:ShouldExecute) {
    Write-Log 'WhatIf: Simulation mode - no changes will be applied.' -Level 'Warning'
}

Write-Log "=== Bloatware Removal Started ===" -Level 'Info'
Write-Log "User: $env:USERNAME" -Level 'Info'
Write-Log "Computer: $env:COMPUTERNAME" -Level 'Info'

# Arrays to hold the results
$succeededRemovals = [System.Collections.ArrayList]::new()
$failedRemovals = [System.Collections.ArrayList]::new()

# Iterate over the entries and apply both provisioned and installed removals
foreach ($appName in $AppsToRemove) {
    $pattern = "*$appName*"
    
    Remove-AppxByPattern -Pattern $pattern -Succeeded $succeededRemovals -Failed $failedRemovals
    Remove-ProvisionedByPattern -Pattern $pattern -Succeeded $succeededRemovals -Failed $failedRemovals
}

# --- Disable Consumer Features ---
Write-Log "Configuring registry to prevent bloatware reinstallation..." -Level 'Info'

$registryConfigs = @(
    @{
        Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        Name = "DisableWindowsConsumerFeatures"
        Value = 1
        Description = "Prevents automatic installation of consumer apps"
    },
    @{
        Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Name = "Start_IrisRecommendations"
        Value = 0
        Description = "Disables Start Menu suggestions"
    },
    @{
        Path = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
        Name = "HideRecommendedSection"
        Value = 1
        Description = "Hides Start Menu recommended section via PolicyManager"
    },
    @{
        Path = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education"
        Name = "IsEducationEnvironment"
        Value = 1
        Description = "Signals education environment to suppress recommendations"
    },
    @{
        Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
        Name = "HideRecommendedSection"
        Value = 1
        Description = "Hides Start Menu recommended section via Explorer policy"
    }
)

foreach ($config in $registryConfigs) {
    try {
        if (-not (Test-Path $config.Path)) {
                if (-not $script:ShouldExecute) {
                Write-Log "WhatIf: Would create registry path: $($config.Path)" -Level 'Warning'
            } else {
                New-Item -Path $config.Path -Force | Out-Null
                Write-Log "Created registry path: $($config.Path)" -Level 'Success'
            }
        }
        
            if (-not $script:ShouldExecute) {
            Write-Log "WhatIf: Would set $($config.Name) to $($config.Value) at $($config.Path)" -Level 'Warning'
        } else {
            New-ItemProperty -Path $config.Path -Name $config.Name -Value $config.Value -PropertyType DWord -Force | Out-Null
            Write-Log "Configured: $($config.Description)" -Level 'Success'
        }
    } catch {
        Write-Log "Failed to configure $($config.Name): $($_.Exception.Message)" -Level 'Error'
    }
}

# --- Summary ---
Write-Information -MessageData '' -Tags 'Info'
Write-Log "--- Removal Summary ---" -Level 'Info'

if ($succeededRemovals.Count -gt 0) {
    Write-Log "Successfully processed $($succeededRemovals.Count) packages:" -Level 'Success'
    $succeededRemovals | ForEach-Object { Write-Log "- $_" -Level 'Success' }
} else {
    Write-Log "No packages were removed or marked for removal." -Level 'Warning'
}

if ($failedRemovals.Count -gt 0) {
    Write-Log "Failed to remove $($failedRemovals.Count) packages:" -Level 'Error'
    $failedRemovals | ForEach-Object { Write-Log "- $_" -Level 'Error' }
}

Write-Log "=== Bloatware removal completed ===" -Level 'Info'
Write-Log "Log file saved to: $LogPath" -Level 'Info'
Write-Log "Bloatware removal script finished." -Level 'Success'