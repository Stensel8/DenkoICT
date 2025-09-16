
# =====================
# PowerShell 5.1 Section
# =====================
if ($PSVersionTable.PSVersion.Major -lt 7) {
    # winget installer (online)
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) { Write-Error 'Run as Administrator'; exit 1 }
    if (Get-Command winget -ErrorAction SilentlyContinue) { Write-Host 'winget present — updating sources'; winget source update; exit 0 }

    $api = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    try {
        $assets = (Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent'='PowerShell' } -ErrorAction Stop).assets
    } catch {
        Write-Error "Failed to query GitHub: $_"
        exit 1
    }
    $pkgAssets = $assets | Where-Object { $_.name -match 'Microsoft.UI.Xaml|Microsoft.VCLibs|Microsoft.DesktopAppInstaller' }
    if (-not $pkgAssets) { Write-Warning 'No release assets found'; exit 1 }

    $tmp = Join-Path $env:TEMP 'winget_install'; New-Item -Path $tmp -ItemType Directory -Force | Out-Null
    $pkgAssets | ForEach-Object {
        $dest = Join-Path $tmp $_.name
        Write-Host "DL: $_.name"
        $dlSuccess = $false
        try {
            Start-BitsTransfer -Source $_.browser_download_url -Destination $dest -DisplayName "DL $_.name" -Priority High -ErrorAction Stop
            $dlSuccess = $true
        } catch {
            Write-Warning "DL failed: $_"
        }
        if (-not $dlSuccess) { return }
        if (-not (Test-Path -LiteralPath $dest)) { Write-Warning "Missing file, skipping: $dest"; return }
        $path = $null
        try {
            $path = (Resolve-Path -LiteralPath $dest -ErrorAction Stop).ProviderPath
        } catch {
            Write-Warning "Bad path: $_"
            return
        }
        try {
            Add-AppxPackage -Path $path -ForceApplicationShutdown -DisableDevelopmentMode -ErrorAction Stop
            Write-Host "Installed: $($_.name)"
        } catch {
            Write-Warning "Install failed: $_"
        }
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) { Write-Host 'winget installed — updating sources'; winget source update } else { Write-Warning "winget not installed. See $tmp" }
}

# =====================
# PowerShell 7+ Section
# =====================
if ($PSVersionTable.PSVersion.Major -ge 7) {
    # winget installer (online)
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) { Write-Error 'Run as Administrator'; exit 1 }
    if (Get-Command winget -ErrorAction SilentlyContinue) { Write-Host 'winget present — updating sources'; winget source update; exit 0 }

    $api = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    $assets = try { (Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent'='PowerShell' } -ErrorAction Stop).assets } catch { Write-Error "Failed to query GitHub: $_"; exit 1 }
    $pkgAssets = $assets | Where-Object { $_.name -match 'Microsoft.UI.Xaml|Microsoft.VCLibs|Microsoft.DesktopAppInstaller' }
    if (-not $pkgAssets) { Write-Warning 'No release assets found'; exit 1 }

    $tmp = Join-Path $env:TEMP 'winget_install'; New-Item -Path $tmp -ItemType Directory -Force | Out-Null
    $pkgAssets | ForEach-Object {
        $dest = Join-Path $tmp $_.name
        Write-Host "DL: $_.name"
        if (-not (Try { Start-BitsTransfer -Source $_.browser_download_url -Destination $dest -DisplayName "DL $_.name" -Priority High -ErrorAction Stop; $true } Catch { Write-Warning "DL failed: $_"; $false })) { return }
        if (-not (Test-Path -LiteralPath $dest)) { Write-Warning "Missing file, skipping: $dest"; return }
        $path = try { (Resolve-Path -LiteralPath $dest -ErrorAction Stop).ProviderPath } catch { Write-Warning "Bad path: $_"; return }
        Try { Add-AppxPackage -Path $path -ForceApplicationShutdown -DisableDevelopmentMode -ErrorAction Stop; Write-Host "Installed: $($_.name)" } Catch { Write-Warning "Install failed: $_" }
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) { Write-Host 'winget installed — updating sources'; winget source update } else { Write-Warning "winget not installed. See $tmp" }
}
