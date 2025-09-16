# Run as admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Script must be run as Administrator."
    exit 1
}

# If winget already present just update sources
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "winget is installed. Updating sources..."
    winget source update
    exit 0
}

$owner = "microsoft"
$repo  = "winget-cli"
$api   = "https://api.github.com/repos/$owner/$repo/releases/latest"
$headers = @{ "User-Agent" = "PowerShell" }

try {
    $release = Invoke-RestMethod -Uri $api -Headers $headers -ErrorAction Stop
} catch {
    Write-Error "Unable to query GitHub releases: $_"
    exit 1
}

# Select assets that we need (names used by the winget releases)
$assets = $release.assets | Where-Object { $_.name -match "Microsoft.UI.Xaml|Microsoft.VCLibs|Microsoft.DesktopAppInstaller" }

if (-not $assets) {
    Write-Warning "No matching assets found in the latest release. You may need to provide offline packages or check network access."
    exit 1
}

$tempDir = Join-Path $env:TEMP "winget_install"
New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

foreach ($asset in $assets) {
    $outFile = Join-Path $tempDir $asset.name
    Write-Host "Downloading $($asset.name) ..."
    try {
        Start-BitsTransfer -Source $asset.browser_download_url -Destination $outFile -DisplayName "Downloading $($asset.name)" -Priority High -ErrorAction Stop
    } catch {
        Write-Warning "Failed to download $($asset.name): $_"
        continue
    }

    Write-Host "Installing $($asset.name) ..."
    try {
        Add-AppxPackage -Path $outFile -ForceApplicationShutdown -DisableDevelopmentMode -ErrorAction Stop
    } catch {
        Write-Warning "Failed to install $($asset.name): $_"
    }
}

# Final step: ensure winget is available and update sources
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "winget installed. Updating sources..."
    winget source update
} else {
    Write-Warning "winget was not installed successfully. Inspect logs and the downloaded files in $tempDir"
}