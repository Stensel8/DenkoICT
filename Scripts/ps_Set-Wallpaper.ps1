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

<#
.SYNOPSIS
    Sets Windows desktop wallpaper and theme with smooth transitions.

.DESCRIPTION
    This script provides comprehensive wallpaper and theme management for Windows.
    It sets the desktop wallpaper and can apply light, dark, or custom theme combinations
    using Windows API calls and proper broadcast notifications for smooth transitions.

.PARAMETER WallpaperPath
    Optional. Path to the wallpaper image file. 
    Default: "C:\Windows\Web\Wallpaper\Windows\img19.jpg"

.PARAMETER AppsTheme
    Theme for Windows applications. Valid values: 'light', 'dark'
    Default: 'dark'

.PARAMETER SystemTheme
    Theme for Windows system UI. Valid values: 'light', 'dark'
    Default: 'dark'

.PARAMETER ThemePreset
    Optional preset for common theme combinations:
    - 'Dark': Both apps and system in dark mode
    - 'Light': Both apps and system in light mode
    - 'Default': Light apps, dark system
    - 'Inverted': Dark apps, light system

.EXAMPLE
    .\ps_Set-WallpaperAndTheme.ps1
    
    Sets wallpaper to Windows 11 dark theme image with full dark mode.

.EXAMPLE
    .\ps_Set-WallpaperAndTheme.ps1 -WallpaperPath "C:\Company\Wallpaper.jpg" -ThemePreset Light
    
    Sets custom wallpaper with light theme.

.EXAMPLE
    .\ps_Set-WallpaperAndTheme.ps1 -AppsTheme dark -SystemTheme light
    
    Sets custom theme combination with default wallpaper.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. The script sets wallpaper/theme and exits.

.NOTES
    Version      : 1.3.0
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    
    This script requires administrative privileges for some operations.
    Theme changes are applied smoothly without restarting Explorer.

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

#requires -Version 5.1

[CmdletBinding(DefaultParameterSetName = 'Individual', SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({
        if (Test-Path -Path $_ -PathType Leaf) { $true }
        else { throw "Wallpaper file not found: $_" }
    })]
    [string]$WallpaperPath = "C:\Windows\Web\Wallpaper\Windows\img19.jpg",

    [Parameter(ParameterSetName = 'Individual')]
    [ValidateSet('light', 'dark')]
    [string]$AppsTheme = 'dark',

    [Parameter(ParameterSetName = 'Individual')]
    [ValidateSet('light', 'dark')]
    [string]$SystemTheme = 'dark',

    [Parameter(ParameterSetName = 'Preset')]
    [ValidateSet('Dark', 'Light', 'Default', 'Inverted')]
    [string]$ThemePreset
)

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import helper functions
$toolkitPath = Join-Path -Path $PSScriptRoot -ChildPath 'ps_Custom-Functions.ps1'

if (Test-Path -Path $toolkitPath) {
    try {
        . $toolkitPath
        Write-Verbose "Imported shared helper functions from $toolkitPath."
    } catch {
        throw "Failed to import helper toolkit from ${toolkitPath}: $_"
    }
} else {
    throw "Required helper toolkit not found at $toolkitPath."
}

$requiredCommands = @('Assert-AdminRights','Initialize-Environment','Stop-Environment','Write-Log')
foreach ($command in $requiredCommands) {
    if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue)) {
        throw "Required toolkit command '$command' not found after importing ps_Custom-Functions.ps1."
    }
}

# Set correct log name for this script
$Global:DenkoConfig.LogName = "$($MyInvocation.MyCommand.Name).log"

Initialize-Environment
$script:ExitCode = 0

# Theme management constants
$script:keyPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$script:appsThemeKeyName = 'AppsUseLightTheme'
$script:systemThemeKeyName = 'SystemUsesLightTheme'

# Theme conversion functions
function ConvertTo-ThemeRegistryValue {
    param([ValidateSet('light', 'dark')][string]$Theme)
    if ($Theme -eq 'light') { 1 } else { 0 }
}

function ConvertFrom-ThemeRegistryValue {
    param([ValidateSet(0, 1)][int]$Value)
    if ($Value -eq 1) { 'light' } else { 'dark' }
}

