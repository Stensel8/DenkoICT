<#PSScriptInfo

.VERSION 1.0.1

.AUTHOR Sten Tijhuis

.COMPANYNAME Denko ICT

.TAGS PowerShell Windows LocalUser Administrator Deployment Security

.PROJECTURI https://github.com/Stensel8/DenkoICT

.RELEASENOTES
[Version 1.0.0] - Initial Release. Creates local administrator account for Denko ICT management.
[Version 1.0.1] - Improved password handling and logging.
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

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Username = "DenkoAdmin",
    
    [Parameter(Mandatory = $false)]
    [System.Security.SecureString]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Level = 'Info'
    )
    
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        default { 'White' }
    }
    
    Write-Host $Message -ForegroundColor $color
}

try {
    # If no password provided, use default (NOT RECOMMENDED FOR PRODUCTION)
    if (-not $Password) {
        Write-ColorOutput "WARNING: Using default password. This should only be used for testing!" -Level 'Warning'
        $Password = ConvertTo-SecureString "Secure@12345" -AsPlainText -Force
    }
    
    # Check if running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script requires administrator privileges. Please run as administrator."
    }
    
    Write-Verbose "Checking if user '$Username' exists..."
    
    # Check if user already exists
    $existingUser = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    
    if ($existingUser) {
        Write-ColorOutput "User '$Username' already exists." -Level 'Warning'
        
        # Optional: Update the password for existing user
        $updatePassword = Read-Host "Do you want to update the password? (Y/N)"
        if ($updatePassword -eq 'Y') {
            Set-LocalUser -Name $Username -Password $Password
            Write-ColorOutput "Password updated for user '$Username'." -Level 'Success'
        }
    } else {
        Write-Verbose "Creating new local user '$Username'..."
        
        # Create the new local user
        $userParams = @{
            Name                     = $Username
            Password                 = $Password
            FullName                = "Denko ICT Administrator"
            Description             = "Administrative account for Denko ICT management"
            PasswordNeverExpires    = $true
            AccountNeverExpires     = $true
            UserMayNotChangePassword = $false
        }
        
        New-LocalUser @userParams
        
        Write-Verbose "Adding user to Administrators group..."
        
        # Add the user to the Administrators group
        Add-LocalGroupMember -Group "Administrators" -Member $Username
        
        Write-ColorOutput "User '$Username' has been created and added to the Administrators group." -Level 'Success'
        
        # Log the creation
        $logMessage = "DenkoAdmin account created on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') by $env:USERNAME"
        Write-EventLog -LogName Application -Source "DenkoICT" -EventID 1000 -Message $logMessage -ErrorAction SilentlyContinue
    }
    
    # Verify the user is in Administrators group
    $isAdmin = Get-LocalGroupMember -Group "Administrators" | Where-Object { $_.Name -like "*$Username" }
    if ($isAdmin) {
        Write-ColorOutput "Verified: '$Username' has administrator privileges." -Level 'Success'
    } else {
        Write-ColorOutput "Warning: '$Username' might not have full administrator privileges." -Level 'Warning'
    }
    
} catch {
    Write-ColorOutput "Failed to create or modify user: $_" -Level 'Error'
    exit 1
}