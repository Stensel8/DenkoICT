# List of unwanted provisioned apps to remove (Windows 11)
$AppsToRemove = @(
    "king.com.CandyCrushSaga",
    "king.com.CandyCrushSodaSaga",
    "Microsoft.BingNews",
    #"Microsoft.GamingApp",                   # Xbox app in Win11
    #"Microsoft.Xbox.TCUI",
    #"Microsoft.XboxGameOverlay",
    #"Microsoft.XboxGamingOverlay",
    #"Microsoft.XboxIdentityProvider",
    #"Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.ZuneMusic",                  # Groove Music
    #"Microsoft.ZuneVideo",                  # Movies & TV
    #"Microsoft.People",
    #"Microsoft.OneConnect",
    #"Microsoft.Todos",                      # Microsoft To Do
    #"Microsoft.WindowsMaps",
    #"Microsoft.MicrosoftStickyNotes",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.SkypeApp",
    "Microsoft.MicrosoftOfficeHub",         # Office promotion app
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",                 # Tips app
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.MixedReality.Portal",
    "Microsoft.ClipChamp"
)

# Remove provisioned packages (for all new users)
foreach ($App in $AppsToRemove) {
    Write-Output "Removing provisioned package: $App"
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*$App*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

# Optional: Remove already-installed apps for all users (e.g. for testing or admin users)
foreach ($App in $AppsToRemove) {
    Write-Output "Removing installed app: $App"
    Get-AppxPackage -AllUsers | Where-Object Name -like "*$App*" | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
}
