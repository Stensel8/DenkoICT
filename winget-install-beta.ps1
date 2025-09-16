# Robust WinGet installer with dependency management
param(
    [switch]$Force,
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"
$ProgressPreference = 'SilentlyContinue'

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage -ForegroundColor $Color
    $logMessage | Out-File "$env:TEMP\winget-install.log" -Append
}

function Test-InternetConnection {
    try {
        $null = Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing -TimeoutSec 10
        return $true
    } catch {
        return $false
    }
}

function Install-RequiredDependencies {
    Write-Log "Installing required dependencies..." "Yellow"
    
    # Install NuGet provider first (auto-accept all prompts)
    try {
        Write-Log "Installing NuGet provider..." "Cyan"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -ErrorAction SilentlyContinue
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    } catch {
        Write-Log "NuGet provider installation failed: $($_.Exception.Message)" "Yellow"
    }
    
    # Define dependencies with multiple download sources
    $dependencies = @(
        @{
            Name = "Microsoft.VCLibs.140.00.UWPDesktop"
            Urls = @(
                "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx",
                "https://download.microsoft.com/download/9/3/F/93FCF1E7-E6A4-478B-96E7-D4B285925B00/VC_redist.x64.exe"
            )
            File = "VCLibs_Desktop.appx"
        },
        @{
            Name = "Microsoft.VCLibs.140.00"
            Urls = @(
                "https://store.rg-adguard.net/dl/file/Microsoft.VCLibs.140.00_14.0.32530.0_x64__8wekyb3d8bbwe.appx"
            )
            File = "VCLibs_Runtime.appx"
        },
        @{
            Name = "Microsoft.UI.Xaml.2.8"
            Urls = @(
                "https://globalcdn.nuget.org/packages/microsoft.ui.xaml.2.8.6.nupkg",
                "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6"
            )
            File = "UIXaml"
            IsNuGet = $true
        }
    )
    
    foreach ($dep in $dependencies) {
        Write-Log "Installing $($dep.Name)..." "Cyan"
        $installed = $false
        
        foreach ($url in $dep.Urls) {
            if ($installed) { break }
            
            try {
                Write-Log "Trying URL: $url" "White"
                
                if ($dep.IsNuGet) {
                    # Handle NuGet/zip packages
                    $zipPath = "$env:TEMP\$($dep.File)_$(Get-Random).zip"
                    $extractPath = "$env:TEMP\$($dep.File)_Extract_$(Get-Random)"
                    
                    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -TimeoutSec 30
                    
                    if (Test-Path $zipPath) {
                        # Extract the NuGet package
                        try {
                            Add-Type -AssemblyName System.IO.Compression.FileSystem
                            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)
                        } catch {
                            # Fallback to Expand-Archive
                            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
                        }
                        
                        # Find and install APPX files
                        $appxFiles = Get-ChildItem -Path $extractPath -Recurse -Filter "*.appx" | Where-Object { 
                            $_.Name -like "*x64*" -or $_.Name -like "*neutral*" -or $_.Name -like "*any*"
                        }
                        
                        if ($appxFiles.Count -eq 0) {
                            # Try looking for MSIX files instead
                            $appxFiles = Get-ChildItem -Path $extractPath -Recurse -Filter "*.msix" | Where-Object { 
                                $_.Name -like "*x64*" -or $_.Name -like "*neutral*" -or $_.Name -like "*any*"
                            }
                        }
                        
                        foreach ($appxFile in $appxFiles) {
                            try {
                                Write-Log "Installing: $($appxFile.Name)" "White"
                                Add-AppxPackage -Path $appxFile.FullName -ErrorAction Stop
                                Write-Log "Successfully installed $($appxFile.Name)" "Green"
                                $installed = $true
                            } catch {
                                Write-Log "Failed to install $($appxFile.Name): $($_.Exception.Message)" "Yellow"
                            }
                        }
                        
                        # Cleanup
                        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    
                } else {
                    # Handle direct APPX downloads
                    $filePath = "$env:TEMP\$($dep.File)_$(Get-Random).appx"
                    
                    Invoke-WebRequest -Uri $url -OutFile $filePath -UseBasicParsing -TimeoutSec 30
                    
                    if (Test-Path $filePath) {
                        Add-AppxPackage -Path $filePath -ErrorAction Stop
                        Write-Log "Successfully installed $($dep.Name)" "Green"
                        $installed = $true
                        Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                    }
                }
                
            } catch {
                Write-Log "Failed with URL $url`: $($_.Exception.Message)" "Yellow"
                # Clean up any partial downloads
                Remove-Item "$env:TEMP\$($dep.File)*" -Force -ErrorAction SilentlyContinue
            }
        }
        
        if (-not $installed) {
            Write-Log "Failed to install $($dep.Name) from any source" "Red"
        }
    }
    
    # Try alternative: Install UI.Xaml via direct Microsoft CDN
    try {
        Write-Log "Trying Microsoft CDN for UI.Xaml..." "Cyan"
        $uiXamlCdnUrl = "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/windowsdesktop-runtime-6.0.25-win-x64.exe"
        # This is just an example - actual CDN URLs change frequently
        Write-Log "Microsoft CDN method not implemented - would need current URLs" "Yellow"
    } catch {
        Write-Log "Microsoft CDN method failed: $($_.Exception.Message)" "Yellow"
    }
}

