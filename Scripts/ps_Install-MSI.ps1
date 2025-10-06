<#PSScriptInfo

.VERSION 3.0.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows MSI Installer Deployment

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Original version by Jeffery Field
[Version 2.0.0] - Refactored and moved to Scripts folder
[Version 3.0.0] - Complete modernization: Added PSScriptInfo, proper error handling, centralized logging, admin checks, removed global variables
#>

#requires -Version 5.1

<#
.SYNOPSIS
    Installs MSI packages with detailed logging and error handling.

.DESCRIPTION
    Automated MSI installation script that extracts MSI properties, installs the package,
    and provides detailed exit code interpretation. Integrates with DenkoICT logging framework.

    Features:
    - Automatic MSI property extraction
    - Detailed installation logging
    - Exit code interpretation
    - Integration with Intune deployment tracking
    - Automatic log rotation

.PARAMETER MSIPath
    Path to the MSI file to install. If not specified and only one MSI exists in the script directory, it will be used automatically.

.PARAMETER LogPath
    Path for the MSI installation log file. If not specified, logs to C:\DenkoICT\Logs

.PARAMETER InstallArguments
    Additional MSI installation arguments (e.g., INSTALLDIR="C:\Custom\Path").
    Default: Silent installation with verbose logging and no reboot.

.PARAMETER SkipLogging
    Skip transcript logging.

.EXAMPLE
    .\ps_Install-MSI.ps1
    Automatically detects and installs the MSI in the current directory.

.EXAMPLE
    .\ps_Install-MSI.ps1 -MSIPath "C:\Installers\MyApp.msi"
    Installs a specific MSI file.

.EXAMPLE
    .\ps_Install-MSI.ps1 -InstallArguments @('INSTALLDIR="C:\Custom\Path"', 'ALLUSERS=1')
    Installs with custom arguments.

.NOTES
    Version      : 3.0.0
    Created by   : Sten Tijhuis (based on original by Jeffery Field)
    Company      : Denko ICT
    Requires     : Admin rights, MSI file

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            throw "MSI file not found: $_"
        }
        if ($_ -notmatch '\.msi$') {
            throw "File must be an MSI: $_"
        }
        $true
    })]
    [string]$MSIPath,

    [Parameter(Mandatory = $false)]
    [string]$LogPath,

    [Parameter(Mandatory = $false)]
    [string[]]$InstallArguments = @(),

    [switch]$SkipLogging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load custom functions
$functionsPath = Join-Path $PSScriptRoot 'ps_Custom-Functions.ps1'
if (-not (Test-Path $functionsPath)) {
    Write-Error "Required functions file not found: $functionsPath"
    exit 1
}
. $functionsPath

# Initialize logging
if (-not $SkipLogging) {
    $Global:DenkoConfig.LogName = "$($MyInvocation.MyCommand.Name).log"
    Start-Logging
}

