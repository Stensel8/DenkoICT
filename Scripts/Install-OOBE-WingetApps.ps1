
<#
Revision: 2.0.0
Author: Sten Tijhuis (Stensel8)
Date: 15/09/2025
Purpose/Change: Refactored and moved to Scripts folder. See original credits below.
.SYNOPSIS
    Installs essential applications and components during Windows OOBE (Out-of-Box Experience).

.DESCRIPTION
    This script automates the installation of essential software components during device provisioning:
    - NuGet Package Provider
    - Visual C++ Redistributable
    - PowerShell 7 (with architecture detection)
    - WinGet applications including Microsoft Copilot 365, EdgeWebView2Runtime, and Company Portal
    
    The script detects system architecture (ARM64 vs x64) and installs appropriate versions.
    All activities are logged with timestamps for troubleshooting.

.PARAMETER LogPath
    Optional. Specifies the path for the transcript log file. 
    Default: "C:\Temp\AP-Provision-Device-Phase-{timestamp}-{computername}.log"

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    Transcript log file containing detailed installation progress and results.
    Default location: "C:\Temp\AP-Provision-Device-Phase-{timestamp}-{computername}.log"

.NOTES
    Version:        2.0.0
    Author:         Sten Tijhuis
    Creation Date:  15/09/2025
    Last Modified:  15/09/2025
    Purpose/Change: Enhanced error handling, improved documentation, and code cleanup.
    GitHub:         https://github.com/Stensel8/DenkoICT

.EXAMPLE
    PS C:\> .\Install-OOBE-WingetApps.ps1
    
    Runs the complete OOBE application installation process with default settings.

.EXAMPLE
    PS C:\> .\Install-OOBE-WingetApps.ps1 -LogPath "C:\Custom\MyLog.log"
    
    Runs the installation with a custom log file path.

.LINK
    https://github.com/Stensel8/DenkoICT

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath = "C:\Temp\AP-Provision-Device-Phase-$((Get-Date).ToString('yyyyMMdd-HHmmss'))-$($ENV:COMPUTERNAME).log"
)

#----------------------------------------------------------------------------[ Begin Declarations ]----------------------------------------------------------
# Start a transcript to log the session; discard output to avoid unused-variable warnings.
Start-Transcript -Path $LogPath -Append -Force | Out-Null

#---------------------------------------------------------------------------[ End Initialisations ]--------------------------------------------------------



#-----------------------------------------------------------------------------[ Begin Functions ]------------------------------------------------------------

function Get-MSIProperties {
    <#
    .SYNOPSIS
        Gets the properties of an MSI file.
    .DESCRIPTION
        Extracts MSI properties like ProductCode, ProductVersion, and ProductName using Windows Installer COM object.
    .PARAMETER MSI
        Path to the MSI file to analyze.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$MSI
    )
    
    try {
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $database = $windowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $windowsInstaller, @($MSI, 0))
        
        $query = "SELECT Property, Value FROM Property"
        $propView = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, ($query))
        $propView.GetType().InvokeMember("Execute", "InvokeMethod", $null, $propView, $null) | Out-Null
        
        $msiProps = @()
        $propRecord = $propView.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $propView, $null)
        
        while ($null -ne $propRecord) {
            $property = $propRecord.GetType().InvokeMember("StringData", "GetProperty", $null, $propRecord, 1)
            $value = $propRecord.GetType().InvokeMember("StringData", "GetProperty", $null, $propRecord, 2)
            
            $msiProps += [PSCustomObject]@{
                MSIProperty = $property
                Value = $value
            }
            
            $propRecord = $propView.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $propView, $null)
        }
        
        # Clean up COM objects
        $propView.GetType().InvokeMember("Close", "InvokeMethod", $null, $propView, $null) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($windowsInstaller) | Out-Null
        
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Successfully extracted MSI properties from: $MSI"
        return $msiProps
    } catch {
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [ERROR] Failed to extract MSI properties: $($_.Exception.Message)"
        throw
    }
}