function Install-WingetMethod1 {
    Write-Log "Method 1: Microsoft Store direct download" "Cyan"
    try {
        $urls = @(
            "https://aka.ms/getwinget",
            "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle",
            "https://store.rg-adguard.net/api/GetFiles?productId=9NBLGGH4NNS1&cat=1&format=json"
        )
        
        foreach ($url in $urls) {
            try {
                Write-Log "Trying URL: $url" "White"
                $filePath = "$env:TEMP\AppInstaller_$(Get-Random).msixbundle"
                
                if ($url -like "*rg-adguard*") {
                    # This is a complex API call, skip for now
                    continue
                }
                
                Invoke-WebRequest -Uri $url -OutFile $filePath -UseBasicParsing
                
                if (Test-Path $filePath) {
                    Add-AppxPackage -Path $filePath -ErrorAction Stop
                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                    Write-Log "Method 1 succeeded with URL: $url" "Green"
                    return $true
                }
            } catch {
                Write-Log "Failed with URL $url`: $($_.Exception.Message)" "Yellow"
                Remove-Item $filePath -Force -ErrorAction SilentlyContinue
            }
        }
        return $false
    } catch {
        Write-Log "Method 1 failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Install-WingetMethod2 {
    Write-Log "Method 2: GitHub releases with dependency installation" "Cyan"
    try {
        # First install dependencies
        Install-RequiredDependencies
        
        # Then try winget installation
        $releases = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $downloadUrl = ($releases.assets | Where-Object { $_.name -like "*.msixbundle" -and $_.name -like "*DesktopAppInstaller*" }).browser_download_url
        
        if (-not $downloadUrl) {
            throw "Could not find suitable msixbundle"
        }
        
        $filePath = "$env:TEMP\winget_$(Get-Random).msixbundle"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $filePath -UseBasicParsing
        
        Add-AppxPackage -Path $filePath -ErrorAction Stop
        Remove-Item $filePath -Force -ErrorAction SilentlyContinue
        
        Write-Log "Method 2 succeeded" "Green"
        return $true
        
    } catch {
        Write-Log "Method 2 failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Install-WingetMethod3 {
    Write-Log "Method 3: Chocolatey bootstrap" "Cyan"
    try {
        # Install chocolatey first if not present (fully automated)
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Log "Installing Chocolatey..." "Yellow"
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            
            # Download and install Chocolatey with automatic yes to all prompts
            $env:ChocolateyInstall = "$env:ProgramData\chocolatey"
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')) 2>$null
            
            # Refresh PATH
            $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        }
        
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Log "Installing WinGet via Chocolatey..." "Yellow"
            
            # Set chocolatey to auto-confirm everything
            & choco feature enable -n allowGlobalConfirmation 2>$null
            & choco install winget --yes --force --no-progress 2>$null
            
            # Refresh environment
            $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            
            Start-Sleep 5
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-Log "Method 3 succeeded" "Green"
                return $true
            }
        }
        
        return $false
        
    } catch {
        Write-Log "Method 3 failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Install-WingetMethod4 {
    Write-Log "Method 4: Windows Package Manager from Windows Features" "Cyan"
    try {
        # Try to enable Windows Package Manager via DISM
        $dismResult = & dism /online /get-capabilities | Select-String "PackageManagement"
        
        if ($dismResult) {
            Write-Log "Attempting to enable Package Management capability..." "Yellow"
            & dism /online /add-capability /capabilityname:PackageManagement.DesktopAppInstaller~~~~0.0.1.0 /quiet
            Start-Sleep 5
            
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-Log "Method 4 succeeded" "Green"
                return $true
            }
        }
        
        return $false
        
    } catch {
        Write-Log "Method 4 failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Main execution
Write-Log "=== WinGet Installation Script Started ===" "Cyan"
Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" "White"
Write-Log "Windows Version: $([System.Environment]::OSVersion.VersionString)" "White"
Write-Log "User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" "White"
Write-Log "Admin: $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))" "White"

# Check if WinGet already exists
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Log "WinGet is already installed!" "Green"
    try {
        $version = winget --version
        Write-Log "Version: $version" "Green"
    } catch {
        Write-Log "WinGet command exists but may not be working properly" "Yellow"
        if (-not $Force) {
            Write-Log "Use -Force to reinstall" "Yellow"
            exit 0
        }
    }
    if (-not $Force) {
        exit 0
    }
}

