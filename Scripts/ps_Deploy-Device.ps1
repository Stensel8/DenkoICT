#requires -Version 5.1
<#
.SYNOPSIS
    Orchestrates Denko ICT device provisioning with structured logging, user-friendly notifications,
    and controlled parallel execution.
.NOTES
    - Uses PowerShell background jobs to safely parallelise compatible workloads.
    - Logs in both human-readable and machine-readable (JSONL) formats under %ProgramData%\DenkoICT\Logs.
    - Displays Windows toast notifications (with graceful fallback when unavailable).
    - Leaves the window open at completion so end users can review the outcome.
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

## region Paths & session metadata
$script:SessionId = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogRoot = Join-Path -Path ${env:ProgramData} -ChildPath 'DenkoICT\\Logs'
if (-not (Test-Path $script:LogRoot)) {
    New-Item -Path $script:LogRoot -ItemType Directory -Force | Out-Null
}

$script:TextLogPath = Join-Path -Path $script:LogRoot -ChildPath "Deployment-$($script:SessionId).log"
$script:JsonLogPath = Join-Path -Path $script:LogRoot -ChildPath "Deployment-$($script:SessionId).jsonl"
$script:TranscriptPath = Join-Path -Path $script:LogRoot -ChildPath "Transcript-$($script:SessionId).txt"
$script:LogLock = New-Object System.Object
$script:DeploymentStart = Get-Date

Start-Transcript -Path $script:TranscriptPath -Append | Out-Null
## endregion

## region Utility helpers
function Get-StepColor {
    param([string]$Level)
    switch ($Level.ToUpperInvariant()) {
        'ERROR' { return 'Red' }
        'WARN' { return 'Yellow' }
        'SUCCESS' { return 'Green' }
        'INFO' { return 'Cyan' }
        'DEBUG' { return 'Gray' }
        default { return 'White' }
    }
}

function Write-DeploymentLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DEBUG')] [string] $Level = 'INFO',
        [string] $StepName
    )

    $timestamp = Get-Date
    $entry = [PSCustomObject]@{
        TimestampUtc = $timestamp.ToUniversalTime().ToString('o')
        TimestampLocal = $timestamp.ToString('yyyy-MM-dd HH:mm:ss')
        Level         = $Level
        Step          = $StepName
        Message       = $Message
        SessionId     = $script:SessionId
    }

    $stepLabel = if ($entry.Step) { $entry.Step } else { 'orchestrator' }
    $textLine = "[$($entry.TimestampLocal)] [$Level] [$stepLabel] $Message"

    [System.Threading.Monitor]::Enter($script:LogLock)
    try {
        Add-Content -Path $script:TextLogPath -Value $textLine -Encoding UTF8
        $entry | ConvertTo-Json -Compress | Add-Content -Path $script:JsonLogPath -Encoding UTF8
    }
    finally {
        [System.Threading.Monitor]::Exit($script:LogLock)
    }

    $color = Get-StepColor -Level $Level
    Write-Host $textLine -ForegroundColor $color
}

function Show-DeploymentNotification {
    param(
        [string]$Title,
        [string]$Body,
        [ValidateSet('Info','Success','Warning','Error')] [string]$Severity = 'Info'
    )

    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

        $toastXml = @"
<toast scenario="default">
  <visual>
    <binding template="ToastGeneric">
      <text>$([Security.SecurityElement]::Escape($Title))</text>
      <text>$([Security.SecurityElement]::Escape($Body))</text>
    </binding>
  </visual>
  <actions>
    <action content="Open log" activationType="protocol" arguments="file:///$($script:TextLogPath.Replace('\', '/'))"/>
  </actions>
</toast>
"@

        $xmlDoc = [Windows.Data.Xml.Dom.XmlDocument]::new()
        $xmlDoc.LoadXml($toastXml)

        $toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDoc)

        switch ($Severity) {
            'Success' { $toast.Tag = 'success' }
            'Warning' { $toast.Tag = 'warning' }
            'Error'   { $toast.Tag = 'error' }
            default   { $toast.Tag = 'info' }
        }

        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('DenkoICT.Deployment')
        $notifier.Show($toast)
    } catch {
        Write-DeploymentLog -Message "Toast notification unavailable: $($_.Exception.Message)" -Level 'DEBUG'
    }
}

