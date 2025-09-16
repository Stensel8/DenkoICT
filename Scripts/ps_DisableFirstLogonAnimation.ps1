# Registry path
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

# Create the key if it doesn't exist
If (-Not (Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}

# Disable the first logon animation
Set-ItemProperty -Path $RegPath -Name EnableFirstLogonAnimation -Type DWord -Value 0

Write-Host "First logon animation disabled."
