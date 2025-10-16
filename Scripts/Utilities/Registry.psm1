#requires -Version 5.1

function Set-RegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        $Value,
        [ValidateSet('String','DWord','Binary','ExpandString','MultiString','QWord')]
        [string]$Type = 'String'
    )
    if (-not (Test-Path $Path)) {
        $null = New-Item -Path $Path -Force -ErrorAction Stop
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
}

function Set-IntuneSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,
        [string]$Version = '1.0.0'
    )
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\DenkoICT\Intune' -Name $AppName -Value $Version
}

function Set-DeploymentStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StepName,
        [Parameter(Mandatory)]
        [ValidateSet('Success', 'Failed', 'Skipped', 'Running')]
        [string]$Status,
        [string]$ErrorMessage,
        [int]$ExitCode,
        [string]$Version
    )
    $key = "HKLM:\SOFTWARE\DenkoICT\Deployment\Steps\$StepName"
    if (-not (Test-Path $key)) {
        $null = New-Item -Path $key -Force -ErrorAction Stop
    }
    Set-ItemProperty -Path $key -Name 'Status' -Value $Status -Type String -Force
    Set-ItemProperty -Path $key -Name 'Timestamp' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Type String -Force
    if ($ExitCode) { Set-ItemProperty -Path $key -Name 'ExitCode' -Value $ExitCode -Type DWord -Force }
    if ($ErrorMessage) { Set-ItemProperty -Path $key -Name 'ErrorMessage' -Value $ErrorMessage -Type String -Force }
    if ($Version) { Set-ItemProperty -Path $key -Name 'Version' -Value $Version -Type String -Force }
}

function Get-DeploymentStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][string]$StepName)
    $key = "HKLM:\SOFTWARE\DenkoICT\Deployment\Steps\$StepName"
    if (-not (Test-Path $key)) { return $null }
    $status = Get-ItemProperty -Path $key -ErrorAction Stop
    return [PSCustomObject]@{
        StepName = $StepName
        Status = $status.Status
        Timestamp = $status.Timestamp
        ExitCode = if ($status.PSObject.Properties['ExitCode']) { $status.ExitCode } else { $null }
        ErrorMessage = if ($status.PSObject.Properties['ErrorMessage']) { $status.ErrorMessage } else { $null }
        Version = if ($status.PSObject.Properties['Version']) { $status.Version } else { $null }
    }
}

Export-ModuleMember -Function @(
    'Set-RegistryValue', 'Set-IntuneSuccess',
    'Set-DeploymentStatus', 'Get-DeploymentStatus'
)