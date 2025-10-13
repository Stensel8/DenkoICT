<#PSScriptInfo

.VERSION 1.4.0

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
[Version 1.4.0] - Improved speed by caching installed and provisioned packages, reducing redundant PowerShell calls.
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

.EXAMPLE
    .\ps_Remove-Bloat.ps1
    
    Removes all bloatware applications and configures prevention settings.

.EXAMPLE
    .\ps_Remove-Bloat.ps1 -WhatIf
    
    Shows what would be removed without making any changes.

.EXAMPLE
    .\ps_Remove-Bloat.ps1 -SkipLogging
    
    Removes bloatware without creating a log file.

.OUTPUTS
    Console output with removal summary and detailed log file in C:\DenkoICT\Logs\.

.NOTES
    Version      : 1.4.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    
    Supports -WhatIf for safe simulation.
    Requires administrative privileges for full effectiveness.
    Registry changes prevent automatic reinstallation of bloatware.
    Logs are saved to C:\DenkoICT\Logs\ps_Remove-Bloat.ps1.log
    
    Registry modifications:
    - DisableWindowsConsumerFeatures: Prevents bloatware auto-installation
    - Start_IrisRecommendations: Disables Start Menu suggestions

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'None')]

# --- Elevate if necessary ---
$currentIdentity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log "Elevation required. Restarting script with administrative privileges..." -Level 'Warning'
    try {
        $hostPath     = (Get-Process -Id $PID -ErrorAction Stop).Path
        $argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        Start-Process -FilePath $hostPath -ArgumentList $argumentList -Verb RunAs | Out-Null
    } catch {
        Write-Log "Failed to restart with elevated privileges: $($_.Exception.Message)" -Level 'Error'
    }
    exit
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Remove Appx module if already loaded to prevent assembly conflicts
try {
    if (Get-Module -Name Appx) {
        Remove-Module -Name Appx -Force -ErrorAction SilentlyContinue
    }
} catch {
    # Ignore errors during module removal
}

# Load custom functions - check multiple locations
$functionsPath = $null
$possiblePaths = @(
    (Join-Path $PSScriptRoot 'ps_Custom-Functions.ps1'),
    'C:\DenkoICT\Download\ps_Custom-Functions.ps1',
    (Join-Path (Split-Path $PSCommandPath -Parent) 'ps_Custom-Functions.ps1')
)

foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $functionsPath = $path
        break
    }
}

if (-not $functionsPath) {
    Write-Error "Required functions file not found. Searched locations: $($possiblePaths -join ', ')"
    exit 1
}

Write-Verbose "Loading custom functions from: $functionsPath"
. $functionsPath

# Initialize logging
$Global:DenkoConfig.LogName = "ps_Remove-Bloat.ps1.log"
Start-Logging

$script:ShouldExecute = $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Remove Denko ICT bloatware packages and policies')