function Install-Nuget {
    <#
    .SYNOPSIS
        Installs the NuGet package provider.
    .DESCRIPTION
        Installs NuGet package provider required for PowerShell package management.
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Installing NuGet package provider..."
        
        # Check if NuGet is already installed
        $nugetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        
        if (-not $nugetProvider) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
            Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] NuGet package provider installed successfully"
        }
        else {
            Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] NuGet package provider already installed"
        }
    }
    catch {
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [ERROR] Failed to install NuGet package provider: $($_.Exception.Message)"
        throw
    }
}

function Install-PowerShell7MSI {
    <#
    .SYNOPSIS
        Installs PowerShell 7 from MSI package.
    .DESCRIPTION
        Installs PowerShell 7 using msiexec with predefined arguments for automation and logging.
    .PARAMETER MSIPath
        Path to the PowerShell 7 MSI installer file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$MSIPath
    )

    try {
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Extracting MSI properties..."
        $msiProperties = Get-MSIProperties -MSI $MSIPath
        
        $ProductCode = $msiProperties | Where-Object MSIProperty -eq "ProductCode" | Select-Object -ExpandProperty Value
        $ProductVersion = $msiProperties | Where-Object MSIProperty -eq "ProductVersion" | Select-Object -ExpandProperty Value  
        $ProductName = $msiProperties | Where-Object MSIProperty -eq "ProductName" | Select-Object -ExpandProperty Value
        
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] MSI Product: $ProductName v$ProductVersion (ProductCode: $ProductCode)"
    }
    catch {
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [ERROR] Getting MSI properties failed: $($_.Exception.Message)"
        throw
    }
    
    # Define MSI exit codes for better error handling
    $MSIExitCodes = @{
        0    = @{Name = "ERROR_SUCCESS"; Description = "Action completed successfully."}
        1602 = @{Name = "ERROR_INSTALL_USEREXIT"; Description = "User cancelled installation."}
        1603 = @{Name = "ERROR_INSTALL_FAILURE"; Description = "Fatal error during installation."}
        1608 = @{Name = "ERROR_UNKNOWN_PROPERTY"; Description = "Unknown property."}
        1609 = @{Name = "ERROR_INVALID_HANDLE_STATE"; Description = "Handle is in an invalid state."}
        1614 = @{Name = "ERROR_PRODUCT_UNINSTALLED"; Description = "Product is uninstalled."}
        1618 = @{Name = "ERROR_INSTALL_ALREADY_RUNNING"; Description = "Another installation is already in progress."}
        1619 = @{Name = "ERROR_INSTALL_PACKAGE_OPEN_FAILED"; Description = "Installation package could not be opened."}
        1620 = @{Name = "ERROR_INSTALL_PACKAGE_INVALID"; Description = "Installation package is invalid."}
        1624 = @{Name = "ERROR_INSTALL_TRANSFORM_FAILURE"; Description = "Error applying transforms."}
        1635 = @{Name = "ERROR_PATCH_PACKAGE_OPEN_FAILED"; Description = "Patch package could not be opened."}
        1636 = @{Name = "ERROR_PATCH_PACKAGE_INVALID"; Description = "Patch package is invalid."}
        1638 = @{Name = "ERROR_PRODUCT_VERSION"; Description = "Another version is already installed."}
        1639 = @{Name = "ERROR_INVALID_COMMAND_LINE"; Description = "Invalid command line argument."}
        1640 = @{Name = "ERROR_INSTALL_REMOTE_DISALLOWED"; Description = "Installation from Terminal Server not permitted."}
        1641 = @{Name = "ERROR_SUCCESS_REBOOT_INITIATED"; Description = "Installer has initiated a reboot."}
        1644 = @{Name = "ERROR_INSTALL_TRANSFORM_REJECTED"; Description = "Customizations not permitted by policy."}
        3010 = @{Name = "ERROR_SUCCESS_REBOOT_REQUIRED"; Description = "Reboot required to complete install."}
    }

    try {
        $logFile = Join-Path -Path (Split-Path $MSIPath -Parent) -ChildPath "PowerShellMSI.log"
        $msiArguments = @(
            "/i", "`"$MSIPath`""
            "/qn"
            "ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1"
            "ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1" 
            "ENABLE_PSREMOTING=1"
            "REGISTER_MANIFEST=1"
            "USE_MU=1"
            "ENABLE_MU=1"
            "ADD_PATH=1"
            "/l*v", "`"$logFile`""
        )
        
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Starting MSI installation for $ProductName version $ProductVersion..."
        $result = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -Wait -PassThru -NoNewWindow
        
        $exitCodeInfo = $MSIExitCodes[$result.ExitCode]
        if ($exitCodeInfo) {
            $exitCodeName = $exitCodeInfo.Name
            $exitCodeDescription = $exitCodeInfo.Description
        } else {
            $exitCodeName = "UNKNOWN_ERROR"
            $exitCodeDescription = "Unknown exit code: $($result.ExitCode)"
        }
        
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] MSI installation completed with exit code: $($result.ExitCode) ($exitCodeName)"
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Description: $exitCodeDescription"

        # Handle success cases
        if ($result.ExitCode -eq 0 -or $result.ExitCode -eq 1707) {
            Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] $ProductName version $ProductVersion installed successfully"
            return $true
        }
        # Handle reboot required cases  
        elseif ($result.ExitCode -eq 3010 -or $result.ExitCode -eq 1641) {
            Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [WARNING] $ProductName version $ProductVersion installed successfully but requires reboot"
            return $true
        }
        # Handle failure cases
        else {
            Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [ERROR] MSI installation failed for $ProductName version $ProductVersion"
            return $false
        }
    }
    catch {
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [ERROR] Failed to run MSI installation for $ProductName version ${ProductVersion}: $($_.Exception.Message)"
        return $false
    }

}


