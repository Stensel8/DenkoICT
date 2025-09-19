param(
    [switch]$WhatIf    # Set -WhatIf when testing to avoid destructive changes
)

param(
    [switch]$WhatIf    # Set -WhatIf when testing to avoid destructive changes
)

# List of unwanted apps to remove. Wildcards (*) are supported.
$AppsToRemove = @(
    # Communication and Social
    "Microsoft.SkypeApp",
    "Microsoft.YourPhone",
    "MicrosoftTeams", # This is the new personal Teams app in Windows 11
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
    "Microsoft.Start", # Successor to BingNews
    "Microsoft.BingSearch",
    "Microsoft.WebExperiencePack", # Widgets and other web content

    # System & Utility (use with caution)
    "Microsoft.PowerAutomateDesktop"
)

# --- Functions ---

function Log {
    param($Message)
    $time = Get-Date -Format 's'
    Write-Output "[$time] $Message"
}

function Remove-AppxByPattern {
    param(
        [string]$Pattern,
        [switch]$WhatIf,
        [System.Collections.ArrayList]$Succeeded,
        [System.Collections.ArrayList]$Failed
    )

    Log "Searching installed packages matching: $Pattern"
    $matches = Get-AppxPackage -AllUsers -Name $Pattern

    if (-not $matches) {
        Log "No installed packages found for pattern: $Pattern"
        return
    }

    foreach ($pkg in $matches) {
        $packageName = $pkg.PackageFullName
        Log "Found installed package: $($pkg.Name) | $packageName"
        if ($WhatIf) {
            Log "WhatIf: Would remove package $packageName for all users"
            $Succeeded.Add("Would remove: $packageName") | Out-Null
        } else {
            try {
                Remove-AppxPackage -Package $packageName -AllUsers -ErrorAction Stop
                Log "Successfully removed package: $packageName"
                $Succeeded.Add("Removed: $packageName") | Out-Null
            } catch {
                Log "Failed to remove package $packageName: $($_.Exception.Message)"
                $Failed.Add("Failed to remove: $packageName") | Out-Null
            }
        }
    }
}

function Remove-ProvisionedByPattern {
    param(
        [string]$Pattern,
        [switch]$WhatIf,
        [System.Collections.ArrayList]$Succeeded,
        [System.Collections.ArrayList]$Failed
    )

    Log "Searching provisioned packages matching: $Pattern"
    $provPackages = Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like $Pattern }

    if (-not $provPackages) {
        Log "No provisioned packages found for pattern: $Pattern"
        return
    }

    foreach ($p in $provPackages) {
        $packageName = $p.PackageName
        Log "Found provisioned package: $($p.DisplayName) | $packageName"
        if ($WhatIf) {
            Log "WhatIf: Would remove provisioned package $packageName"
            $Succeeded.Add("Would remove provisioned: $packageName") | Out-Null
        } else {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $packageName -ErrorAction Stop
                Log "Successfully removed provisioned package: $packageName"
                $Succeeded.Add("Removed provisioned: $packageName") | Out-Null
            } catch {
                Log "Failed to remove provisioned package $packageName: $($_.Exception.Message)"
                $Failed.Add("Failed to remove provisioned: $packageName") | Out-Null
            }
        }
    }
}

# --- Main Execution ---

# Arrays to hold the results
$succeededRemovals = [System.Collections.ArrayList]@()
$failedRemovals = [System.Collections.ArrayList]@()

# Iterate over the entries and apply both provisioned and installed removals
foreach ($appName in $AppsToRemove) {
    $pattern = "*$appName*"
    
    Remove-AppxByPattern -Pattern $pattern -WhatIf:$WhatIf -Succeeded $succeededRemovals -Failed $failedRemovals
    Remove-ProvisionedByPattern -Pattern $pattern -WhatIf:$WhatIf -Succeeded $succeededRemovals -Failed $failedRemovals
}

# --- Summary ---
Write-Host "`n--- Removal Summary ---" -ForegroundColor Green

if ($succeededRemovals.Count -gt 0) {
    Write-Host "`nSuccessfully processed $($succeededRemovals.Count) packages:" -ForegroundColor Green
    $succeededRemovals | ForEach-Object { Write-Host "- $_" -ForegroundColor Gray }
} else {
    Write-Host "`nNo packages were removed or marked for removal." -ForegroundColor Yellow
}

if ($failedRemovals.Count -gt 0) {
    Write-Host "`nFailed to remove $($failedRemovals.Count) packages:" -ForegroundColor Red
    $failedRemovals | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
}

Write-Host "`nBloatware removal script finished." -ForegroundColor Green