try {
    Assert-AdminRights

    Write-Log "=== MSI Installation Started ===" -Level Info

    # ============================================================================ #
    # Detect MSI file
    # ============================================================================ #

    if (-not $MSIPath) {
        Write-Log "No MSI path specified, searching current directory..." -Level Info
        $msiFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.msi' -ErrorAction SilentlyContinue

        if ($msiFiles.Count -eq 0) {
            throw "No MSI files found in $PSScriptRoot"
        } elseif ($msiFiles.Count -gt 1) {
            throw "Multiple MSI files found in $PSScriptRoot. Please specify -MSIPath parameter."
        }

        $MSIPath = $msiFiles[0].FullName
    }

    Write-Log "MSI file: $MSIPath" -Level Info

    # ============================================================================ #
    # Extract MSI properties
    # ============================================================================ #

    Write-Log "Extracting MSI properties..." -Level Info

    try {
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $database = $windowsInstaller.GetType().InvokeMember(
            "OpenDatabase",
            "InvokeMethod",
            $null,
            $windowsInstaller,
            @($MSIPath, 0)  # 0 = read-only
        )

        $query = "SELECT Property, Value FROM Property"
        $view = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, $query)
        $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null) | Out-Null

        $msiProperties = @{}
        $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)

        while ($null -ne $record) {
            $property = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
            $value = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 2)
            $msiProperties[$property] = $value
            $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
        }

        $view.GetType().InvokeMember("Close", "InvokeMethod", $null, $view, $null) | Out-Null

        # Log key properties
        if ($msiProperties.ContainsKey('ProductName')) {
            Write-Log "Product Name: $($msiProperties['ProductName'])" -Level Info
        }
        if ($msiProperties.ContainsKey('ProductVersion')) {
            Write-Log "Product Version: $($msiProperties['ProductVersion'])" -Level Info
        }
        if ($msiProperties.ContainsKey('Manufacturer')) {
            Write-Log "Manufacturer: $($msiProperties['Manufacturer'])" -Level Info
        }

    } catch {
        Write-Log "Failed to extract MSI properties: $_" -Level Warning
        $msiProperties = @{}
    }

    # ============================================================================ #
    # Prepare log file path
    # ============================================================================ #

    if (-not $LogPath) {
        $msiFileName = [System.IO.Path]::GetFileNameWithoutExtension($MSIPath)
        $logFileName = "${msiFileName}_Install.log"
        $LogPath = Join-Path 'C:\DenkoICT\Logs' $logFileName
    }

    Write-Log "MSI log file: $LogPath" -Level Info

    # ============================================================================ #
    # Build MSI arguments
    # ============================================================================ #

    $msiArgs = @(
        '/i'
        "`"$MSIPath`""
        '/qn'          # Silent install
        '/norestart'   # Don't restart
        "/L*V `"$LogPath`""  # Verbose logging
    )

    # Add custom arguments if provided
    if ($InstallArguments.Count -gt 0) {
        $msiArgs += $InstallArguments
        Write-Log "Custom arguments: $($InstallArguments -join ' ')" -Level Info
    }

    Write-Log "Installation command: msiexec.exe $($msiArgs -join ' ')" -Level Info

    # ============================================================================ #
    # Install MSI
    # ============================================================================ #

    Write-Log "Starting MSI installation..." -Level Info
    $startTime = Get-Date

    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow

    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    $exitCode = $process.ExitCode

    Write-Log "Installation completed in $([math]::Round($duration, 1)) seconds" -Level Info
    Write-Log "Exit code: $exitCode" -Level Info

    # ============================================================================ #
    # Interpret exit code
    # ============================================================================ #

    $exitCodeInfo = Get-MSIExitCodeDescription -ExitCode $exitCode

    Write-Log "Status: $($exitCodeInfo.Name)" -Level Info
    Write-Log "Description: $($exitCodeInfo.Description)" -Level Info

    # Determine overall status
    $overallStatus = 'Success'
    $finalExitCode = 0

    if ($exitCode -eq 0 -or $exitCode -eq 1707) {
        Write-Log "MSI installation completed successfully" -Level Success
        $overallStatus = 'Success'
        $finalExitCode = 0

        # Record success in Intune registry
        $productName = if ($msiProperties.ContainsKey('ProductName')) {
            $msiProperties['ProductName']
        } else {
            [System.IO.Path]::GetFileNameWithoutExtension($MSIPath)
        }

        $productVersion = if ($msiProperties.ContainsKey('ProductVersion')) {
            $msiProperties['ProductVersion']
        } else {
            '1.0.0'
        }

        Set-IntuneSuccess -AppName $productName -Version $productVersion

    } elseif ($exitCode -eq 3010 -or $exitCode -eq 1641) {
        Write-Log "MSI installation succeeded, but a reboot is required" -Level Warning
        $overallStatus = 'Reboot'
        $finalExitCode = 3010

    } else {
        Write-Log "MSI installation failed" -Level Error
        $overallStatus = 'Error'
        $finalExitCode = $exitCode
    }

    Write-Log "=== MSI Installation Complete ===" -Level Success
    Write-Log "Final Status: $overallStatus" -Level Info

    exit $finalExitCode

} catch {
    Write-Log "MSI installation failed with exception: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 9999
} finally {
    if (-not $SkipLogging) {
        Stop-Logging
    }
}