function Update-DeploymentProgress {
    param(
        [int]$Completed,
        [int]$Total,
        [string]$CurrentStatus
    )

    $percent = if ($Total -gt 0) { [math]::Floor(($Completed / $Total) * 100) } else { 0 }
    Write-Progress -Id 1 -Activity 'Denko ICT Device Deployment' -Status $CurrentStatus -PercentComplete $percent
}

function Start-DeploymentJob {
    param(
        [Parameter(Mandatory)][pscustomobject]$Task
    )

    $job = Start-Job -Name $Task.Name -InitializationScript {
        $ProgressPreference = 'SilentlyContinue'
        $InformationPreference = 'Continue'
    } -ScriptBlock {
        param($Path)
        try {
            & $Path
            return [PSCustomObject]@{ Success = $true; ExitCode = $LASTEXITCODE }
        } catch {
            Write-Error $_
            return [PSCustomObject]@{ Success = $false; ExitCode = 1; ErrorMessage = $_.Exception.Message }
        }
    } -ArgumentList $Task.Path

    return [PSCustomObject]@{
        Task       = $Task
        Job        = $job
        Stopwatch  = [System.Diagnostics.Stopwatch]::StartNew()
    }
}

function Receive-DeploymentJobOutput {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Job]$Job,
        [string]$StepName
    )

    $records = Receive-Job -Job $Job -Keep -ErrorAction SilentlyContinue -InformationAction Continue -WarningAction Continue
    foreach ($record in $records) {
        switch ($record.GetType().FullName) {
            'System.Management.Automation.ErrorRecord' {
                Write-DeploymentLog -Message $record.ToString() -Level 'ERROR' -StepName $StepName
            }
            'System.Management.Automation.WarningRecord' {
                Write-DeploymentLog -Message $record.Message -Level 'WARN' -StepName $StepName
            }
            'System.Management.Automation.VerboseRecord' {
                Write-DeploymentLog -Message $record.Message -Level 'DEBUG' -StepName $StepName
            }
            'System.Management.Automation.ProgressRecord' { }
            'System.Management.Automation.InformationRecord' {
                Write-DeploymentLog -Message $record.MessageData -Level 'INFO' -StepName $StepName
            }
            default {
                if ($null -ne $record) {
                    Write-DeploymentLog -Message ($record | Out-String).Trim() -Level 'INFO' -StepName $StepName
                }
            }
        }
    }
}

function Wait-DeploymentJobs {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Contexts,
        [ref]$CompletedCounter
    )

    while ($Contexts.Count -gt 0) {
        foreach ($context in @($Contexts)) {
            Receive-DeploymentJobOutput -Job $context.Job -StepName $context.Task.Name

            if ($context.Job.State -in 'Completed','Failed','Stopped') {
                $context.Stopwatch.Stop()
                $result = Receive-Job -Job $context.Job -Wait -Keep -ErrorAction SilentlyContinue
                $exitCode = 0
                $success = $true
                $message = 'Step completed.'

                if ($result -and ($result | Where-Object { $_.PSObject.Properties.Name -contains 'Success' })) {
                    $success = $result.Success
                    $exitCode = $result.ExitCode
                    if ($result.ErrorMessage) {
                        $message = $result.ErrorMessage
                    }
                } elseif ($context.Job.State -eq 'Failed') {
                    $success = $false
                    $exitCode = 1
                    $message = ($context.Job.ChildJobs | Select-Object -ExpandProperty JobStateInfo | Select-Object -ExpandProperty Reason | Select-Object -ExpandProperty Message) -join '; '
                }

                $duration = [math]::Round($context.Stopwatch.Elapsed.TotalMinutes, 2)
                if ($success) {
                    Write-DeploymentLog -Message "Completed in $duration minute(s) (exit code $exitCode). $message" -Level 'SUCCESS' -StepName $context.Task.Name
                    Show-DeploymentNotification -Title "$($context.Task.FriendlyTitle) complete" -Body "Finished in $duration minute(s)." -Severity 'Success'
                } else {
                    Write-DeploymentLog -Message "Failed after $duration minute(s). Details: $message" -Level 'ERROR' -StepName $context.Task.Name
                    Show-DeploymentNotification -Title "$($context.Task.FriendlyTitle) failed" -Body $message -Severity 'Error'
                }

                Remove-Job -Job $context.Job -Force | Out-Null
                $Contexts.Remove($context)
                $CompletedCounter.Value++
            }
        }

        Start-Sleep -Milliseconds 400
    }
}
## endregion