# Theme getter functions
function Get-PersonalizeRegistry {
    param([string]$Key)
    try {
        return (Get-ItemProperty -Path $script:keyPath -Name $Key -ErrorAction Stop).($Key)
    } catch {
        Write-Log -Message "Registry key not found: $Key. Defaulting to 0." -Level Verbose
        return 0
    }
}

function Get-WindowsAppsTheme {
    return ConvertFrom-ThemeRegistryValue (Get-PersonalizeRegistry $script:appsThemeKeyName)
}

function Get-WindowsSystemTheme {
    return ConvertFrom-ThemeRegistryValue (Get-PersonalizeRegistry $script:systemThemeKeyName)
}

function Get-WindowsTheme {
    [PSCustomObject]@{
        Apps = Get-WindowsAppsTheme
        System = Get-WindowsSystemTheme
    }
}

# Theme setter functions
function Set-PersonalizeRegistry {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low')]
    param(
        [string]$Key,
        [int]$Value
    )
    
    if ($PSCmdlet.ShouldProcess("$Key = $Value", "Set registry value")) {
        # Ensure registry path exists
        if (-not (Test-Path -Path $script:keyPath)) {
            New-Item -Path $script:keyPath -Force | Out-Null
            Write-Log -Message "Created registry path: $script:keyPath" -Level Verbose
        }
        
        Set-ItemProperty -Path $script:keyPath -Name $Key -Value $Value -Type DWord -Force
        Write-Log -Message "Set $Key = $Value" -Level Verbose
    }
}

function Set-WindowsAppsTheme {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low')]
    param([ValidateSet('light', 'dark')][string]$Theme)
    
    Set-PersonalizeRegistry -Key $script:appsThemeKeyName -Value (ConvertTo-ThemeRegistryValue $Theme)
}

function Set-WindowsSystemTheme {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low')]
    param([ValidateSet('light', 'dark')][string]$Theme)
    
    Set-PersonalizeRegistry -Key $script:systemThemeKeyName -Value (ConvertTo-ThemeRegistryValue $Theme)
}

function Set-WindowsTheme {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low')]
    param(
        [ValidateSet('light', 'dark')][string]$Apps = 'light',
        [ValidateSet('light', 'dark')][string]$System = 'dark'
    )

    Write-Log -Message "Setting Windows theme - Apps: $Apps, System: $System" -Level Info

    if ($PSCmdlet.ShouldProcess("Apps=$Apps, System=$System", "Set Windows theme")) {
        # Try official Microsoft dark theme method first (only for full dark mode)
        if ($Apps -eq 'dark' -and $System -eq 'dark') {
            $darkThemePath = "C:\Windows\Resources\Themes\dark.theme"

            if (Test-Path -Path $darkThemePath) {
                try {
                    Write-Log -Message "Activating official dark theme via $darkThemePath" -Level Verbose
                    Start-Process -FilePath $darkThemePath -Wait -ErrorAction Stop
                    Write-Log -Message "Dark theme successfully activated via official method" -Level Info
                    return
                } catch {
                    Write-Log -Message "Official theme activation failed: $_. Falling back to registry method." -Level Warning
                }
            } else {
                Write-Log -Message "Dark theme file not found at $darkThemePath. Falling back to registry method." -Level Warning
            }
        }

        # Fallback: use registry method
        Write-Log -Message "Applying theme via registry method" -Level Verbose
        Set-WindowsAppsTheme -Theme $Apps
        Set-WindowsSystemTheme -Theme $System

        # Broadcast theme change for smooth transition
        Send-ThemeChangeNotification
    }
}

# API definitions
$script:apiDefinitions = @'
using System;
using System.Runtime.InteropServices;
using System.ComponentModel;

public class WallpaperApi {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

    private const int SPI_SETDESKWALLPAPER = 20;
    private const int SPIF_UPDATEINIFILE = 0x01;
    private const int SPIF_SENDWININICHANGE = 0x02;

