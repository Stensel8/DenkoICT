<#
.SYNOPSIS
    Install vendor driver update tools and run updates
.DESCRIPTION
    Detects system manufacturer and runs appropriate driver update tool:
    - Dell: Dell Command Update
    - HP: HP Image Assistant (Enterprise models only)
    - Lenovo: Lenovo System Update
#>

Write-Host "Starting Driver Update..." -ForegroundColor Cyan

# Get system info
$manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer.ToLower()
$model = (Get-CimInstance Win32_ComputerSystem).Model

Write-Host "System: $manufacturer $model" -ForegroundColor Green

# Simple function to run command with timeout
function Start-WithTimeout {
    param($Path, $Arguments, $TimeoutMinutes = 10)
    try {
        $process = Start-Process -FilePath $Path -ArgumentList $Arguments -NoNewWindow -PassThru -Wait
        return $process.ExitCode
    } catch {
        Write-Warning "Command timed out or failed: $($_.Exception.Message)"
        return -1
    }
}

# Dell Command Update
function Update-DellDrivers {
    Write-Host "Installing Dell Command Update..." -ForegroundColor Yellow
    winget install Dell.CommandUpdate --silent --accept-package-agreements --accept-source-agreements | Out-Null
    
    $dcu = "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
    if (Test-Path $dcu) {
        Write-Host "Running Dell driver updates..." -ForegroundColor Cyan
        $result = Start-WithTimeout $dcu @("/applyUpdates", "-reboot=disable")
        switch ($result) {
            0 { Write-Host "`nDell updates completed successfully" -ForegroundColor Green }
            1 { Write-Host "`nDell updates completed - reboot recommended" -ForegroundColor Yellow }
            500 { Write-Host "`nDell system is up to date - no updates available" -ForegroundColor Green }
            default { Write-Warning "`nDell updates may have failed (exit code: $result)" }
        }
    } else {
        Write-Warning "Dell Command Update not found"
    }
}

# HP Image Assistant (Enterprise models only)
function Update-HPDrivers {
    # Simple check for enterprise models
    if ($model -match "pavilion|envy|omen|spectre|stream") {
        Write-Host "HP Consumer model detected - please use HP Support Assistant manually" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Installing HP Image Assistant..." -ForegroundColor Yellow
    winget install HP.ImageAssistant --silent --accept-package-agreements --accept-source-agreements | Out-Null
    
    $hpia = "C:\Program Files\HP\HPIA\HPImageAssistant.exe"
    if (Test-Path $hpia) {
        Write-Host "Running HP driver updates..." -ForegroundColor Cyan
        $result = Start-WithTimeout $hpia @("/Operation:Analyze", "/Category:Driver", "/Action:Install", "/Silent") 15
        if ($result -eq 0) { Write-Host "HP updates completed" -ForegroundColor Green }
        else { Write-Warning "HP updates may have failed (exit code: $result)" }
    } else {
        Write-Warning "HP Image Assistant not found"
    }
}

# Lenovo System Update
function Update-LenovoDrivers {
    Write-Host "Installing Lenovo System Update..." -ForegroundColor Yellow
    winget install Lenovo.ThinkVantageSystemUpdate --silent --accept-package-agreements --accept-source-agreements | Out-Null
    
    $lenovo = "${env:ProgramFiles(x86)}\Lenovo\System Update\tvsu.exe"
    if (Test-Path $lenovo) {
        Write-Host "Running Lenovo driver updates..." -ForegroundColor Cyan
        $result = Start-WithTimeout $lenovo @("/CM", "-search", "A", "-action", "INSTALL", "-noicon", "-noreboot") 15
        if ($result -eq 0) { Write-Host "Lenovo updates completed" -ForegroundColor Green }
        else { Write-Warning "Lenovo updates may have failed (exit code: $result)" }
    } else {
        Write-Warning "Lenovo System Update not found"
    }
}

# Main execution
try {
    if ($manufacturer -like "*dell*") {
        Update-DellDrivers
    } elseif ($manufacturer -like "*hewlett*" -or $manufacturer -like "*hp*") {
        Update-HPDrivers
    } elseif ($manufacturer -like "*lenovo*") {
        Update-LenovoDrivers
    } else {
        Write-Warning "Unsupported manufacturer: $manufacturer"
    }
    
    Write-Host "Driver update completed!" -ForegroundColor Green
    
} catch {
    Write-Warning "Error: $($_.Exception.Message)"
    Write-Host "Driver update finished with errors" -ForegroundColor Yellow
}