# List of unwanted apps to remove. Wildcards (*) are supported.
$AppsToRemove = @(
    # === Microsoft Apps ===
    
    # Communication and Social
    "Microsoft.SkypeApp",                       # Skype communication app (UWP version)
    "Microsoft.YourPhone",
    "Microsoft.People",
    "Microsoft.Messaging",                      # Messaging app (largely deprecated)

    # Media and Entertainment
    "Microsoft.GamingApp",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxApp",                        # Old Xbox Console Companion App (no longer supported)
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.ZuneMusic",                      # Groove Music (legacy)
    "Microsoft.ZuneVideo",                      # Movies & TV app (rebranded as Films & TV)
    "Microsoft.MicrosoftSolitaireCollection",   # Collection of solitaire card games
    "Microsoft.Media.Player",                   # New Media Player
    
    # Productivity and Tools
    "Microsoft.Todos",                          # To-do list and task management app
    "Microsoft.WindowsMaps",                    # Mapping and navigation app
    "Microsoft.MicrosoftStickyNotes",           # Digital sticky notes (deprecated, replaced by OneNote)
    "Microsoft.MicrosoftOfficeHub",             # Office hub (precursor to Microsoft 365 app)
    "Microsoft.OneConnect",                     # Mobile Plans
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",                     # Tips app (cannot be uninstalled in Windows 11)
    "Microsoft.WindowsFeedbackHub",             # App for providing feedback to Microsoft
    "Microsoft.Microsoft3DViewer",              # Viewer for 3D models
    "Microsoft.3DBuilder",                      # Basic 3D modeling software
    "Microsoft.Print3D",                        # 3D printing preparation software
    "Microsoft.MixedReality.Portal",            # Portal for Windows Mixed Reality headsets
    "Microsoft.Clipchamp",                      # Video editor from Microsoft
    "Clipchamp.Clipchamp",                      # Video editor from Microsoft (alternative package name)
    "9P1J8S7CCWWT",                             # Clipchamp Product ID
    "MicrosoftCorporationII.MicrosoftFamily",   # Family Safety App
    "Microsoft.WindowsAlarms",                  # Alarms & Clock app
    "Microsoft.ScreenSketch",                   # Snip & Sketch
    "Microsoft.Wallet",
    "Microsoft.NetworkSpeedTest",               # Internet connection speed test utility
    "Microsoft.MicrosoftJournal",               # Digital note-taking app optimized for pen input
    "Microsoft.MicrosoftPowerBIForWindows",     # Business analytics service client
    "Microsoft.Office.Sway",                    # Presentation and storytelling app

    # News, Weather, and Information
    "Microsoft.BingNews",                       # News aggregator via Bing
    "Microsoft.BingWeather",                    # Weather forecast via Bing
    "Microsoft.BingFinance",                    # Finance news and tracking (discontinued)
    "Microsoft.BingFoodAndDrink",               # Recipes and food news (discontinued)
    "Microsoft.BingHealthAndFitness",           # Health and fitness tracking (discontinued)
    "Microsoft.BingSports",                     # Sports news and scores (discontinued)
    "Microsoft.BingTranslator",                 # Translation service via Bing
    "Microsoft.BingTravel",                     # Travel planning and news (discontinued)
    "Microsoft.News",                           # News aggregator (replaced Bing News, now part of Microsoft Start)
    "Microsoft.Start",                          # Successor to BingNews
    "Microsoft.BingSearch",
    "Microsoft.WebExperiencePack",              # Widgets and other web content

    # AI and Assistant
    "Microsoft.Copilot",                        # AI assistant integrated into Windows
    "Microsoft.549981C3F5F10",                  # Cortana app (discontinued)

    # System & Utility (use with caution)
    "Microsoft.PowerAutomateDesktop",

    # === Third Party Apps ===
    
    # Social Media
    "Facebook",
    "Instagram",
    "Twitter",
    "TikTok",
    "LinkedInforWindows",
    "XING",
    
    # Entertainment and Streaming
    "SpotifyAB.SpotifyMusic",
    "Spotify",
    "Netflix",
    "AmazonVideo.PrimeVideo",
    "Amazon.com.Amazon",
    "HULULLC.HULUPLUS",
    "Plex",
    "Disney",
    "DisneyMagicKingdoms",
    "SlingTV",
    "PandoraMediaInc",
    "iHeartRadio",
    "TuneInRadio",
    "Shazam",
    
    # Games
    "king.com.CandyCrushSaga",
    "king.com.CandyCrushSodaSaga",
    "king.com.BubbleWitch3Saga",
    "CaesarsSlotsFreeCasino",
    "COOKINGFEVER",
    "FarmVille2CountryEscape",
    "MarchofEmpires",
    "Royal Revolt",
    "Asphalt8Airborne",
    "HiddenCity",
    
    # Productivity and Utilities
    "Duolingo-LearnLanguagesforFree",
    "NYTCrossword",
    "Flipboard",
    "OneCalendar",
    "Wunderlist",
    "fitbit",
    "Viber",
    "WinZipUniversal",
    "EclipseManager",
    "Sidia.LiveWallpaper",
    
    # Creative and Photo Editing
    "AdobeSystemsIncorporated.AdobePhotoshopExpress",
    "AutodeskSketchBook",
    "DrawboardPDF",
    "PhototasticCollage",
    "PicsArt-PhotoStudio",
    "PolarrPhotoEditorAcademicEdition",
    "ActiproSoftwareLLC",
    "ACGMediaPlayer",
    "CyberLinkMediaSuiteEssentials"
)

# --- Functions ---

# Cache for packages to avoid redundant queries
$script:InstalledPackagesCache = $null
$script:ProvisionedPackagesCache = $null

