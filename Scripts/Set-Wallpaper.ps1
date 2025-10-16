<#PSScriptInfo

.VERSION 1.3.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Wallpaper Desktop Theme Customization Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Sets Windows desktop wallpaper to img19.jpg (dark theme).
[Version 1.0.1] - Improved logging. NOTE: some EDRs may block this script.
[Version 1.1.0] - Added WhatIf support, centralized logging, and admin validation.
[Version 1.1.1] - Improved error handling with Win32Exception.
[Version 1.1.2] - Added method verification and improved robustness.
[Version 1.2.0] - Simplified code, added explorer.exe restart.
[Version 1.3.0] - Proper theme notification using broadcast messages, no explorer restart needed.
#>

#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Sets Windows wallpaper and theme efficiently without opening Settings.

.DESCRIPTION
    Applies wallpaper and theme settings via direct registry manipulation and Windows API.
    No Settings app will be opened during execution.

.PARAMETER WallpaperPath
    Path to wallpaper image. Default: Windows 11 dark wallpaper.

.PARAMETER Theme
    Theme preset: 'Dark', 'Light', 'Mixed' (light apps/dark system), 'Inverted' (dark apps/light system)
    Default: 'Dark'

.PARAMETER AppsTheme
    Apps theme override: 'light' or 'dark'

.PARAMETER SystemTheme
    System theme override: 'light' or 'dark'

.EXAMPLE
    .\Set-Wallpaper.ps1
    Sets default dark wallpaper and dark theme.

.EXAMPLE
    .\Set-Wallpaper.ps1 -WallpaperPath "C:\Custom\bg.jpg" -Theme Light
    Sets custom wallpaper with light theme.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Bootstrap initialization using consolidated function
Import-Module (Join-Path $PSScriptRoot 'Utilities\ScriptBootstrap.psm1') -Force -Global
Initialize-DeploymentScript -LogName 'Set-Wallpaper.log' -RequiredModules @('Logging','System') -RequireAdmin

# Define Windows API
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.ComponentModel;

public class WinAPI {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    public static void SetWallpaper(string path) {
        if (!SystemParametersInfo(20, 0, path, 0x01 | 0x02))
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    public static void BroadcastThemeChange() {
        IntPtr HWND_BROADCAST = new IntPtr(0xFFFF);
        IntPtr result;

        // Notify ImmersiveColorSet change
        SendMessageTimeout(HWND_BROADCAST, 0x001A, IntPtr.Zero, "ImmersiveColorSet", 2, 5000, out result);

        // Send theme changed message
        PostMessage(HWND_BROADCAST, 0x031A, IntPtr.Zero, IntPtr.Zero);
    }
}
'@ -ErrorAction SilentlyContinue

function Set-Theme {
    <#
    .SYNOPSIS
        Applies Windows theme settings (light/dark mode).
    .DESCRIPTION
        Sets system and application theme via registry and broadcasts change notifications.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Apps,
        [string]$System
    )

    $keyPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'

    if ($PSCmdlet.ShouldProcess("Windows Theme", "Set Apps=$Apps, System=$System")) {
        # Ensure key exists
        if (!(Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }

        # Convert theme names to registry values (0=dark, 1=light)
        $appsValue = if ($Apps -eq 'light') { 1 } else { 0 }
        $systemValue = if ($System -eq 'light') { 1 } else { 0 }

        # Apply settings
        Set-ItemProperty -Path $keyPath -Name 'AppsUseLightTheme' -Value $appsValue -Type DWord
        Set-ItemProperty -Path $keyPath -Name 'SystemUsesLightTheme' -Value $systemValue -Type DWord

        # Notify system of changes
        [WinAPI]::BroadcastThemeChange()

        # Small delay for changes to propagate
        Start-Sleep -Milliseconds 500
    }
}

function Close-SettingsIfOpen {
    # Forcefully close any Settings app instances (just in case)
    Get-Process SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Main execution
try {
    Write-Log "Applying wallpaper and theme configuration..." -Level Info

    # Fixed configuration values
    $WallpaperPath = "$env:WINDIR\Web\Wallpaper\Windows\img19.jpg"
    $AppsTheme = 'dark'
    $SystemTheme = 'dark'

    # Ensure Settings isn't running
    Close-SettingsIfOpen

    # Set wallpaper
    Write-Log "Setting wallpaper: $WallpaperPath" -Level Info
    [WinAPI]::SetWallpaper($WallpaperPath)

    # Apply dark theme
    Write-Log "Setting theme: Apps=$AppsTheme, System=$SystemTheme" -Level Info
    Set-Theme -Apps $AppsTheme -System $SystemTheme

    Write-Log "Configuration applied successfully" -Level Success

    # Explicit successful exit
    exit 0

} catch {
    Write-Log "Failed to apply configuration: $($_.Exception.Message)" -Level Error
    exit 1
} finally {
    Complete-DeploymentScript
}
