Function Update-AllWinget {

    <#

    .SYNOPSIS
        This will update all programs using Winget

    #>

    [ScriptBlock]$wingetinstall = {

        # Define log directory and timestamp for transcript
        $logdir = "$env:USERPROFILE\Documents\Logs"
        if (!(Test-Path -Path $logdir)) {
            New-Item -ItemType Directory -Path $logdir | Out-Null
        }
        $dateTime = Get-Date -Format "yyyyMMdd_HHmmss"
        $host.ui.RawUI.WindowTitle = """Winget Install"""

        Start-Transcript "$logdir\winget-update_$dateTime.log" -Append
        winget upgrade --all --accept-source-agreements --accept-package-agreements --scope=machine --silent

    }

    $global:WinGetInstall = Start-Process -Verb runas powershell -ArgumentList "-command invoke-command -scriptblock {$wingetinstall}" -PassThru

}