function Get-CachedInstalledPackages {
    if ($null -eq $script:InstalledPackagesCache) {
        Write-Log "Caching all installed packages for faster pattern matching..."
        $useWindowsPowerShell = $PSVersionTable.PSVersion.Major -ge 7
        
        if ($useWindowsPowerShell) {
            try {
                $scriptBlock = @"
Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName | ConvertTo-Json -Compress
"@
                $result = powershell.exe -NoProfile -Command $scriptBlock
                if ($result -and $result -ne "null") {
                    $script:InstalledPackagesCache = $result | ConvertFrom-Json
                    if ($script:InstalledPackagesCache -isnot [array]) {
                        $script:InstalledPackagesCache = @($script:InstalledPackagesCache)
                    }
                } else {
                    $script:InstalledPackagesCache = @()
                }
            } catch {
                Write-Log "Error caching installed packages: $($_.Exception.Message)" -Level 'Warning'
                $script:InstalledPackagesCache = @()
            }
        } else {
            try {
                $script:InstalledPackagesCache = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Select-Object Name, PackageFullName)
            } catch {
                Write-Log "Error caching installed packages: $($_.Exception.Message)" -Level 'Warning'
                $script:InstalledPackagesCache = @()
            }
        }
        Write-Log "Cached $($script:InstalledPackagesCache.Count) installed packages"
    }
    return $script:InstalledPackagesCache
}

function Get-CachedProvisionedPackages {
    if ($null -eq $script:ProvisionedPackagesCache) {
        Write-Log "Caching all provisioned packages for faster pattern matching..."
        $useWindowsPowerShell = $PSVersionTable.PSVersion.Major -ge 7
        
        if ($useWindowsPowerShell) {
            try {
                $scriptBlock = @"
Get-AppxProvisionedPackage -Online | Select-Object PackageName, DisplayName | ConvertTo-Json -Compress
"@
                $result = powershell.exe -NoProfile -Command $scriptBlock
                if ($result -and $result -ne "null") {
                    $script:ProvisionedPackagesCache = $result | ConvertFrom-Json
                    if ($script:ProvisionedPackagesCache -isnot [array]) {
                        $script:ProvisionedPackagesCache = @($script:ProvisionedPackagesCache)
                    }
                } else {
                    $script:ProvisionedPackagesCache = @()
                }
            } catch {
                Write-Log "Error caching provisioned packages: $($_.Exception.Message)" -Level 'Warning'
                $script:ProvisionedPackagesCache = @()
            }
        } else {
            try {
                $script:ProvisionedPackagesCache = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Select-Object PackageName, DisplayName)
            } catch {
                Write-Log "Error caching provisioned packages: $($_.Exception.Message)" -Level 'Warning'
                $script:ProvisionedPackagesCache = @()
            }
        }
        Write-Log "Cached $($script:ProvisionedPackagesCache.Count) provisioned packages"
    }
    return $script:ProvisionedPackagesCache
}