function Install-VcRedistributable {
    <#
    .SYNOPSIS
        Installs Visual C++ Redistributable packages.
    .DESCRIPTION
        Installs Visual C++ Redistributable with configurable silent installation options.
    .PARAMETER InstallerPath
        Path to the Visual C++ Redistributable installer executable.
    .PARAMETER Silent
        Switch to enable silent installation mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$InstallerPath,

        [Parameter(Mandatory = $false)]
        [switch]$Silent
    )

    try {
        $arguments = "/install"
        if ($Silent) {
            $arguments += " /quiet /norestart"
        }

        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Installing Visual C++ Redistributable from: $InstallerPath"
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Silent mode: $Silent"
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Installation arguments: $arguments"

        $process = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Installation completed with exit code: $($process.ExitCode)"
        
        # Common Visual C++ Redistributable exit codes
        switch ($process.ExitCode) {
            0 { 
                Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Visual C++ Redistributable installed successfully"
                return $true
            }
            3010 { 
                Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [WARNING] Installation successful but reboot required"
                return $true
            }
            5100 { 
                Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] A newer version is already installed"
                return $true
            }
            default {
                Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [ERROR] Installation failed with exit code: $($process.ExitCode)"
                return $false
            }
        }
    }
    catch {
        Write-Output "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [ERROR] Failed to start installation process: $($_.Exception.Message)"
        return $false
    }
}




#-----------------------------------------------------------------------------[ End Functions ]------------------------------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------[ Begin Code ]-----------------------------------------------------------------------------------------------------------------------------------------



#---------------------------------[ Install Nuget ]---------------------------------
try {
    Write-Output "[$((Get-Date).TimeofDay)] [INFO] Attempting to install Nuget provider."
    Install-Nuget
}
catch {
    <#Do this if a terminating exception happens#>
    Write-Output "[$((Get-Date).TimeofDay)] [ERROR] Installing Nuget provider failed"
}




#---------------------------------[ Install Visual C++ Redistributable ]---------------------------------
try {
    Write-Output "[$((Get-Date).TimeofDay)] [INFO] Installing Visual C++ Redistributable"
    Install-VcRedistributable -InstallerPath ".\vc_redist.x64.exe" -Silent  -ErrorAction Continue
    Write-Output "[$((Get-Date).TimeofDay)] [INFO] Installed Visual C++ Redistributable"
}
catch {
    <#Do this if a terminating exception happens#>
    write-Output "[$((Get-Date).TimeofDay)] [ERROR] Installing Visual C++ Redistributable Failed"
}



