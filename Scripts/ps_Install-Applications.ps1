<#PSScriptInfo

.VERSION 1.2.1

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows WinGet Applications Installation Deployment OOBE

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.2.1] - Merged OOBE functionality, added PowerShell 7 support, architecture detection, default terminal configuration, and enhanced installation capabilities.
[Version 1.1.0] - Added WhatIf support, centralized admin validation, and standardized output.
[Version 1.0.2] - Improved error handling and logging.
[Version 1.0.1] - Added 7zip to default applications.
[Version 1.0.0] - Initial Release. Installs applications using WinGet package manager.
#>

<#
.SYNOPSIS
    Installs specified applications using WinGet package manager with optional OOBE components.

.DESCRIPTION
    This script automates the installation of multiple applications using WinGet.
    It includes error handling, progress tracking, detailed logging, and optional OOBE components:
    - NuGet Package Provider installation
    - Visual C++ Redistributable installation
    - PowerShell 7 installation with architecture detection (ARM64/x64)
    - WinGet applications with PowerShell 7 system context support
    
    The script can install applications silently and accepts all required agreements automatically.

.PARAMETER Applications
    Array of application IDs to install. Uses default list if not specified.

.PARAMETER LogPath
    Path for installation log file. Creates log in temp directory by default.

.PARAMETER Force
    Forces installation even if application is already installed.

.PARAMETER InstallNuGet
    Installs NuGet package provider if not present.

.PARAMETER InstallVCRedist
    Installs Visual C++ Redistributable (architecture-aware).

.PARAMETER InstallPowerShell7
    Installs PowerShell 7 (architecture-aware).

.PARAMETER SetPS7AsDefault
    Sets PowerShell 7 as the default terminal for Windows Terminal and console host.

.PARAMETER UsePowerShell7
    Uses PowerShell 7 for WinGet installations (recommended for system context).

.PARAMETER VCRedistPath
    Path to Visual C++ Redistributable installer. Required if InstallVCRedist is specified.

.PARAMETER PowerShell7MSIPath
    Path to PowerShell 7 MSI installer. Auto-detects architecture if not specified.

.EXAMPLE
    .\ps_Install-Applications.ps1
    
    Installs default applications using standard WinGet.

.EXAMPLE
    .\ps_Install-Applications.ps1 -Applications @("7zip.7zip", "Mozilla.Firefox") -InstallNuGet
    
    Installs specific applications and ensures NuGet is installed.

.EXAMPLE
    .\ps_Install-Applications.ps1 -InstallVCRedist -VCRedistPath ".\vc_redist.x64.exe" -InstallPowerShell7 -SetPS7AsDefault -UsePowerShell7
    
    Full OOBE-style installation with prerequisites, installs PowerShell 7, sets it as default terminal, and uses it for WinGet.

.OUTPUTS
    Installation log file with detailed results.

.NOTES
    Version      : 1.2.1
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    
    Requires WinGet to be installed and configured.
    For OOBE scenarios, use with InstallPowerShell7 and UsePowerShell7 parameters.
    
    Default applications:
    - Microsoft.VCRedist.2015+.x64 (Visual C++ Redistributable)
    - Microsoft.Office (Microsoft Office Suite)
    - 7zip.7zip

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Applications = @(
        "Microsoft.VCRedist.2015+.x64",
        "Microsoft.Office",
        "7zip.7zip"
    ),
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\DenkoICT-Applications-$(Get-Date -Format 'yyyyMMdd-HHmmss').log",
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [switch]$InstallNuGet,
    
    [Parameter(Mandatory = $false)]
    [switch]$InstallVCRedist,
    
    [Parameter(Mandatory = $false)]
    [switch]$InstallPowerShell7,
    
    [Parameter(Mandatory = $false)]
    [switch]$UsePowerShell7,
    
    [Parameter(Mandatory = $false)]
    [switch]$SetPS7AsDefault,
    
    [Parameter(Mandatory = $false)]
    [ValidateNotNull()]
    [System.IO.FileInfo]$VCRedistPath,
    
    [Parameter(Mandatory = $false)]
    [string]$PowerShell7MSIPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Architecture detection
