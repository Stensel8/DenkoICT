<#PSScriptInfo

.VERSION 1.1.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Wallpaper Desktop Customization Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.1.0] - Added WhatIf support, centralized logging, and admin validation.
[Version 1.0.0] - Initial Release. Sets Windows desktop wallpaper to img19.jpg (dark theme).
[Version 1.0.1] - Improved logging. NOTE: some EDRs may block this script.
#>

<#
.SYNOPSIS
    Sets the Windows desktop wallpaper to the default dark theme image.

.DESCRIPTION
    This script sets the desktop wallpaper to the Windows 11 dark theme wallpaper (img19.jpg)
    using Windows API calls through P/Invoke. The change is immediate and persistent across
    user sessions.

.PARAMETER WallpaperPath
    Optional. Path to the wallpaper image file. 
    Default: "C:\Windows\Web\Wallpaper\Windows\img19.jpg"

.EXAMPLE
    .\ps_Set-Wallpaper.ps1
    
    Sets the wallpaper to the default Windows 11 dark theme image.

.EXAMPLE
    .\ps_Set-Wallpaper.ps1 -WallpaperPath "C:\Company\Wallpaper.jpg"
    
    Sets the wallpaper to a custom image path.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. The script sets the wallpaper and exits.

.NOTES
    Version      : 1.0.1
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    
    This script requires administrative privileges to run successfully.
    Uses Windows API SystemParametersInfo to ensure immediate wallpaper change.
    
    The script is typically used as part of device deployment to apply corporate branding.

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({
        if (Test-Path $_) { $true }
        else { throw "Wallpaper file not found: $_" }
    })]
    [string]$WallpaperPath = "C:\Windows\Web\Wallpaper\Windows\img19.jpg"
)

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolkitPath = Join-Path -Path $PSScriptRoot -ChildPath 'ps_Invoke-AdminToolkit.ps1'
$script:ToolkitLoaded = $false

if (Test-Path -Path $toolkitPath) {
    try {
        . $toolkitPath
        $script:ToolkitLoaded = $true
        Write-Verbose "Imported shared helper functions from $toolkitPath."
    } catch {
        Write-Verbose "Failed to import helper toolkit from ${toolkitPath}: $_"
    }
} else {
    Write-Verbose "Helper toolkit not found at $toolkitPath. Falling back to local helper implementations."
}

if (-not (Get-Command -Name Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [Parameter()]
            [ValidateSet('Info','Success','Warning','Error','Verbose')]
            [string]$Level = 'Info'
        )

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $formatted = "[$timestamp] [$Level] $Message"

        $color = switch ($Level) {
            'Success' { 'Green' }
            'Warning' { 'Yellow' }
            'Error'   { 'Red' }
            'Verbose' { 'Cyan' }
            default   { 'White' }
        }

        Write-Host $formatted -ForegroundColor $color
    }
}

if (-not (Get-Command -Name Assert-AdminRights -ErrorAction SilentlyContinue)) {
    function Assert-AdminRights {
        [CmdletBinding()]
        param()

        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)

        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $message = 'This script requires administrative privileges. Please run in an elevated PowerShell session.'
            Write-Log -Message $message -Level 'Error'
            throw $message
        }
    }
}

Assert-AdminRights

# Define the Windows API code for setting wallpaper
$wallpaperCode = @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    
    // Constants for SystemParametersInfo
    public const int SPI_SETDESKWALLPAPER = 20;
    public const int SPIF_UPDATEINIFILE = 0x01;
    public const int SPIF_SENDWININICHANGE = 0x02;
}
"@

try {
    Write-Verbose "Setting wallpaper to: $WallpaperPath"
    
    # Add the type and cache the result
    $WallpaperType = Add-Type -TypeDefinition $wallpaperCode -PassThru -ErrorAction Stop
    
    if ($PSCmdlet.ShouldProcess($WallpaperPath, 'Set desktop wallpaper')) {
        # Parameters: SPI_SETDESKWALLPAPER (20), 0, path, SPIF_UPDATEINIFILE | SPIF_SENDWININICHANGE (3)
        $result = [Wallpaper]::SystemParametersInfo(20, 0, $WallpaperPath, 3)

        if ($result) {
            Write-Log -Message "Wallpaper successfully set to: $WallpaperPath" -Level Success
        } else {
            $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Failed to set wallpaper. Win32 error code: $lastError"
        }
    } else {
    Write-Verbose 'WhatIf: Skipping wallpaper update.'
    Write-Log -Message "WhatIf: Would set wallpaper to $WallpaperPath" -Level Warning
    }

} catch {
    Write-Error "Failed to set wallpaper: $_"
    exit 1
}