## region Task definitions
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$tasks = @(
    [PSCustomObject]@{
        Name          = 'Install-WinGet'
        FriendlyTitle = 'Installing WinGet'
        Path          = Join-Path -Path $scriptRoot -ChildPath 'ps_Install-Winget.ps1'
        ParallelSafe  = $false
    },
    [PSCustomObject]@{
        Name          = 'Install-Drivers'
        FriendlyTitle = 'Updating device drivers'
        Path          = Join-Path -Path $scriptRoot -ChildPath 'ps_Install-Drivers.ps1'
        ParallelSafe  = $true
    },
    [PSCustomObject]@{
        Name          = 'Install-Applications'
        FriendlyTitle = 'Deploying applications'
        Path          = Join-Path -Path $scriptRoot -ChildPath 'ps_Install-Applications.ps1'
        ParallelSafe  = $true
    },
    [PSCustomObject]@{
        Name          = 'Set-Wallpaper'
        FriendlyTitle = 'Setting corporate wallpaper'
        Path          = Join-Path -Path $scriptRoot -ChildPath 'ps_Set-Wallpaper.ps1'
        ParallelSafe  = $false
    }
)

foreach ($task in $tasks) {
    if (-not (Test-Path -Path $task.Path)) {
        throw "Task script not found: $($task.Path)"
    }
}

$totalSteps = $tasks.Count
$completedSteps = 0

Write-DeploymentLog -Message '=== Denko ICT Device Deployment Started ===' -Level 'INFO'
Write-DeploymentLog -Message "Session ID: $($script:SessionId) | Transcript: $($script:TranscriptPath)" -Level 'DEBUG'

if (-not $env:WT_SESSION) {
    Write-DeploymentLog -Message 'Consider launching from Windows Terminal for the best experience.' -Level 'WARN'
}

Show-DeploymentNotification -Title 'Denko ICT deployment' -Body 'Configuration has started. Sit tight while we prepare your device.'

Update-DeploymentProgress -Completed $completedSteps -Total $totalSteps -CurrentStatus 'Preparing environment'

## Step 1: Install WinGet (sequential prerequisite)
$wingetTask = $tasks | Where-Object Name -eq 'Install-WinGet'
Write-DeploymentLog -Message "Starting step: $($wingetTask.FriendlyTitle)" -StepName $wingetTask.Name
Show-DeploymentNotification -Title $wingetTask.FriendlyTitle -Body 'Downloading and configuring Windows Package Manager.'

$wingetContext = Start-DeploymentJob -Task $wingetTask
Update-DeploymentProgress -Completed $completedSteps -Total $totalSteps -CurrentStatus $wingetTask.FriendlyTitle

$list = [System.Collections.Generic.List[object]]::new()
$list.Add($wingetContext) | Out-Null
Wait-DeploymentJobs -Contexts $list -CompletedCounter ([ref]$completedSteps)
Update-DeploymentProgress -Completed $completedSteps -Total $totalSteps -CurrentStatus 'Winget ready'