$script:SystemArch = $env:PROCESSOR_ARCHITECTURE
$script:IsARM64 = $SystemArch -eq "ARM64"

# Common module check
$commonModule = Join-Path -Path $PSScriptRoot -ChildPath 'ps_Invoke-AdminToolkit.ps1'
if (Test-Path -Path $commonModule) {
    . $commonModule
    $script:CommonModuleAvailable = $true
} else {
    $script:CommonModuleAvailable = $false
    Write-Warning "Common module not found at $commonModule. Admin validation will use fallback method."
}

# Initialize logging
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $LogPath -Value $logMessage -Force
    
    # Write to console with color
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        default { 'Cyan' }
    }
    
    Write-Host $logMessage -ForegroundColor $color
}

# Admin rights validation
function Test-AdminRights {
    if ($script:CommonModuleAvailable) {
        Assert-AdminRights
    } else {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw "This script requires administrator privileges. Please run as administrator."
        }
    }
}

# Get MSI Properties (for PowerShell 7 installation)
function Get-MSIProperties {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$MSI
    )
    
    try {
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $database = $windowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $windowsInstaller, @($MSI, 0))
        
        $query = "SELECT Property, Value FROM Property"
        $propView = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, ($query))
        $propView.GetType().InvokeMember("Execute", "InvokeMethod", $null, $propView, $null) | Out-Null
        
        $msiProps = @()
        $propRecord = $propView.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $propView, $null)
        
        while ($null -ne $propRecord) {
            $property = $propRecord.GetType().InvokeMember("StringData", "GetProperty", $null, $propRecord, 1)
            $value = $propRecord.GetType().InvokeMember("StringData", "GetProperty", $null, $propRecord, 2)
            
            $msiProps += [PSCustomObject]@{
                MSIProperty = $property
                Value = $value
            }
            
            $propRecord = $propView.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $propView, $null)
        }
        
        # Clean up COM objects
        $propView.GetType().InvokeMember("Close", "InvokeMethod", $null, $propView, $null) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($windowsInstaller) | Out-Null
        
        Write-Log "Successfully extracted MSI properties from: $MSI" -Level 'Info'
        return $msiProps
    } catch {
        Write-Log "Failed to extract MSI properties: $($_.Exception.Message)" -Level 'Error'
        throw
    }
}

# Install NuGet provider
function Install-NuGetProvider {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param()
    try {
        Write-Log "Checking NuGet package provider..." -Level 'Info'
        
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        
        if (-not $nugetProvider) {
            if ($PSCmdlet.ShouldProcess("NuGet Package Provider", "Install")) {
                Install-PackageProvider -Name NuGet -MinimumVersion 3.0.0.1 -Force -Scope AllUsers
                Write-Log "NuGet package provider installed successfully" -Level 'Success'
            }
        } else {
            Write-Log "NuGet package provider already installed (version: $($nugetProvider.Version))" -Level 'Info'
        }
    } catch {
        Write-Log "Failed to install NuGet package provider: $($_.Exception.Message)" -Level 'Error'
        throw
    }
}

# Install Visual C++ Redistributable
function Install-VCRedistributable {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$InstallerPath
    )

    try {
        $arguments = "/install /quiet /norestart"

        Write-Log "Installing Visual C++ Redistributable from: $InstallerPath" -Level 'Info'
        
        if ($PSCmdlet.ShouldProcess($InstallerPath, "Install Visual C++ Redistributable")) {
            $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
            
            switch ($process.ExitCode) {
                0 { 
                    Write-Log "Visual C++ Redistributable installed successfully" -Level 'Success'
                    return $true
                }
                3010 { 
                    Write-Log "Installation successful but reboot required" -Level 'Warning'
                    return $true
                }
                5100 { 
                    Write-Log "A newer version is already installed" -Level 'Info'
                    return $true
                }
                default {
                    Write-Log "Installation failed with exit code: $($process.ExitCode)" -Level 'Error'
                    return $false
                }
            }
        }
    } catch {
        Write-Log "Failed to start installation process: $($_.Exception.Message)" -Level 'Error'
        return $false
    }
}

