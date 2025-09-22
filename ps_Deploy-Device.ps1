# Enhanced Denko ICT Device Deployment Script with Logging
# Version: 2.0 - Enhanced with comprehensive logging

# Initialize logging
$LogFile = "C:\DenkoICT-Deployment.log"

function Write-DeploymentLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] [ps_Deploy-Device] $Message"
    
    # Write to both console and log file
    Write-Host $LogEntry
    Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8
}

Write-DeploymentLog "=== Denko ICT Device Deployment Started ===" "INFO"
Write-DeploymentLog "Script: ps_Deploy-Device.ps1" "INFO"

# Run each script in separate process to isolate exit commands
Write-DeploymentLog "Starting Winget Installation..." "INFO"
Write-Host "[1/4] Installing Winget..." -ForegroundColor Cyan
try {
    $process = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"irm 'https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts/ps_Install-Winget.ps1' | iex`"" -Wait -WindowStyle Hidden -PassThru
    if ($process.ExitCode -eq 0) {
        Write-DeploymentLog "Winget installation completed successfully" "INFO"
    } else {
        Write-DeploymentLog "Winget installation failed with exit code: $($process.ExitCode)" "ERROR"
    }
} catch {
    Write-DeploymentLog "Winget installation error: $($_.Exception.Message)" "ERROR"
}

Write-DeploymentLog "Starting Drivers Installation..." "INFO"
Write-Host "[2/4] Installing Drivers..." -ForegroundColor Cyan
try {
    $process = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"irm 'https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts/ps_InstallDrivers.ps1' | iex`"" -Wait -WindowStyle Hidden -PassThru
    if ($process.ExitCode -eq 0) {
        Write-DeploymentLog "Drivers installation completed successfully" "INFO"
    } else {
        Write-DeploymentLog "Drivers installation failed with exit code: $($process.ExitCode)" "ERROR"
    }
} catch {
    Write-DeploymentLog "Drivers installation error: $($_.Exception.Message)" "ERROR"
}

Write-DeploymentLog "Starting Applications Installation..." "INFO"
Write-Host "[3/4] Installing Applications..." -ForegroundColor Cyan
try {
    $process = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"irm 'https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts/ps_InstallApplications.ps1' | iex`"" -Wait -WindowStyle Hidden -PassThru
    if ($process.ExitCode -eq 0) {
        Write-DeploymentLog "Applications installation completed successfully" "INFO"
    } else {
        Write-DeploymentLog "Applications installation failed with exit code: $($process.ExitCode)" "ERROR"
    }
} catch {
    Write-DeploymentLog "Applications installation error: $($_.Exception.Message)" "ERROR"
}

Write-DeploymentLog "Starting Personalization Setup..." "INFO"
Write-Host "[4/4] Setting Personalization..." -ForegroundColor Cyan
try {
    $process = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"irm 'https://raw.githubusercontent.com/Stensel8/DenkoICT/refs/heads/main/Scripts/ps_Set-Personalization.ps1' | iex`"" -Wait -WindowStyle Hidden -PassThru
    if ($process.ExitCode -eq 0) {
        Write-DeploymentLog "Personalization setup completed successfully" "INFO"
    } else {
        Write-DeploymentLog "Personalization setup failed with exit code: $($process.ExitCode)" "ERROR"
    }
} catch {
    Write-DeploymentLog "Personalization setup error: $($_.Exception.Message)" "ERROR"
}

Write-DeploymentLog "=== Denko ICT Device Deployment Completed ===" "INFO"
Write-DeploymentLog "Check log file for detailed results: $LogFile" "INFO"

# Display completion message
Write-Host "`n=== Deployment Summary ===" -ForegroundColor Green
Write-Host "Deployment script completed. Check log file: $LogFile" -ForegroundColor Green
Write-Host "=========================`n" -ForegroundColor Green