## Steps 2 & 3: Drivers and applications (parallel)
$parallelTasks = $tasks | Where-Object { $_.ParallelSafe -and $_.Name -ne 'Install-WinGet' -and $_.Name -ne 'Set-Wallpaper' }
if ($parallelTasks.Count -gt 0) {
    Write-DeploymentLog -Message "Launching parallel tasks: $($parallelTasks.Name -join ', ')" -Level 'INFO'
    foreach ($task in $parallelTasks) {
        Write-DeploymentLog -Message "Starting step: $($task.FriendlyTitle)" -StepName $task.Name
        Show-DeploymentNotification -Title $task.FriendlyTitle -Body 'Running in the background. This may take a few minutes.'
    }

    $parallelContexts = [System.Collections.Generic.List[object]]::new()
    foreach ($task in $parallelTasks) {
        $parallelContexts.Add((Start-DeploymentJob -Task $task)) | Out-Null
    }

    Update-DeploymentProgress -Completed $completedSteps -Total $totalSteps -CurrentStatus 'Running parallel tasks'
    Wait-DeploymentJobs -Contexts $parallelContexts -CompletedCounter ([ref]$completedSteps)
}

## Final step: wallpaper (sequential finish)
$wallpaperTask = $tasks | Where-Object Name -eq 'Set-Wallpaper'
Write-DeploymentLog -Message "Starting step: $($wallpaperTask.FriendlyTitle)" -StepName $wallpaperTask.Name
Show-DeploymentNotification -Title $wallpaperTask.FriendlyTitle -Body 'Applying finishing touches.'

$wallpaperContext = Start-DeploymentJob -Task $wallpaperTask
$finalList = [System.Collections.Generic.List[object]]::new()
$finalList.Add($wallpaperContext) | Out-Null
Update-DeploymentProgress -Completed $completedSteps -Total $totalSteps -CurrentStatus $wallpaperTask.FriendlyTitle
Wait-DeploymentJobs -Contexts $finalList -CompletedCounter ([ref]$completedSteps)

Update-DeploymentProgress -Completed $totalSteps -Total $totalSteps -CurrentStatus 'Deployment complete'
Write-Progress -Id 1 -Activity 'Denko ICT Device Deployment' -Status 'All steps complete' -PercentComplete 100

Write-DeploymentLog -Message '=== Denko ICT Device Deployment Completed ===' -Level 'SUCCESS'
Write-DeploymentLog -Message "Detailed log: $($script:TextLogPath)" -Level 'INFO'
Write-DeploymentLog -Message "JSON stream: $($script:JsonLogPath)" -Level 'DEBUG'
Write-DeploymentLog -Message "Transcript: $($script:TranscriptPath)" -Level 'DEBUG'

Show-DeploymentNotification -Title 'Deployment complete' -Body 'Your device is ready. Review the console for details.' -Severity 'Success'

$totalTime = (Get-Date) - $script:DeploymentStart
$durationMinutes = [math]::Round($totalTime.TotalMinutes, 2)
Write-Host "`n=== Deployment Summary ===" -ForegroundColor Green
Write-Host "Log file: $($script:TextLogPath)" -ForegroundColor Green
Write-Host "JSON log: $($script:JsonLogPath)" -ForegroundColor Green
Write-Host "Transcript: $($script:TranscriptPath)" -ForegroundColor Green
Write-Host "Total time: $durationMinutes minute(s)" -ForegroundColor Green
Write-Host "=========================" -ForegroundColor Green
Write-Host ''

Stop-Transcript | Out-Null

Write-DeploymentLog -Message 'Awaiting user acknowledgement (press any key)...' -Level 'INFO'
Show-DeploymentNotification -Title 'Review results' -Body 'Press any key in the window to close it when you are done.'

Write-Host 'Press any key to exit...' -ForegroundColor Gray
[void][System.Console]::ReadKey($true)