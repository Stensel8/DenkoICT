

# =====================
# WinGet Online Installer
# =====================

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

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-Error 'Run as Administrator'
    exit 1
}

$winget = Get-WingetPath
if ($winget) {
    Write-Host 'winget present - updating sources'
    & "$winget" source update
    exit 0
}

# Download latest release assets
$api = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
$assets = try { (Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent'='PowerShell' } -ErrorAction Stop).assets } catch { Write-Error "Failed to query GitHub: $_"; exit 1 }
$pkgAssets = $assets | Where-Object { $_.name -match 'Microsoft.UI.Xaml|Microsoft.VCLibs|Microsoft.DesktopAppInstaller' }
if (-not $pkgAssets) { Write-Warning 'No release assets found'; exit 1 }

$tmp = Join-Path $env:TEMP 'winget_install'; New-Item -Path $tmp -ItemType Directory -Force | Out-Null

# Download all assets
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

# Install all packages (try both Add-AppxPackage and Add-AppxProvisionedPackage for OOBE/system context)
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

# Final check
$winget = Get-WingetPath
if ($winget) {
    Write-Host 'winget installed — updating sources'
    & $winget source update
    exit 0
} else {
    Write-Warning "winget not installed. See $tmp"
    exit 1
}