#---------------------------------[ Install PowerShell 7 ]---------------------------------
If ($Arch -eq "ARM64") {
        <# Action to perform if the condition is true #>
        try {
        Write-Output "[$((Get-Date).TimeofDay)] [INFO] Attempting to install PowerShell 7 ARM64"
        Install-PowerShell7MSI -MSIPath .\AP-Provision\PowerShell-7.5.2-win-arm64.msi
        Write-Output "[$((Get-Date).TimeofDay)] [INFO] PowerShell 7 install ran."
    }catch {
        Write-Output "[$((Get-Date).TimeofDay)] [ERROR] Installing PowerShell 7 Failed"
    }
}else{
    try {
        Write-Output "[$((Get-Date).TimeofDay)] [INFO] Attempting to install PowerShell 7 x64"
        Install-PowerShell7MSI -MSIPath .\AP-Provision\PowerShell-7.5.2-win-x64.msi
        Write-Output "[$((Get-Date).TimeofDay)] [INFO] PowerShell 7 install ran."
    }catch {
        Write-Output "[$((Get-Date).TimeofDay)] [ERROR] Installing PowerShell 7 Failed"
    }
}



#---------------------------------[ Install Winget Apps ]---------------------------------

try {
    #Set architecture variables
    $Arch = $env:PROCESSOR_ARCHITECTURE
    If($Arch -eq "ARM64"){
        Write-Output "[$((Get-Date).TimeofDay)] [INFO] Running on 64-bit ARM architecture"
            $Ids = @(
            #9WZDNCRD29V9 is Microsoft CoPilot 365
            '9WZDNCRD29V9',
            'Microsoft.VCRedist.2015+.arm64',
            'Microsoft.EdgeWebView2Runtime',
            'Microsoft.CompanyPortal'
            )
    }else{
        Write-Output "[$((Get-Date).TimeofDay)] [INFO] Architecture is X64"
            $Ids = @(
            #9WZDNCRD29V9 is Microsoft CoPilot 365
            '9WZDNCRD29V9',
            'Microsoft.VCRedist.2015+.x64',
            'Microsoft.EdgeWebView2Runtime',
            'Microsoft.CompanyPortal'
            )

    }

    write-Output "[$((Get-Date).TimeofDay)] [INFO] Winget Steps - Setting PS repo to trusted."
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -SourceLocation "https://www.powershellgallery.com/api/v2" -ErrorAction Continue

    write-Output "[$((Get-Date).TimeofDay)] [INFO] Winget Steps - Setting Execution Policy to Bypass for Process."
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Force -Scope Process -ErrorAction Continue

    write-Output "[$((Get-Date).TimeofDay)] [INFO] Winget Steps - Installing Module."
    Install-Module -Name Microsoft.WinGet.Client -Force -Scope AllUsers -Repository PSGallery
    write-Output "[$((Get-Date).TimeofDay)] [INFO] Winget Steps - Installed Module. Now to apps."
    

    #I did not need to repair winget. A lot of blogs say to do this. But I think it is fixed in latest Windows 11 builds.
    #write-Output "[$((Get-Date).TimeofDay)] [INFO] Repairing Winget package manager."  
    #Repair-WinGetPackageManager -Force -Latest -ErrorAction Continue
    #write-Output "[$((Get-Date).TimeofDay)] [INFO] Winget package manager repair completed."
        
        
    foreach ($id in $Ids) {
        #From this blog: https://powershellisfun.com/2025/05/16/deploy-and-automatically-update-winget-apps-in-intune-using-powershell-without-remediation-or-3rd-party-tools/?noamp=available
        #PowerShell 7 is required. 5.1 Gave an error: This cmdlet is not supported in Windows PowerShell. This is a known issue with 5.1 and running in system context.

        $PS7Proc = Start-Process -FilePath "C:\Program Files\PowerShell\7\pwsh.exe" -argumentList "-MTA -Command `"Install-WinGetPackage -Id $Id -Mode Silent -Scope SystemOrUnknown -ErrorAction Continue`"" -Wait -NoNewWindow -PassThru
        Write-Output "[$((Get-Date).TimeofDay)] [INFO] Installed Winget package with ID: $Id. Exit code: $($PS7Proc.ExitCode)"
    }   


}catch {
    <#Do this if a terminating exception happens#>
    write-Output "[$((Get-Date).TimeofDay)] [ERROR] Installing Winget Apps Failed"
}

