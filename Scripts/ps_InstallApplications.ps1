# List of application IDs or names to install
$apps = @(
    #"abbodi1406.vcredist",
    "Microsoft.VCRedist.2015+.x64",
    "Microsoft.Office"
)

# Function to install each application
foreach ($app in $apps) {
    Write-Host "Installing $app..." -ForegroundColor Cyan
    try {
        winget install --id $app --accept-source-agreements --accept-package-agreements -e -h
        Write-Host "$app installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to install $app." -ForegroundColor Red
    }
}
