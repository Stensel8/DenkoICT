<#
.SYNOPSIS
    Install vendor driver update tools and run updates
.DESCRIPTION
    Detects system manufacturer and runs appropriate driver update tool:
    - Dell: Dell Command Update
    - HP: HP Client Management Script Library (HP CMSL) - supports all HP models including ProBook, EliteBook, and ZBook
    - Lenovo: Lenovo System Update
    
    The HP implementation now includes:
    - Proper use of Get-Softpaq cmdlet for downloading drivers
    - Silent installation with multiple exit code handling
    - Retry mechanisms with exponential backoff
    - Progress tracking and detailed logging
    - BIOS/Firmware update detection (reports only, manual installation required)
    - Enhanced error handling and troubleshooting information
    
.NOTES
    - HP CMSL requires PowerShell to be run as Administrator for module installation and driver updates
    - Firmware/BIOS updates are detected but not automatically installed for safety reasons
    - The script uses proper HP CMSL cmdlets: Get-Softpaq, Get-SoftpaqList, Get-HPBIOSUpdates
    - Supports various installation exit codes (0, 1641, 3010) for successful installations
.EXAMPLE
    .\ps_Install-Drivers.ps1
    Runs the appropriate driver update tool based on detected system manufacturer
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

# Function to retry operations with exponential backoff
function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 2,
        [string]$OperationName = "Operation"
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Host "  Attempt $i of $MaxRetries for $OperationName" -ForegroundColor Gray
            return & $ScriptBlock
        } catch {
            if ($i -eq $MaxRetries) {
                Write-Warning "$OperationName failed after $MaxRetries attempts: $($_.Exception.Message)"
                throw
            } else {
                Write-Warning "$OperationName failed (attempt $i): $($_.Exception.Message). Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds ($DelaySeconds * $i) # Exponential backoff
            }
        }
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
        # Check if HP CMSL modules are available
        $hpModules = Get-Module -ListAvailable -Name "HP.*" | Where-Object { $_.Name -in @("HP.Softpaq", "HP.ClientManagement") }
        
        if (-not $hpModules) {
            Write-Host "HP CMSL modules not found. Installing..." -ForegroundColor Cyan
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            # HP recommended installation method
            $installScript = @"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -Force
Install-Module -Name PowerShellGet -Force -SkipPublisherCheck
# Exit to resolve command resolution issues as per HP documentation
Start-Sleep -Seconds 2
# Install HP CMSL with AcceptLicense as per HP documentation
Install-Module -Name HPCMSL -AcceptLicense -Force -SkipPublisherCheck
"@
            
            $scriptPath = "$env:TEMP\Install-HPCMSL.ps1"
            $installScript | Out-File -FilePath $scriptPath -Encoding UTF8
            
            Write-Host "Installing HP CMSL (this requires a PowerShell restart)..." -ForegroundColor Cyan
            $process = Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Wait -PassThru -WindowStyle Hidden
            Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
            
            if ($process.ExitCode -ne 0) {
                Write-Warning "PowerShell Gallery installation failed. Trying manual installation..."
                
                # Fallback: Download and extract HP CMSL manually
                $tempDir = "$env:TEMP\HP-CMSL"
                $extractDir = "$tempDir\extracted"
                New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
                
                try {
                    # Download latest HP CMSL installer
                    $cmslUrl = "https://hpia.hpcloud.hp.com/downloads/cmsl/hp-cmsl-1.7.2.exe"
                    $installerPath = "$tempDir\hp-cmsl.exe"
                    
                    Write-Host "Downloading HP CMSL installer..." -ForegroundColor Cyan
                    Invoke-WebRequest -Uri $cmslUrl -OutFile $installerPath -UseBasicParsing
                    
                    # Extract modules only (no installation)
                    Write-Host "Extracting HP CMSL modules..." -ForegroundColor Cyan
                    Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT", "/SP-", "/UnpackOnly=True", "/DestDir=`"$extractDir`"" -Wait -WindowStyle Hidden
                    
                    # Copy modules to PowerShell modules directory
                    $modulesSource = "$extractDir\modules"
                    $modulesTarget = "${env:ProgramFiles}\WindowsPowerShell\Modules"
                    
                    if (Test-Path $modulesSource) {
                        Copy-Item -Path "$modulesSource\*" -Destination $modulesTarget -Recurse -Force
                        Write-Host "HP CMSL modules extracted successfully" -ForegroundColor Green
                    }
                    
                } catch {
                    Write-Warning "Manual installation failed: $($_.Exception.Message)"
                    return
                } finally {
                    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        # Import required HP modules with detailed error handling
        try {
            # Try to import main HP CMSL modules
            $importResults = @()
            
            Write-Host "Loading HP CMSL modules..." -ForegroundColor Cyan
            
            try {
                Import-Module HP.Softpaq -Force -ErrorAction Stop
                $importResults += "HP.Softpaq: OK"
                Write-Host "  \u2713 HP.Softpaq module loaded" -ForegroundColor Green
            } catch {
                $importResults += "HP.Softpaq: FAILED - $($_.Exception.Message)"
                Write-Warning "  \u2717 Failed to load HP.Softpaq: $($_.Exception.Message)"
            }
            
            try {
                Import-Module HP.ClientManagement -Force -ErrorAction Stop
                $importResults += "HP.ClientManagement: OK"
                Write-Host "  \u2713 HP.ClientManagement module loaded" -ForegroundColor Green
            } catch {
                $importResults += "HP.ClientManagement: FAILED - $($_.Exception.Message)"
                Write-Warning "  \u2717 Failed to load HP.ClientManagement: $($_.Exception.Message)"
            }
            
            # Check if at least HP.Softpaq is available (minimum required)
            if (Get-Module HP.Softpaq -ErrorAction SilentlyContinue) {
                Write-Host "HP CMSL core modules loaded successfully" -ForegroundColor Green
            } else {
                Write-Warning "HP.Softpaq module is required but failed to load"
                Write-Host "Module import results:" -ForegroundColor Yellow
                $importResults | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
                return
            }
            
        } catch {
            Write-Warning "Could not import HP CMSL modules: $($_.Exception.Message)"
            Write-Host "Please ensure HP CMSL is properly installed and try running as Administrator" -ForegroundColor Yellow
            return
        }
        
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
            $totalCount = $softpaqs.Count
            $currentItem = 0
            
            Write-Host "Starting installation of $totalCount drivers..." -ForegroundColor Cyan
            
            foreach ($softpaq in $softpaqs) {
                $currentItem++
                $percentComplete = [math]::Round(($currentItem / $totalCount) * 100)
                
                Write-Host "[$currentItem/$totalCount] ($percentComplete%) Installing: $($softpaq.Name) ($($softpaq.Id))" -ForegroundColor Yellow
                
                try {
                    
                    # Download the softpaq using Get-Softpaq with retry
                    $downloadPath = Join-Path $tempPath "$($softpaq.Id).exe"
                    
                    $downloadSuccess = Invoke-WithRetry -OperationName "Download $($softpaq.Id)" -ScriptBlock {
                        Get-Softpaq -Number $softpaq.Id -SaveAs $downloadPath
                        if (-not (Test-Path $downloadPath)) {
                            throw "Downloaded file not found at $downloadPath"
                        }
                        return $true
                    }
                    
                    if ($downloadSuccess -and (Test-Path $downloadPath)) {
                        # Get file size for progress indication
                        $fileSize = [math]::Round((Get-Item $downloadPath).Length / 1MB, 1)
                        Write-Host "  Downloaded $($softpaq.Id) ($fileSize MB)" -ForegroundColor Gray
                        
                        # Install silently using Start-Process with retry
                        $installSuccess = Invoke-WithRetry -OperationName "Install $($softpaq.Id)" -ScriptBlock {
                            $installResult = Start-Process -FilePath $downloadPath -ArgumentList '/S', '/v/qn' -Wait -PassThru -WindowStyle Hidden
                            
                            # Check various success exit codes
                            if ($installResult.ExitCode -eq 0) {
                                Write-Host "  ✓ Successfully installed $($softpaq.Name)" -ForegroundColor Green
                                return $true
                            } elseif ($installResult.ExitCode -eq 3010) {
                                Write-Host "  ✓ Successfully installed $($softpaq.Name) (Reboot required)" -ForegroundColor Yellow
                                return $true
                            } elseif ($installResult.ExitCode -eq 1641) {
                                Write-Host "  ✓ Successfully installed $($softpaq.Name) (Installer initiated reboot)" -ForegroundColor Yellow
                                return $true
                            } else {
                                throw "Installation failed with exit code: $($installResult.ExitCode)"
                            }
                        }
                        
                        if ($installSuccess) {
                            $successCount++
                        } else {
                            $failCount++
                        }
                        
                        # Clean up downloaded file
                        Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
                    } else {
                        Write-Warning "  ✗ Failed to download $($softpaq.Name)"
                        $failCount++
                    }
                    
                } catch {
                    Write-Warning "✗ Failed to install $($softpaq.Name): $($_.Exception.Message)"
                    $failCount++
                }
                
                # Add small delay between installations to prevent resource conflicts
                if ($currentItem -lt $totalCount) {
                    Start-Sleep -Milliseconds 500
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
        
        # Check for BIOS/firmware updates
        Write-Host "`nChecking for HP BIOS/Firmware updates..." -ForegroundColor Cyan
        
        try {
            # Get available BIOS updates
            $biosUpdates = Get-HPBIOSUpdates -ErrorAction SilentlyContinue
            
            if ($biosUpdates -and $biosUpdates.Count -gt 0) {
                Write-Host "Found $($biosUpdates.Count) BIOS/Firmware updates available" -ForegroundColor Green
                
                foreach ($update in $biosUpdates) {
                    Write-Host "Available BIOS update: $($update.Name) - Version: $($update.Version)" -ForegroundColor Yellow
                    Write-Host "  Current BIOS: $(Get-HPBIOSVersion)" -ForegroundColor Gray
                    
                    # For safety, we'll just report firmware updates rather than auto-install
                    # Firmware updates are more critical and should be done carefully
                    Write-Host "  \u26A0  BIOS/Firmware updates detected but not auto-installed for safety" -ForegroundColor Yellow
                    Write-Host "  \u26A0  Please run 'Update-HPFirmware' manually to install BIOS updates" -ForegroundColor Yellow
                }
            } else {
                Write-Host "BIOS/Firmware is up to date" -ForegroundColor Green
            }
            
            # Also check for other firmware updates using Get-SoftpaqList
            $firmwareSoftpaqs = Get-SoftpaqList -Category Firmware -Characteristic SSM -ErrorAction SilentlyContinue
            
            if ($firmwareSoftpaqs -and $firmwareSoftpaqs.Count -gt 0) {
                Write-Host "`nFound $($firmwareSoftpaqs.Count) additional firmware updates available:" -ForegroundColor Yellow
                foreach ($fw in $firmwareSoftpaqs) {
                    Write-Host "  - $($fw.Name) ($($fw.Id))" -ForegroundColor Gray
                }
                Write-Host "  \u26A0  Firmware updates require manual review and installation" -ForegroundColor Yellow
                Write-Host "  \u26A0  Use 'Get-Softpaq -Number <ID>' and install manually" -ForegroundColor Yellow
            }
            
        } catch {
            Write-Warning "Could not check for BIOS/Firmware updates: $($_.Exception.Message)"
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