function Remove-AppxByPattern {
    param(
        [string]$Pattern,
        [System.Collections.ArrayList]$Succeeded,
        [System.Collections.ArrayList]$Failed
    )

    Write-Log "Searching installed packages matching: $Pattern"
    
    # Use cached packages instead of making individual queries
    $cachedPackages = Get-CachedInstalledPackages
    $matchedPackages = $cachedPackages | Where-Object { 
        $_.Name -like $Pattern -or $_.PackageFullName -like $Pattern 
    }

    if (-not $matchedPackages) {
        Write-Log "No installed packages found for pattern: $Pattern"
        return
    }

    # Use Windows PowerShell for Appx operations to avoid assembly conflicts in PS7
    $useWindowsPowerShell = $PSVersionTable.PSVersion.Major -ge 7

    foreach ($pkg in $matchedPackages) {
        $packageName = $pkg.PackageFullName
        Write-Log "Found installed package: $($pkg.Name) | $packageName"
        
        if (-not $script:ShouldExecute) {
            Write-Log "WhatIf: Would remove package $packageName for all users" -Level 'Warning'
            $Succeeded.Add("Would remove: $packageName") | Out-Null
        } else {
            try {
                if ($useWindowsPowerShell) {
                    # Use Windows PowerShell to remove the package
                    $removeScript = "Remove-AppxPackage -Package '$packageName' -AllUsers -ErrorAction Stop"
                    $removeResult = powershell.exe -NoProfile -Command $removeScript 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "Removal failed with exit code $LASTEXITCODE : $removeResult"
                    }
                } else {
                    Remove-AppxPackage -Package $packageName -AllUsers -ErrorAction Stop
                }
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
    
    # Use cached packages instead of making individual queries
    $cachedPackages = Get-CachedProvisionedPackages
    $provPackages = $cachedPackages | Where-Object { 
        $_.PackageName -like $Pattern 
    }

    if (-not $provPackages) {
        Write-Log "No provisioned packages found for pattern: $Pattern"
        return
    }

    # Use Windows PowerShell for DISM operations to avoid assembly conflicts in PS7
    $useWindowsPowerShell = $PSVersionTable.PSVersion.Major -ge 7

    foreach ($p in $provPackages) {
        $packageName = $p.PackageName
        Write-Log "Found provisioned package: $($p.DisplayName) | $packageName"
        
        if (-not $script:ShouldExecute) {
            Write-Log "WhatIf: Would remove provisioned package $packageName" -Level 'Warning'
            $Succeeded.Add("Would remove provisioned: $packageName") | Out-Null
        } else {
            try {
                if ($useWindowsPowerShell) {
                    # Use Windows PowerShell to remove the provisioned package
                    $removeScript = "Remove-AppxProvisionedPackage -Online -PackageName '$packageName' -ErrorAction Stop"
                    $removeResult = powershell.exe -NoProfile -Command $removeScript 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "Removal failed with exit code $LASTEXITCODE : $removeResult"
                    }
                } else {
                    Remove-AppxProvisionedPackage -Online -PackageName $packageName -ErrorAction Stop
                }
                Write-Log "Successfully removed provisioned package: $packageName" -Level 'Success'
                $Succeeded.Add("Removed provisioned: $packageName") | Out-Null
            } catch {
                # Check if it's a "path not found" error (package already removed by earlier operation)
                if ($_.Exception.Message -match "Het systeem kan het opgegeven pad niet vinden|The system cannot find the path specified") {
                    Write-Log "Provisioned package already removed or not found: $packageName" -Level 'Info'
                    $Succeeded.Add("Already removed: $packageName") | Out-Null
                } else {
                    Write-Log "Failed to remove provisioned package $($packageName): $($_.Exception.Message)" -Level 'Error'
                    $Failed.Add("Failed to remove provisioned: $packageName") | Out-Null
                }
            }
        }
    }
}

# --- Main Execution ---

try {
    Write-Log "=== Bloatware Removal Started ===" -Level 'Info'
    $startTime = Get-Date
    Write-Log "User: $env:USERNAME" -Level 'Info'
    Write-Log "Computer: $env:COMPUTERNAME" -Level 'Info'
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" -Level 'Info'
    
    # Indicate which method will be used for Appx operations
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Log "Using Windows PowerShell for Appx operations to avoid assembly conflicts" -Level 'Info'
    } else {
        Write-Log "Using native Appx cmdlets (Windows PowerShell)" -Level 'Info'
    }

    # Arrays to hold the results
    $succeededRemovals = [System.Collections.ArrayList]::new()
    $failedRemovals = [System.Collections.ArrayList]::new()

    # Iterate over the entries and apply both provisioned and installed removals (optimized)
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
                    New-Item -Path $config.Path -Force | Out-Null
                    Write-Log "Created registry path: $($config.Path)" -Level 'Success'
            }
            
            New-ItemProperty -Path $config.Path -Name $config.Name -Value $config.Value -PropertyType DWord -Force | Out-Null
            Write-Log "Configured: $($config.Description)" -Level 'Success'
        } catch {
            Write-Log "Failed to configure $($config.Name): $($_.Exception.Message)" -Level 'Error'
        }
    }

    # --- Summary ---
    Write-Log "" -Level 'Info'
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
    $endTime = Get-Date
    $duration = $endTime - $startTime
    Write-Log "Total execution time: $($duration.TotalSeconds.ToString('F1')) seconds" -Level 'Info'
    Write-Log "Bloatware removal script finished." -Level 'Success'
} catch {
    Write-Log "Critical error during bloatware removal: $($_.Exception.Message)" -Level 'Error'
    throw
} finally {
    Stop-Logging
}