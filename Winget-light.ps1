# Simple WinGet installer for RMM deployment
Write-Host "Checking for WinGet..." -ForegroundColor Cyan

if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "WinGet is already installed" -ForegroundColor Green
    winget --version
} else {
    Write-Host "WinGet not found. Installing..." -ForegroundColor Yellow
    
    try {
        # Method 1: Try Microsoft Store approach (Windows 10 1809+)
        Write-Host "Attempting installation via Microsoft Store..." 
        $progressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile "$env:TEMP\AppInstaller.msixbundle" -UseBasicParsing
        Add-AppxPackage -Path "$env:TEMP\AppInstaller.msixbundle"
        Remove-Item "$env:TEMP\AppInstaller.msixbundle" -Force -ErrorAction SilentlyContinue
        
        # Wait and refresh environment
        Start-Sleep 3
        $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "WinGet installed successfully!" -ForegroundColor Green
            winget --version
        } else {
            Write-Host "Installation may have succeeded but WinGet not immediately available. Try restarting PowerShell." -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
        
        # Method 2: Alternative download URL with process handling
        try {
            Write-Host "Trying alternative installation method..." -ForegroundColor Yellow
            
            # Kill any running winget/AppInstaller processes first
            Write-Host "Stopping any running App Installer processes..."
            Get-Process | Where-Object { $_.ProcessName -like "*AppInstaller*" -or $_.ProcessName -like "*winget*" } | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep 2
            
            $releases = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
            $downloadUrl = ($releases.assets | Where-Object { $_.name -like "*.msixbundle" }).browser_download_url
            
            if (-not $downloadUrl) {
                throw "Could not find msixbundle in GitHub releases"
            }
            
            Write-Host "Downloading from: $downloadUrl"
            Invoke-WebRequest -Uri $downloadUrl -OutFile "$env:TEMP\winget.msixbundle" -UseBasicParsing
            
            # Check if file was downloaded
            if (-not (Test-Path "$env:TEMP\winget.msixbundle")) {
                throw "Download failed - file not found"
            }
            
            Write-Host "Installing package..."
            try {
                Add-AppxPackage -Path "$env:TEMP\winget.msixbundle" -ErrorAction Stop
            } catch {
                if ($_.Exception.Message -match "0x80073D02|in gebruik|in use") {
                    Write-Host "App is still in use. Trying forced installation..." -ForegroundColor Yellow
                    
                    # Try to remove existing package first
                    try {
                        Get-AppxPackage "*AppInstaller*" | Remove-AppxPackage -ErrorAction SilentlyContinue
                        Start-Sleep 3
                        Add-AppxPackage -Path "$env:TEMP\winget.msixbundle" -ErrorAction Stop
                    } catch {
                        # If still failing, try different approach
                        Write-Host "Standard installation failed. Trying PowerShell method..." -ForegroundColor Yellow
                        dism /online /add-provisioned-appx-package /packagepath:"$env:TEMP\winget.msixbundle" /skiplicense 2>$null
                    }
                } else {
                    throw
                }
            }
            
            Remove-Item "$env:TEMP\winget.msixbundle" -Force -ErrorAction SilentlyContinue
            
            Start-Sleep 5  # Give more time for installation to complete
            $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            
            # More thorough check for winget availability
            $attempts = 0
            $maxAttempts = 10
            $wingetFound = $false
            
            while ($attempts -lt $maxAttempts -and -not $wingetFound) {
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    $wingetFound = $true
                    Write-Host "WinGet installed successfully via GitHub!" -ForegroundColor Green
                    winget --version
                } else {
                    $attempts++
                    Write-Host "Waiting for WinGet to become available... ($attempts/$maxAttempts)" -ForegroundColor Yellow
                    Start-Sleep 2
                }
            }
            
            if (-not $wingetFound) {
                Write-Host "WinGet installation may have succeeded but command not available. Try:" -ForegroundColor Yellow
                Write-Host "1. Restart PowerShell session" -ForegroundColor Yellow  
                Write-Host "2. Check Windows Store for App Installer updates" -ForegroundColor Yellow
                Write-Host "3. Reboot system if necessary" -ForegroundColor Yellow
            }
            
        } catch {
            Write-Host "GitHub installation method failed: $($_.Exception.Message)" -ForegroundColor Red
            
            # Method 3: Last resort - manual registration
            try {
                Write-Host "Trying manual registration method..." -ForegroundColor Yellow
                
                # Try to register existing App Installer if present
                $appInstallerPath = Get-AppxPackage -Name "*AppInstaller*" | Select-Object -ExpandProperty InstallLocation -ErrorAction SilentlyContinue
                if ($appInstallerPath) {
                    $manifestPath = Join-Path $appInstallerPath "AppxManifest.xml"
                    if (Test-Path $manifestPath) {
                        Add-AppxPackage -Path $manifestPath -Register -DisableDevelopmentMode -ErrorAction Stop
                        Write-Host "App Installer re-registered successfully!" -ForegroundColor Green
                    }
                }
                
                Start-Sleep 3
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    Write-Host "WinGet is now available!" -ForegroundColor Green
                    winget --version
                } else {
                    Write-Host "Manual registration completed but WinGet still not available." -ForegroundColor Yellow
                }
                
            } catch {
                Write-Host "All installation methods failed. Final error: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Manual steps required:" -ForegroundColor Yellow
                Write-Host "1. Open Microsoft Store and install 'App Installer'" -ForegroundColor White
                Write-Host "2. Or download manually from https://aka.ms/getwinget" -ForegroundColor White
            }
        }
    }
}