    public static void SetWallpaper(string path) {
        bool result = SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, path, SPIF_UPDATEINIFILE | SPIF_SENDWININICHANGE);
        if (!result) {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}

public class ThemeApi {
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, 
        uint Msg, 
        IntPtr wParam, 
        string lParam, 
        uint fuFlags, 
        uint uTimeout, 
        out IntPtr lpdwResult
    );
    
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    private const int HWND_BROADCAST = 0xFFFF;
    private const uint WM_WININICHANGE = 0x001A;
    private const uint WM_SETTINGCHANGE = WM_WININICHANGE;
    private const uint WM_THEMECHANGED = 0x031A;
    private const uint SMTO_ABORTIFHUNG = 0x0002;

    public static void BroadcastThemeChange() {
        IntPtr result;
        IntPtr hWnd = new IntPtr(HWND_BROADCAST);
        
        // Send ImmersiveColorSet change notification
        SendMessageTimeout(hWnd, WM_SETTINGCHANGE, IntPtr.Zero, "ImmersiveColorSet", 
            SMTO_ABORTIFHUNG, 5000, out result);
        
        // Send general theme change
        PostMessage(hWnd, WM_THEMECHANGED, IntPtr.Zero, IntPtr.Zero);
    }
}
'@

# Load API types if not already loaded
if (-not ('WallpaperApi' -as [Type])) {
    Add-Type -TypeDefinition $script:apiDefinitions -ErrorAction Stop
    Write-Log -Message "Windows APIs loaded successfully" -Level Verbose
}

function Send-ThemeChangeNotification {
    Write-Log -Message "Broadcasting theme change notification" -Level Verbose
    try {
        [ThemeApi]::BroadcastThemeChange()
        Write-Log -Message "Theme change notification sent" -Level Verbose
        
        # Give apps a moment to process the change
        Start-Sleep -Milliseconds 500
    } catch {
        Write-Log -Message "Failed to broadcast theme change: $_" -Level Warning
    }
}

# Main execution
try {
    # Check for admin rights (not always required for theme changes)
    try {
        Assert-AdminRights
    } catch {
        Write-Log -Message "Running without admin rights - some features may be limited" -Level Warning
    }

    # Handle theme preset parameter
    if ($PSBoundParameters.ContainsKey('ThemePreset')) {
        Write-Log -Message "Applying theme preset: $ThemePreset" -Level Info
        
        switch ($ThemePreset) {
            'Dark' { 
                $AppsTheme = 'dark'
                $SystemTheme = 'dark'
            }
            'Light' {
                $AppsTheme = 'light'
                $SystemTheme = 'light'
            }
            'Default' {
                $AppsTheme = 'light'
                $SystemTheme = 'dark'
            }
            'Inverted' {
                $AppsTheme = 'dark'
                $SystemTheme = 'light'
            }
        }
    }

    # Get current theme for comparison
    $currentTheme = Get-WindowsTheme
    Write-Log -Message "Current theme - Apps: $($currentTheme.Apps), System: $($currentTheme.System)" -Level Verbose

    # Step 1: Set wallpaper
    Write-Log -Message "Step 1/2: Setting desktop wallpaper" -Level Verbose
    Write-Log -Message "  Target: $WallpaperPath" -Level Verbose

    if ($PSCmdlet.ShouldProcess($WallpaperPath, 'Set desktop wallpaper')) {
        [WallpaperApi]::SetWallpaper($WallpaperPath)
        Write-Log -Message "  Wallpaper set successfully" -Level Verbose
    }

    # Step 2: Apply theme if needed
    if ($currentTheme.Apps -ne $AppsTheme -or $currentTheme.System -ne $SystemTheme) {
        Write-Log -Message "Step 2/2: Applying theme changes" -Level Verbose
        Set-WindowsTheme -Apps $AppsTheme -System $SystemTheme
        Write-Log -Message "  Theme applied successfully" -Level Verbose
    } else {
        Write-Log -Message "Step 2/2: Theme already set to requested values" -Level Verbose
    }

    Write-Log -Message "Configuration completed successfully" -Level Verbose

} catch {
    $script:ExitCode = 1
    Write-Log -Message "Failed to complete configuration: $_" -Level Error
} finally {
    Stop-Environment
}

if ($script:ExitCode -ne 0) {
    exit $script:ExitCode
}