# Define account details
$Username = "DenkoAdmin"
$Password = "Secure@12345" 

# Convert password to secure string
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

# Check if user already exists
if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {
    Write-Host "User '$Username' already exists."
} else {
    # Create the new local user
    New-LocalUser -Name $Username -Password $SecurePassword -FullName "DenkoAdmin" -Description "DenkoAdmin" -PasswordNeverExpires -AccountNeverExpires

    # Add the user to the Administrators group
    Add-LocalGroupMember -Group "Administrators" -Member $Username

    Write-Host "User '$Username' has been created and added to the Administrators group."
}
