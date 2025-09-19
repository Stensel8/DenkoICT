# Run each script in separate process to isolate exit commands
Write-Host "[1/3] Installing Winget..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"irm 'https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts/ps_Install-Winget.ps1' | iex`"" -Wait -WindowStyle Hidden

Write-Host "[2/3] Installing Applications..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"irm 'https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts/ps_InstallApplications.ps1' | iex`"" -Wait -WindowStyle Hidden

Write-Host "[3/3] Installing Drivers..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"irm 'https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts/ps_InstallDrivers.ps1' | iex`"" -Wait -WindowStyle Hidden