# Set PowerShell 7 as default terminal
function Set-PowerShell7AsDefault {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param()
    
    try {
        Write-Log "Setting PowerShell 7 as default terminal..." -Level 'Info'

        if (-not $PSCmdlet.ShouldProcess("PowerShell 7 default terminal configuration", "Apply registry and terminal settings")) {
            if ($WhatIfPreference) {
                Write-Log "WhatIf: Would configure PowerShell 7 as the default terminal" -Level 'Warning'
            }
            return $true
        }
        
        # Check if PowerShell 7 is installed
        $pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
        if (-not (Test-Path $pwshPath)) {
            Write-Log "PowerShell 7 not found at expected location" -Level 'Warning'
            return $false
        }
        
        # Set Windows Terminal default profile if Windows Terminal is installed
        $wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        if (Test-Path $wtSettingsPath) {
            try {
                $settings = Get-Content $wtSettingsPath -Raw | ConvertFrom-Json
                
                # Find PowerShell 7 profile GUID
                $ps7Profile = $settings.profiles.list | Where-Object { $_.name -like "*PowerShell*" -and $_.commandline -like "*pwsh.exe*" }
                
                if ($ps7Profile) {
                    $settings.defaultProfile = $ps7Profile.guid
                    $settings | ConvertTo-Json -Depth 10 | Set-Content $wtSettingsPath -Force
                    Write-Log "Windows Terminal default profile set to PowerShell 7" -Level 'Success'
                }
            } catch {
                Write-Log "Failed to modify Windows Terminal settings: $_" -Level 'Warning'
            }
        }
        
        # Set registry keys for console host
        $regPaths = @(
            "HKCU:\Console\%%Startup",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Terminal"
        )
        
        foreach ($path in $regPaths) {
            try {
                if (-not (Test-Path $path)) {
                    New-Item -Path $path -Force | Out-Null
                }
            } catch {
                Write-Log "Failed to create registry path: $path" -Level 'Warning'
            }
        }
        
        # Set default shell executable in registry
        try {
            Set-ItemProperty -Path "HKCU:\Console\%%Startup" -Name "DelegationConsole" -Value "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKCU:\Console\%%Startup" -Name "DelegationTerminal" -Value "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" -ErrorAction SilentlyContinue
            
            # Set PowerShell 7 as default for Windows Terminal
            New-Item -Path "HKCU:\SOFTWARE\Classes\Directory\shell\pwsh7" -Force | Out-Null
            Set-ItemProperty -Path "HKCU:\SOFTWARE\Classes\Directory\shell\pwsh7" -Name "(Default)" -Value "Open PowerShell 7 here"
            New-Item -Path "HKCU:\SOFTWARE\Classes\Directory\shell\pwsh7\command" -Force | Out-Null
            Set-ItemProperty -Path "HKCU:\SOFTWARE\Classes\Directory\shell\pwsh7\command" -Name "(Default)" -Value "`"$pwshPath`" -NoExit -Command Set-Location '%V'"
            
            # Set for background context menu
            New-Item -Path "HKCU:\SOFTWARE\Classes\Directory\Background\shell\pwsh7" -Force | Out-Null
            Set-ItemProperty -Path "HKCU:\SOFTWARE\Classes\Directory\Background\shell\pwsh7" -Name "(Default)" -Value "Open PowerShell 7 here"
            New-Item -Path "HKCU:\SOFTWARE\Classes\Directory\Background\shell\pwsh7\command" -Force | Out-Null
            Set-ItemProperty -Path "HKCU:\SOFTWARE\Classes\Directory\Background\shell\pwsh7\command" -Name "(Default)" -Value "`"$pwshPath`" -NoExit -Command Set-Location '%V'"
            
            Write-Log "Registry settings configured for PowerShell 7 as default" -Level 'Success'
        } catch {
            Write-Log "Failed to set registry values: $_" -Level 'Warning'
            return $false
        }
        
        # Update PATHEXT to include .PS1 files if not present
        $pathExt = [Environment]::GetEnvironmentVariable("PATHEXT", "Machine")
        if ($pathExt -notlike "*.PS1*") {
            [Environment]::SetEnvironmentVariable("PATHEXT", "$pathExt;.PS1", "Machine")
            Write-Log "Added .PS1 to PATHEXT environment variable" -Level 'Info'
        }
        
        return $true
        
    } catch {
        Write-Log "Failed to set PowerShell 7 as default: $($_.Exception.Message)" -Level 'Error'
        return $false
    }
}

