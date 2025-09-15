
# Install dependencies first
Add-AppxPackage -Path ".\Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64__8wekyb3d8bbwe.Appx"
Add-AppxPackage -Path ".\Microsoft.VCLibs.140.00_14.0.33519.0_x64__8wekyb3d8bbwe.Appx"
Add-AppxPackage -Path ".\Microsoft.VCLibs.140.00.UWPDesktop_14.0.33728.0_x64__8wekyb3d8bbwe.Appx"

# Then install App Installer
Add-AppxPackage -Path ".\Microsoft.DesktopAppInstaller_2025.717.1857.0_neutral_~_8wekyb3d8bbwe.Msixbundle"

winget source update