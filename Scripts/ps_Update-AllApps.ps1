function Update-AllApps {
    
    Clear-Host
    
    Write-Host "Detected the following updatable packages:" -ForegroundColor Green
    Write-Host "----------------------------------------" -ForegroundColor Green
    # Check for available updates
    try {
        winget upgrade
    }
    catch {
        Write-Host "Error checking for updates: $_" -ForegroundColor Red
        return
    }

        Write-Host "Updating packages..." -ForegroundColor Blue
        try {
            winget upgrade --all --accept-source-agreements --accept-package-agreements --silent --force
            Write-Host "Updates completed successfully!" -ForegroundColor Green
        }
        catch {
            Write-Host "Error during update: $_" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "Exiting..." -ForegroundColor Green
    Start-Sleep -Seconds 1

# Call the main function
Update-AllApps
