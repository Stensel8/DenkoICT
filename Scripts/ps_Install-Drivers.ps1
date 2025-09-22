<#
.SYNOPSIS
    Install vendor driver update tools and run updates
.DESCRIPTION
    Detects system manufacturer and runs appropriate driver update tool:
    - Dell: Dell Command Update
    - HP: HP Client Management Script Library (HP CMSL) - supports all HP models including ProBook, EliteBook, and ZBook
    - Lenovo: Lenovo System Update
.NOTES
    HP CMSL requires PowerShell to be run as Administrator for module installation and driver updates.
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

# HP CMSL (Client Management Script Library)
function Update-HPDrivers {
    Write-Host "Installing HP Client Management Script Library (HP CMSL)..." -ForegroundColor Yellow
    
    try {
        # Check if HPCMSL module is installed
        if (-not (Get-Module -ListAvailable -Name HPCMSL)) {
            Write-Host "Installing HPCMSL PowerShell module..." -ForegroundColor Cyan
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
            Install-Module -Name HPCMSL -Force -Scope AllUsers -AllowClobber | Out-Null
        }
        
        # Import the module
        Import-Module HPCMSL -Force
        
        Write-Host "Detecting available HP driver updates..." -ForegroundColor Cyan
        
        # Get available softpaqs (drivers) for this system
        $softpaqs = Get-SoftpaqList -Category Driver -Characteristic SSM
        
        if ($softpaqs -and $softpaqs.Count -gt 0) {
            Write-Host "Found $($softpaqs.Count) driver updates available" -ForegroundColor Green
            
            # Create temp directory for downloads
            $tempPath = "$env:TEMP\HPDrivers"
            if (-not (Test-Path $tempPath)) {
                New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
            }
            
            $successCount = 0
            $failCount = 0
            
            foreach ($softpaq in $softpaqs) {
                try {
                    Write-Host "Installing driver: $($softpaq.Name) ($($softpaq.Id))" -ForegroundColor Yellow
                    
                    # Download and install the softpaq
                    Install-SoftPaq -Number $softpaq.Id -DestinationPath $tempPath -Quiet
                    $successCount++
                    
                } catch {
                    Write-Warning "Failed to install $($softpaq.Name): $($_.Exception.Message)"
                    $failCount++
                }
            }
            
            # Cleanup temp directory
            Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            
            Write-Host "`nHP driver update summary:" -ForegroundColor Cyan
            Write-Host "  Successfully installed: $successCount drivers" -ForegroundColor Green
            if ($failCount -gt 0) {
                Write-Host "  Failed installations: $failCount drivers" -ForegroundColor Red
            }
            
        } else {
            Write-Host "No HP driver updates available for this system" -ForegroundColor Green
        }
        
    } catch {
        Write-Warning "HP CMSL driver update failed: $($_.Exception.Message)"
        Write-Host "You may need to run this script as Administrator or check your internet connection" -ForegroundColor Yellow
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
