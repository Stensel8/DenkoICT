# Define the path to the default dark Windows 11 wallpaper
$wallpaperPath = "C:\Windows\Web\Wallpaper\Windows\img19.jpg"

# Use COM object to set the wallpaper
$code = @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

Add-Type $code
[Wallpaper]::SystemParametersInfo(20, 0, $wallpaperPath, 3)