# Check internet connection
if (-not (Test-InternetConnection)) {
    Write-Log "No internet connection detected. Cannot proceed." "Red"
    exit 1
}

Write-Log "Starting WinGet installation process..." "Yellow"

# Kill any conflicting processes
Write-Log "Stopping conflicting processes..." "Yellow"
$processes = @("winget", "AppInstaller", "DesktopAppInstaller", "WindowsPackageManagerServer")
foreach ($proc in $processes) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep 2

function Install-WingetMethod5 {
    Write-Log "Method 5: Older WinGet version with fewer dependencies" "Cyan"
    try {
        # Try older versions that have fewer dependency requirements
        $olderVersions = @(
            "https://github.com/microsoft/winget-cli/releases/download/v1.4.11071/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle",
            "https://github.com/microsoft/winget-cli/releases/download/v1.3.2691/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle",
            "https://github.com/microsoft/winget-cli/releases/download/v1.2.10271/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        )
        
        foreach ($url in $olderVersions) {
            try {
                Write-Log "Trying older version: $url" "White"
                $filePath = "$env:TEMP\winget_old_$(Get-Random).msixbundle"
                
                Invoke-WebRequest -Uri $url -OutFile $filePath -UseBasicParsing -TimeoutSec 30
                
                if (Test-Path $filePath) {
                    # Try to install without dependencies first
                    Add-AppxPackage -Path $filePath -ErrorAction Stop
                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                    
                    Start-Sleep 3
                    if (Get-Command winget -ErrorAction SilentlyContinue) {
                        Write-Log "Method 5 succeeded with older version" "Green"
                        return $true
                    }
                }
                
            } catch {
                Write-Log "Failed with older version $url`: $($_.Exception.Message)" "Yellow"
                Remove-Item $filePath -Force -ErrorAction SilentlyContinue
            }
        }
        
        return $false
        
    } catch {
        Write-Log "Method 5 failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

# Try installation methods in order
$methods = @(
    { Install-WingetMethod1 },
    { Install-WingetMethod2 },
    { Install-WingetMethod5 },  # Try older version before Chocolatey
    { Install-WingetMethod3 },
    { Install-WingetMethod4 }
)

$success = $false
for ($i = 0; $i -lt $methods.Count; $i++) {
    Write-Log "=== Attempting Method $($i + 1) ===" "Cyan"
    
    try {
        if (& $methods[$i]) {
            $success = $true
            break
        }
    } catch {
        Write-Log "Method $($i + 1) threw exception: $($_.Exception.Message)" "Red"
    }
    
    Start-Sleep 3
}

# Final verification
Start-Sleep 5
$env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

$attempts = 0
$maxAttempts = 10
while ($attempts -lt $maxAttempts) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            $version = winget --version
            Write-Log "SUCCESS: WinGet installed successfully!" "Green"
            Write-Log "Version: $version" "Green"
            Write-Log "Installation completed in method $($i + 1)" "Green"
            exit 0
        } catch {
            Write-Log "WinGet command found but not responding correctly" "Yellow"
        }
    }
    
    $attempts++
    Write-Log "Waiting for WinGet to become available... ($attempts/$maxAttempts)" "Yellow"
    Start-Sleep 2
}

# If we get here, installation failed
Write-Log "FAILED: All installation methods failed" "Red"
Write-Log "Manual steps required:" "Yellow"
Write-Log "1. Open Microsoft Store and search for 'App Installer'" "White"
Write-Log "2. Install or update App Installer" "White"  
Write-Log "3. Reboot the system" "White"
Write-Log "4. Check Windows Update for pending updates" "White"

Write-Log "=== Installation log saved to: $env:TEMP\winget-install.log ===" "Cyan"
exit 1