# Install PowerShell 7
function Install-PowerShell7MSI {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$MSIPath
    )

    try {
        Write-Log "Extracting MSI properties..." -Level 'Info'
        $msiProperties = Get-MSIProperties -MSI $MSIPath
        
        $ProductVersion = $msiProperties | Where-Object MSIProperty -eq "ProductVersion" | Select-Object -ExpandProperty Value  
        $ProductName = $msiProperties | Where-Object MSIProperty -eq "ProductName" | Select-Object -ExpandProperty Value
        
        Write-Log "MSI Product: $ProductName v$ProductVersion" -Level 'Info'
    } catch {
        Write-Log "Getting MSI properties failed: $($_.Exception.Message)" -Level 'Error'
        throw
    }
    
    if ($PSCmdlet.ShouldProcess("$ProductName v$ProductVersion", "Install PowerShell 7")) {
        try {
            $logFile = Join-Path -Path (Split-Path $LogPath -Parent) -ChildPath "PowerShellMSI.log"
            $msiArguments = @(
                "/i", "`"$MSIPath`""
                "/qn"
                "ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1"
                "ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1" 
                "ENABLE_PSREMOTING=1"
                "REGISTER_MANIFEST=1"
                "USE_MU=1"
                "ENABLE_MU=1"
                "ADD_PATH=1"
                "/l*v", "`"$logFile`""
            )
            
            Write-Log "Starting MSI installation for $ProductName version $ProductVersion..." -Level 'Info'
            $result = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -Wait -PassThru -NoNewWindow
            
            if ($result.ExitCode -eq 0 -or $result.ExitCode -eq 1707) {
                Write-Log "$ProductName version $ProductVersion installed successfully" -Level 'Success'
                return $true
            } elseif ($result.ExitCode -eq 3010 -or $result.ExitCode -eq 1641) {
                Write-Log "$ProductName version $ProductVersion installed successfully but requires reboot" -Level 'Warning'
                return $true
            } else {
                Write-Log "MSI installation failed with exit code: $($result.ExitCode)" -Level 'Error'
                return $false
            }
        } catch {
            Write-Log "Failed to run MSI installation: $($_.Exception.Message)" -Level 'Error'
            return $false
        }
    }
}

# Check if WinGet is available
function Test-WinGetAvailable {
    try {
        $wingetExists = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $wingetExists) {
            Write-Log "WinGet command not found." -Level 'Error'
            return $false
        }
        
        $wingetVersion = & winget --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "WinGet version: $wingetVersion" -Level 'Info'
            return $true
        } else {
            Write-Log "WinGet command exists but returned error code: $LASTEXITCODE" -Level 'Error'
            return $false
        }
    } catch {
        Write-Log "WinGet is not available: $_" -Level 'Error'
        return $false
    }
}

