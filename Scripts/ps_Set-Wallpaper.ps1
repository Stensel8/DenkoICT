<#PSScriptInfo

.VERSION 1.1.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows Wallpaper Desktop Customization Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Sets Windows desktop wallpaper to img19.jpg (dark theme).
[Version 1.0.1] - Improved logging. NOTE: some EDRs may block this script.
[Version 1.1.0] - Added WhatIf support, centralized logging, and admin validation.
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
    Version      : 1.1.0
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
        if (Test-Path -Path $_ -PathType Leaf) { $true }
        else { throw "Wallpaper file not found: $_" }
    })]
    [string]$WallpaperPath = "C:\Windows\Web\Wallpaper\Windows\img19.jpg"
)

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

Initialize-Environment
$script:ExitCode = 0

try {
    Assert-AdminRights

    # Define the Windows API code for setting wallpaper
    $wallpaperCode = @'
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    
    // Constants for SystemParametersInfo
    public const int SPI_SETDESKWALLPAPER = 20;
    public const int SPIF_UPDATEINIFILE = 0x01;
    public const int SPIF_SENDWININICHANGE = 0x02;
}
'@

    if (-not ('Wallpaper' -as [Type])) {
        Add-Type -TypeDefinition $wallpaperCode -ErrorAction Stop | Out-Null
    }

    Write-Log -Message "Setting wallpaper to: $WallpaperPath" -Level Info

    if ($PSCmdlet.ShouldProcess($WallpaperPath, 'Set desktop wallpaper')) {
        # Parameters: SPI_SETDESKWALLPAPER (20), 0, path, SPIF_UPDATEINIFILE | SPIF_SENDWININICHANGE (3)
        $result = [Wallpaper]::SystemParametersInfo(20, 0, $WallpaperPath, 3)

        if ($result) {
            Write-Log -Message ("Wallpaper successfully set to: {0}" -f $WallpaperPath) -Level Success
        } else {
            $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Failed to set wallpaper. Win32 error code: $lastError"
        }
    } else {
        Write-Log -Message 'WhatIf: Skipping wallpaper update.' -Level Verbose
        Write-Log -Message ('WhatIf: Would set wallpaper to {0}' -f $WallpaperPath) -Level Warning
    }

} catch {
    $script:ExitCode = 1
    Write-Log -Message ("Failed to set wallpaper: {0}" -f $_) -Level Error
} finally {
    Stop-Environment
}

if ($script:ExitCode -ne 0) {
    exit $script:ExitCode
}