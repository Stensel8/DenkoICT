#!/usr/bin/env pwsh

# WinGet Installer: online + offline
# Usage:
#  - To update existing winget:   .\ps_InstallWinget.ps1 -UpdateOnly
#  - To install from online GitHub release: .\ps_InstallWinget.ps1 -Mode Online
#  - To install from local folder/files:   .\ps_InstallWinget.ps1 -Mode Offline -OfflinePath C:\path\to\packages

param(
    [ValidateSet('Online','Offline')]
    [string]$Mode = 'Online',
    [string]$OfflinePath = '',
    [switch]$UpdateOnly,
    [switch]$Force
)

function Get-WingetPath {
    $paths = @(
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe",
        "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
    )
    foreach ($p in $paths) {
        $found = Get-ChildItem -Path $p -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) { return "winget" }
    return $null
}

function Test-IsAdministrator {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
        Write-Error 'Run as Administrator'
        exit 1
    }
}

function Update-WingetSources {
    param([string]$WingetExe = 'winget')
    try {
        & "$WingetExe" source update
        Write-Host 'winget sources updated.'
    } catch {
        Write-Warning "Failed to update winget sources: $_"
    }
}

function Install-From-GitHub {
    # Download latest release assets from winget-cli and install packages
    $api = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    $assets = try { (Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent'='PowerShell' } -ErrorAction Stop).assets } catch { Write-Error "Failed to query GitHub: $_"; return $false }
    $pkgAssets = $assets | Where-Object { $_.name -match 'Microsoft.UI.Xaml|Microsoft.VCLibs|Microsoft.DesktopAppInstaller' }
    if (-not $pkgAssets) { Write-Warning 'No release assets found'; return $false }

    $tmp = Join-Path $env:TEMP 'winget_install'; New-Item -Path $tmp -ItemType Directory -Force | Out-Null

    $pkgFiles = @()
    foreach ($asset in $pkgAssets) {
        $dest = Join-Path $tmp $asset.name
        Write-Host "DL: $($asset.name)"
        try {
            Start-BitsTransfer -Source $asset.browser_download_url -Destination $dest -DisplayName "DL $($asset.name)" -Priority High -ErrorAction Stop
            $pkgFiles += $dest
        } catch {
            Write-Warning "DL failed: $_"
        }
    }

    foreach ($file in $pkgFiles) {
        try {
            Add-AppxPackage -Path $file -ForceApplicationShutdown -DisableDevelopmentMode -ErrorAction Stop
            Write-Host "Installed: $file"
        } catch {
            try {
                Add-AppxProvisionedPackage -Online -PackagePath $file -SkipLicense | Out-Null
                Write-Host "Provisioned: $file"
            } catch {
                Write-Warning "Install failed: $file ($_ )"
            }
        }
    }

    return $true
}

function Install-From-Local {
    param([string]$Path)
    if (-not (Test-Path $Path)) { Write-Warning "Offline path not found: $Path"; return $false }

    # If a file was provided, install that single file; if a directory, install all .appx/.msixbundle files
    $pkgFiles = @()
    if ((Get-Item $Path).PSIsContainer) {
        $pkgFiles = Get-ChildItem -Path $Path -Include *.appx,*.msix,*.msixbundle -File -Recurse
    } else {
        $pkgFiles = ,(Get-Item -Path $Path)
    }

    if (-not $pkgFiles -or $pkgFiles.Count -eq 0) { Write-Warning "No package files found in $Path"; return $false }

    foreach ($file in $pkgFiles) {
        $dst = $file.FullName
        Write-Output "Provisioning/installing $dst"
        try {
            Add-AppxProvisionedPackage -Online -PackagePath $dst -SkipLicense -ErrorAction Stop
            Write-Host "Provisioned: $dst"
        } catch {
            try {
                Add-AppxPackage -Path $dst -Register -DisableDevelopmentMode -ErrorAction Stop
                Write-Host "Installed (register): $dst"
            } catch {
                Write-Warning "Failed to provision/install ${dst}: $_"
            }
        }
    }

    return $true
}

# --- Main ---
Test-IsAdministrator

if ($UpdateOnly) {
    $winget = Get-WingetPath
    if ($winget) { Update-WingetSources -WingetExe $winget; exit 0 } else { Write-Warning 'winget not found for update.'; exit 1 }
}

switch ($Mode) {
    'Online' {
        Write-Host 'Mode: Online'
        $winget = Get-WingetPath
        if ($winget -and -not $Force) {
            Write-Host 'winget present - updating sources'
            Update-WingetSources -WingetExe $winget
            exit 0
        }

        $ok = Install-From-GitHub
        if ($ok) {
            $winget = Get-WingetPath
            if ($winget) { Update-WingetSources -WingetExe $winget; exit 0 } else { Write-Warning "winget not installed. See $env:TEMP\winget_install"; exit 1 }
        } else {
            Write-Warning 'Online install failed.'; exit 1
        }
    }
    'Offline' {
        Write-Host 'Mode: Offline'
        if (-not $OfflinePath) { Write-Error 'OfflinePath is required for Offline mode.'; exit 1 }
        $ok = Install-From-Local -Path $OfflinePath
        if ($ok) { $winget = Get-WingetPath; if ($winget) { Update-WingetSources -WingetExe $winget }; exit 0 } else { Write-Warning 'Offline install failed.'; exit 1 }
    }
}