# Install application using WinGet
function Install-Application {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        
        [Parameter(Mandatory = $false)]
        [switch]$UsePS7
    )
    
    Write-Log "Installing $AppId..." -Level 'Info'
    
    if ($UsePS7 -and (Test-Path "C:\Program Files\PowerShell\7\pwsh.exe")) {
        # Use PowerShell 7 for system context installations
        try {
            $PS7Proc = Start-Process -FilePath "C:\Program Files\PowerShell\7\pwsh.exe" `
                -ArgumentList "-MTA -Command `"Install-WinGetPackage -Id '$AppId' -Mode Silent -Scope SystemOrUnknown -ErrorAction Continue`"" `
                -Wait -NoNewWindow -PassThru
            
            if ($PS7Proc.ExitCode -eq 0) {
                Write-Log "$AppId installed successfully via PowerShell 7." -Level 'Success'
                return $true
            } else {
                Write-Log "Failed to install $AppId via PowerShell 7. Exit code: $($PS7Proc.ExitCode)" -Level 'Error'
                return $false
            }
        } catch {
            Write-Log "Exception installing $AppId via PowerShell 7: $_" -Level 'Error'
            return $false
        }
    } else {
        # Use standard WinGet
        try {
            $arguments = @(
                "install"
                "--id", $AppId
                "--accept-source-agreements"
                "--accept-package-agreements"
                "--exact"
                "--silent"
            )
            
            if ($Force) {
                $arguments += "--force"
            }
            
            $process = Start-Process -FilePath "winget" -ArgumentList $arguments -Wait -PassThru -NoNewWindow
            
            switch ($process.ExitCode) {
                0 { 
                    Write-Log "$AppId installed successfully." -Level 'Success'
                    return $true
                }
                -1978335189 { 
                    Write-Log "$AppId is already installed." -Level 'Warning'
                    return $true
                }
                -1978335153 { 
                    Write-Log "$AppId is up to date." -Level 'Info'
                    return $true
                }
                default {
                    Write-Log "Failed to install $AppId. Exit code: $($process.ExitCode)" -Level 'Error'
                    return $false
                }
            }
        } catch {
            Write-Log "Exception installing $($AppId): $_" -Level 'Error'
            return $false
        }
    }
}

# Main execution
Write-Log "=== Application Installation Started ===" -Level 'Info'
Write-Log "Version: 1.2.1" -Level 'Info'
Write-Log "User: $env:USERNAME" -Level 'Info'
Write-Log "Computer: $env:COMPUTERNAME" -Level 'Info'
Write-Log "Architecture: $SystemArch" -Level 'Info'
Write-Log "Applications to install: $($Applications -join ', ')" -Level 'Info'

# Validate admin rights
Test-AdminRights

# Install NuGet if requested
if ($InstallNuGet) {
    try {
        Install-NuGetProvider
    } catch {
        Write-Log "NuGet installation failed, continuing..." -Level 'Warning'
    }
}

# Install Visual C++ Redistributable if requested
if ($InstallVCRedist) {
    if (-not $VCRedistPath) {
        # Try to find VC Redist in script directory
        $VCRedistPath = if ($IsARM64) {
            Join-Path $PSScriptRoot "vc_redist.arm64.exe"
        } else {
            Join-Path $PSScriptRoot "vc_redist.x64.exe"
        }
    }
    
    if (Test-Path $VCRedistPath) {
        Install-VCRedistributable -InstallerPath $VCRedistPath
    } else {
        Write-Log "Visual C++ Redistributable installer not found at: $VCRedistPath" -Level 'Warning'
    }
}

