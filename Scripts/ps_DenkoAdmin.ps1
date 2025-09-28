<#PSScriptInfo

.VERSION 1.1.0

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows LocalUser Administrator Deployment Security

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.1.0] - Added ShouldProcess support, centralized logging, and admin validation helpers.
[Version 1.0.1] - Improved password handling and logging.
[Version 1.0.0] - Initial Release. Creates local administrator account for Denko ICT management.
#>

<#
.SYNOPSIS
    Creates a local administrator account for Denko ICT management.

.DESCRIPTION
    This script creates a local user account named "DenkoAdmin" with administrator privileges.
    The account is configured with password never expires and account never expires settings.
    If the account already exists, the script will skip creation and notify the user.

.PARAMETER Username
    The username for the administrator account. Default: "DenkoAdmin"

.PARAMETER Password
    The password for the administrator account. Should be provided as SecureString in production.
    Default: Uses a predefined password (not recommended for production)

.PARAMETER ResetExistingPassword
    When specified, resets the password for an existing account using the supplied credential.

.EXAMPLE
    .\ps_DenkoAdmin.ps1
    
    Creates the DenkoAdmin account with default settings.

.EXAMPLE
    $securePass = Read-Host "Enter Password" -AsSecureString
    .\ps_DenkoAdmin.ps1 -Password $securePass
    
    Creates the DenkoAdmin account with a custom secure password.

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    None. Displays status messages to the console.

.NOTES
    Version      : 1.0.1
    Created by   : Sten Tijhuis
    Company      : Denko ICT
    
    SECURITY WARNING: This script contains a hardcoded password for demonstration purposes.
    In production environments, use secure password management methods such as:
    - Azure Key Vault
    - Windows Credential Manager
    - Encrypted configuration files
    - Runtime password generation
    
    Requires administrative privileges to run successfully.

.LINK
    Project Site: https://github.com/Stensel8/DenkoICT
#>

#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Username = "DenkoAdmin",
    
    [Parameter(Mandatory = $false)]
    [System.Security.SecureString]$Password,

    [Parameter(Mandatory = $false)]
    [switch]$ResetExistingPassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commonModule = Join-Path -Path $PSScriptRoot -ChildPath 'DenkoICT.Common.ps1'
if (-not (Test-Path -Path $commonModule)) {
    throw "Unable to locate shared helper module at $commonModule"
}

. $commonModule

try {
    if (-not $Password) {
        Write-DenkoLog -Message 'WARNING: Using default password. This should only be used for testing!' -Level Warning
        $Password = ConvertTo-SecureString 'Secure@12345' -AsPlainText -Force
    }

    Assert-DenkoAdministrator

    Write-Verbose "Checking if user '$Username' exists..."
    $existingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue

    if ($existingUser) {
        Write-DenkoLog -Message "User '$Username' already exists." -Level Warning

        if ($ResetExistingPassword) {
            if ($PSCmdlet.ShouldProcess("Local user '$Username'", 'Reset local administrator password')) {
                Set-LocalUser -Name $Username -Password $Password
                Write-DenkoLog -Message "Password reset for user '$Username'." -Level Success
            }
        } else {
            Write-Verbose 'ResetExistingPassword not specified; leaving existing credentials unchanged.'
        }
    } else {
        Write-Verbose "Creating new local user '$Username'..."

        if ($PSCmdlet.ShouldProcess("Local user '$Username'", 'Create local administrator account')) {
            $userParams = @{
                Name                      = $Username
                Password                  = $Password
                FullName                  = 'Denko ICT Administrator'
                Description               = 'Administrative account for Denko ICT management'
                PasswordNeverExpires      = $true
                AccountNeverExpires       = $true
                UserMayNotChangePassword  = $false
            }

            New-LocalUser @userParams
            Write-DenkoLog -Message "Created local user '$Username'." -Level Success
        }
    }

    $isMember = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$Username" }
    if (-not $isMember) {
        if ($PSCmdlet.ShouldProcess("Administrators group", "Add '$Username' as member")) {
            Add-LocalGroupMember -Group 'Administrators' -Member $Username
            Write-DenkoLog -Message "Added '$Username' to the Administrators group." -Level Success
        }
    } else {
        Write-Verbose "'$Username' is already a member of the Administrators group."
    }

    if ($PSCmdlet.ShouldProcess('Application Event Log', 'Record DenkoAdmin account activity')) {
        $logMessage = "DenkoAdmin account processed on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') by $env:USERNAME"
        Write-EventLog -LogName Application -Source 'DenkoICT' -EventID 1000 -Message $logMessage -ErrorAction SilentlyContinue
        Write-Verbose 'Audit entry written to Application log.'
    }

    $finalCheck = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$Username" }
    if ($finalCheck) {
        Write-DenkoLog -Message "Verified: '$Username' has administrator privileges." -Level Success
    } else {
        Write-DenkoLog -Message "Warning: '$Username' might not have full administrator privileges." -Level Warning
    }

} catch {
    Write-DenkoLog -Message "Failed to create or modify user: $_" -Level Error
    exit 1
}