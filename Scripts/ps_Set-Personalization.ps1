# Set Windows 11 Dark Wallpaper for Desktop and Lock Screen
try {
    # Path to dark wallpaper (prefer 4K version if available)
    $darkWallpaper = if (Test-Path "$env:WINDIR\Web\4K\Wallpaper\Windows\img19_1920x1200.jpg") {
        "$env:WINDIR\Web\4K\Wallpaper\Windows\img19_1920x1200.jpg"
    } else {
        "$env:WINDIR\Web\Wallpaper\Windows\img19.jpg"
    }
    
    Write-Host "Setting dark wallpaper: $darkWallpaper"
    
    # Set desktop wallpaper
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -Value $darkWallpaper
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10"  # Fill
    
    # Set lock screen wallpaper  
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "LockScreenImage" -Value $darkWallpaper
    
    # Refresh desktop wallpaper
    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class Win32 { [DllImport("user32.dll")] public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni); }'
    [Win32]::SystemParametersInfo(0x0014, 0, $darkWallpaper, 0x0003)
    
    Write-Host "Dark wallpaper applied successfully"
    
} catch {
    Write-Error "Failed to set wallpaper: $($_.Exception.Message)"
}