# Install PowerShell 7 if requested
if ($InstallPowerShell7) {
    if (-not $PowerShell7MSIPath) {
        # Try to find PS7 MSI in script directory based on architecture
        $PowerShell7MSIPath = if ($IsARM64) {
            Join-Path $PSScriptRoot "PowerShell-7.*-win-arm64.msi" | Get-Item -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        } else {
            Join-Path $PSScriptRoot "PowerShell-7.*-win-x64.msi" | Get-Item -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        }
    }
    
    if ($PowerShell7MSIPath -and (Test-Path $PowerShell7MSIPath)) {
        $ps7Installed = Install-PowerShell7MSI -MSIPath $PowerShell7MSIPath
        
        # Set as default if requested and installation succeeded
        if ($ps7Installed -and $SetPS7AsDefault) {
            $setPs7Params = @{}
            if ($WhatIfPreference) { $setPs7Params['WhatIf'] = $true }
            if ($PSBoundParameters.ContainsKey('Confirm')) { $setPs7Params['Confirm'] = $PSBoundParameters['Confirm'] }
            Set-PowerShell7AsDefault @setPs7Params
        }
    } else {
        Write-Log "PowerShell 7 MSI not found. Specify path with -PowerShell7MSIPath parameter." -Level 'Warning'
    }
} elseif ($SetPS7AsDefault) {
    # If only setting as default without installation
    $setPs7Params = @{}
    if ($WhatIfPreference) { $setPs7Params['WhatIf'] = $true }
    if ($PSBoundParameters.ContainsKey('Confirm')) { $setPs7Params['Confirm'] = $PSBoundParameters['Confirm'] }
    Set-PowerShell7AsDefault @setPs7Params
}

# Check WinGet availability
if (-not (Test-WinGetAvailable)) {
    Write-Log "WinGet is not installed. Please install WinGet first." -Level 'Error'
    exit 1
}

# Prepare PowerShell 7 module if needed
if ($UsePowerShell7) {
    if (Test-Path "C:\Program Files\PowerShell\7\pwsh.exe") {
        Write-Log "Preparing PowerShell 7 for WinGet operations..." -Level 'Info'
        
        if ($PSCmdlet.ShouldProcess("Microsoft.WinGet.Client", "Install PS7 Module")) {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module -Name Microsoft.WinGet.Client -Force -Scope AllUsers -Repository PSGallery -ErrorAction SilentlyContinue
        }
    } else {
        Write-Log "PowerShell 7 not found. Falling back to standard WinGet." -Level 'Warning'
        $UsePowerShell7 = $false
    }
}

# Adjust applications list based on architecture
if ($IsARM64) {
    # Replace x64 specific apps with ARM64 versions
    $Applications = $Applications | ForEach-Object {
        if ($_ -like "*x64*") {
            $_.Replace("x64", "arm64")
        } else {
            $_
        }
    }
    Write-Log "Adjusted applications for ARM64 architecture" -Level 'Info'
}

$confirmParameterSupplied = $PSBoundParameters.ContainsKey('Confirm')
$originalConfirmPreference = $ConfirmPreference

if (-not $confirmParameterSupplied) {
    $ConfirmPreference = 'None'
}

try {
    $shouldInstall = $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Install applications via WinGet')
} finally {
    if (-not $confirmParameterSupplied) {
        $ConfirmPreference = $originalConfirmPreference
    }
}

if (-not $shouldInstall) {
    Write-Log 'WhatIf: Simulation mode - no applications will be installed.' -Level 'Warning'
}

# Install applications
$successCount = 0
$failCount = 0

foreach ($app in $Applications) {
    if (-not $shouldInstall) {
        Write-Log "WhatIf: Would install $app" -Level 'Warning'
        continue
    }

    if (Install-Application -AppId $app -UsePS7:$UsePowerShell7) {
        $successCount++
    } else {
        $failCount++
    }
}

# Summary
Write-Log "=== Installation Summary ===" -Level 'Info'
Write-Log "Total applications: $($Applications.Count)" -Level 'Info'
Write-Log "Successful: $successCount" -Level $(if ($successCount -gt 0) { 'Success' } else { 'Info' })
Write-Log "Failed: $failCount" -Level $(if ($failCount -gt 0) { 'Error' } else { 'Info' })
Write-Log "Log file: $LogPath" -Level 'Info'

# Set exit code
$exitCode = if ($failCount -gt 0) { 1 } else { 0 }
exit $exitCode
