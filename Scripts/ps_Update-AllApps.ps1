Function Update-AllApps {
    <#
    .SYNOPSIS
        This will update all programs using Winget
    #>

    # Setup logging
    $logdir = "$env:USERPROFILE\Documents\Logs"
    if (!(Test-Path $logdir)) { New-Item -ItemType Directory -Path $logdir | Out-Null }
    $logPath = "$logdir\winget-update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    
    # Simple script block for elevated execution
    $scriptBlock = @"
        `$host.ui.RawUI.WindowTitle = 'Winget Update'
        Start-Transcript '$logPath' -Append
        Write-Host 'Starting Winget upgrade...' -ForegroundColor Green
        
        # Execute winget upgrade and capture result
        winget upgrade --all --accept-source-agreements --accept-package-agreements --scope=machine --silent
        `$exitCode = `$LASTEXITCODE
        
        # Print end results
        Write-Host '=' * 50 -ForegroundColor Cyan
        Write-Host 'WINGET UPDATE RESULTS' -ForegroundColor Cyan
        Write-Host '=' * 50 -ForegroundColor Cyan
        
        if (`$exitCode -eq 0) { 
            Write-Host 'Status: SUCCESS - All updates completed successfully!' -ForegroundColor Green
        } else { 
            Write-Host 'Status: WARNING - Update completed with exit code: `$exitCode' -ForegroundColor Yellow
        }
        
        Write-Host 'Log file: $logPath' -ForegroundColor White
        Write-Host 'Timestamp: ' -NoNewline -ForegroundColor White
        Write-Host (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -ForegroundColor White
        Write-Host '=' * 50 -ForegroundColor Cyan
        
        Stop-Transcript
        Write-Host 'Press any key to close...' -ForegroundColor Yellow
        `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
"@

    Write-Host "Starting Winget update (elevated)..." -ForegroundColor Cyan
    Write-Host "Log will be saved to: $logPath" -ForegroundColor Gray
    
    $global:WinGetInstall = Start-Process powershell -Verb RunAs -ArgumentList "-NoExit", "-Command", $scriptBlock -PassThru
    
    # Print information about the started process
    Write-Host "Update process started (PID: $($global:WinGetInstall.Id))" -ForegroundColor Green
    Write-Host "Check the elevated PowerShell window for real-time progress and results." -ForegroundColor Yellow
}

# Run if executed directly
if ($MyInvocation.InvocationName -ne '.') { Update-AllApps }
