# Modern Device Deployment - Denko-ICT

<p align="left">
	<a href="README.md">
		<img src="https://img.shields.io/badge/Switch%20to-English-blue?style=for-the-badge" alt="Switch to English" />
	</a>
</p>

[![Codacy Security Scan](https://github.com/Stensel8/DenkoICT/actions/workflows/codacy.yml/badge.svg?branch=main)](https://github.com/Stensel8/DenkoICT/actions/workflows/codacy.yml)

[![PSScriptAnalyzer](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml)

## Waarom dit project bestaat
Deze repository vormt een onderdeel van mijn stage bij Denko ICT. Ik kreeg de taak om het automatiseringsproces en het apparaat uitrol proces te herzien. Tijdens deze evaluatie zag ik mogelijkheden om handmatige configuratietaken verder te automatiseren met moderne tooling. Met deze eigentijdse automatiseringstoolkit wil ik aantonen dat Windows 11 Pro-apparaten nog sneller, veiliger en consistenter inzetbaar zijn, door gebruik te maken van de nieuwste beschikbare technologieën.

Ik heb deze GitHub-repository zelf opgezet als centrale plek om technische documentatie en scripts te kunnen opslaan.

![Expected Result](Docs/Expected_Result.png)

## Wat deze repository oplevert
- Een PowerShell 7-framework dat aansluit op de actuele Microsoft-richtlijnen voor endpointbeheer
- Geen afhankelijkheid van verouderde technologieën zoals Microsoft MDT, klassieke batch/CMD-scripts, VBScript, PowerShell 2.0 of WMIC
- Geïntegreerde leveranciers-tools voor Dell (Dell Command | Update CLI) en HP (HP Image Assistant & HP CMSL) met automatische driver-updates
- Registry-gebaseerde statusmonitoring en rapportage
- Deployment gaat door zelfs als individuele stappen falen
- Herbruikbare scripts voor applicatie-installatie, driverbeheer, devicevoorbereiding en algemeen onderhoud
- Gecentraliseerde logging en foutafhandeling met gedetailleerde exit code interpretatie
- Documentatie waarmee collega's dezelfde moderne aanpak binnen en buiten Denko ICT kunnen overnemen

## Kernfunctionaliteiten

### Deployment Orchestratie
- Deployment gaat door zelfs als individuele stappen falen
- Automatische retry-logica met netwerk validatie
- Slaat afhankelijke stappen over wanneer vereisten falen (bijv. apps als WinGet faalt)
- Visuele feedback met kleurgecodeerde output

### Tracking & Rapportage
- Alle deployment stappen opgeslagen in `HKLM:\SOFTWARE\DenkoICT\Deployment\Steps`
- Elke stap slaat status, tijdstempel, exit codes en foutmeldingen op
- Tracking overleeft reboots en script crashes
- Opgemaakte samenvattingen met `Show-DeploymentSummary`
- Query registry op afstand om deployment status te controleren
- Genereer CSV-rapporten voor analyse

### Code Kwaliteit
- Gecentraliseerde functies: 350+ regels duplicate code geëlimineerd door gedeelde library
- Exit code interpretatie: WinGet en MSI exit codes vertaald naar leesbare beschrijvingen
- Foutafhandeling: Try-catch-finally blokken met gedetailleerde logging
- Parameter validatie: ValidateScript, ValidateSet, ValidateRange op alle inputs
- PSScriptInfo metadata: Alle scripts PowerShell Gallery compliant
- Volgt Microsoft PowerShell best practices

## Kernprincipes
- **Modern first:** Gericht op Windows 11 Pro 25H2 met volledige ondersteuning voor PowerShell 7 en Windows Terminal
- **Automatiseren waar mogelijk:** Elke manuele taak die tijdens de stage tegengekomen wordt, krijgt een script of herhaalbare workflow
- **Leveranciers-specifiek:** Dell- en HP hardware hebben prioriteit omdat deze onze productieomgeving vertegenwoordigen
- **Best practices als basis:** Scripts volgen de actuele aanbevelingen van Microsoft, Dell en HP
- **Blijven doorwerken:** Scripts blijven werken zelfs wanneer individuele componenten falen
- **Observeerbaar:** Alle operaties gelogd en getrackt voor audit en troubleshooting

## Hybride uitrolaanpak
- **Microsoft Intune & AutoPilot:** Een deel van het devicepark wordt uitgerold via Windows AutoPilot, waarbij Intune de baseline policies, apps en compliance-regels toepast. De scripts in deze repository breiden die basis uit met extra automatisering in PowerShell 7
- **Lokale/on-premises registratie:** Een ander deel wordt voorbereid via lokale infrastructuur. Ondanks het ontbreken van cloudinschrijving profiteren deze systemen van dezelfde moderne PowerShell-7-scripts om handwerk te elimineren
- **Gedeelde automatiseringslaag:** Of het apparaat nu cloud-managed of on-premises is, beheerders kunnen vanuit dezelfde toolkit consistente build-, patch- en configuratieroutines draaien

## Repositorystructuur

### Kernscripts
| Script | Versie | Doel |
| --- | --- | --- |
| [ps_Deploy-Device.ps1](Scripts/ps_Deploy-Device.ps1) | 1.3.0 | **Hoofdorchestrator** - Coördineert het volledige deployment proces met foutafhandeling |
| [ps_Custom-Functions.ps1](Scripts/ps_Custom-Functions.ps1) | 3.0.0 | **Functiebibliotheek** - Logging, netwerktesten, exit code interpretatie, status tracking |

### Installatiescripts
| Script | Versie | Doel |
| --- | --- | --- |
| [ps_Install-Winget.ps1](Scripts/ps_Install-Winget.ps1) | 2.8.1 | Installeert Windows Package Manager met fallback methodes |
| [ps_Install-Applications.ps1](Scripts/ps_Install-Applications.ps1) | 2.3.0 | Automatiseert applicatie-installatie via WinGet met gedetailleerde logging |
| [ps_Install-Drivers.ps1](Scripts/ps_Install-Drivers.ps1) | 2.1.0 | Regelt driver deployment met HP CMSL en Dell DCU-CLI |
| [ps_Install-MSI.ps1](Scripts/ps_Install-MSI.ps1) | 3.0.0 | MSI pakket installer met property extractie en exit code handling |
| [ps_Install-WindowsUpdates.ps1](Scripts/ps_Install-WindowsUpdates.ps1) | 1.0.0 | Windows Update installatie via PSWindowsUpdate module |

### Onderhoudsscripts
| Script | Versie | Doel |
| --- | --- | --- |
| [ps_Update-AllApps.ps1](Scripts/ps_Update-AllApps.ps1) | 2.1.0 | Forceert applicatie-updates voor volledig gepatchte systemen |
| [ps_Remove-Bloat.ps1](Scripts/ps_Remove-Bloat.ps1) | 1.0.2 | Verwijdert overbodige Windows, OEM en consumenten-applicaties |

### Hulpprogramma's
| Script | Versie | Doel |
| --- | --- | --- |
| [ps_Get-InstalledSoftware.ps1](Scripts/ps_Get-InstalledSoftware.ps1) | 1.3.0 | Software-inventarisatie (Win32 + Store apps) |
| [ps_Get-SerialNumber.ps1](Scripts/ps_Get-SerialNumber.ps1) | 1.0.0 | Haalt serienummer op en genereert hostname |
| [ps_Set-Wallpaper.ps1](Scripts/ps_Set-Wallpaper.ps1) | 1.0.0 | Configureert bedrijfsachtergrond |
| [ps_DisableFirstLogonAnimation.ps1](Scripts/ps_DisableFirstLogonAnimation.ps1) | 1.0.0 | Schakelt eerste login-animatie uit voor snellere deployment |

### Configuratiebestanden
| Bestand | Doel |
| --- | --- |
| `autounattend.xml` | Baseline unattend-configuratie voor Windows 11 Pro imaging-scenario's |

## Hoe Deployment Werkt

### Deployment Flow
```
1. Boot vanaf USB met autounattend.xml
2. Windows 11 Pro 25H2 installeert automatisch
3. ps_Deploy-Device.ps1 start (handmatig of via OOBE)
4. Download ps_Custom-Functions.ps1 van GitHub
5. Voert deployment stappen uit in volgorde:
   ├─ ✓ WinGet Installatie
   ├─ ✓ Driver Updates (Dell DCU / HP HPIA)
   ├─ ✓ Applicatie Installatie
   ├─ ✓ Achtergrond Configuratie
   └─ ✓ Windows Updates
6. Toont samenvatting met status van elke stap
7. Slaat resultaten op in registry voor latere review
```

### Foutafhandeling
Het deployment proces blijft doorgaan:
- Als WinGet faalt, probeert het alternatieve installatiemethodes
- Als drivers falen, installeren applicaties nog steeds
- Als netwerk uitvalt, wacht en probeert opnieuw (tot configureerbare limiet)
- Elke stap logt zijn status naar registry voordat verder gegaan wordt
- Eindsamenvatting toont wat gelukt is, gefaald of overgeslagen

### Netwerkvalidatie
Ingebouwde netwerkvalidatie voorkomt fouten:
```powershell
# Controleert netwerk voor kritische operaties
Wait-ForNetworkStability -MaxRetries 5 -DelaySeconds 10

# Voor operaties die langdurige connectiviteit nodig hebben (zoals Office install)
Wait-ForNetworkStability -ContinuousCheck
```

## Deployment Tracking

### Registry Structuur
Elke deployment stap wordt getrackt in de Windows Registry:
```
HKLM:\SOFTWARE\DenkoICT\
├── Intune\                    (Applicatie succes tracking)
│   ├── ApplicationBundle = "2025.10.01"
│   ├── WindowsUpdates = "2025.10.01"
│   └── ...
└── Deployment\Steps\          (Deployment stap tracking)
    ├── WinGet Installation\
    │   ├── Status = "Success"
    │   ├── Timestamp = "2025-10-01 14:23:15"
    │   └── ExitCode = 0
    ├── Driver Updates\
    │   ├── Status = "Success"
    │   ├── Timestamp = "2025-10-01 14:25:42"
    │   └── ...
    └── Application Installation\
        ├── Status = "Failed"
        ├── Timestamp = "2025-10-01 14:32:18"
        ├── ErrorMessage = "Network timeout"
        └── ExitCode = -1978334969
```

### Deployment Status Controleren

#### Tijdens Deployment
Real-time feedback:
```
Starting: WinGet Installation
Completed: WinGet Installation

Starting: Driver Updates
Completed: Driver Updates

Starting: Application Installation
Failed: Application Installation
  Error details: Network connection lost
```

#### Na Deployment
Samenvatting:
```
================================================================================
  DENKO ICT DEPLOYMENT COMPLETE
================================================================================

  Total Steps: 5
  Successful: 4
  Failed: 1

  DETAILED STEP RESULTS:
  ----------------------------------------------------------------------------
  WinGet Installation
      Time: 2025-10-01 14:23:15
  Driver Updates
      Time: 2025-10-01 14:25:42
  Application Installation
      Time: 2025-10-01 14:32:18
  Wallpaper Configuration
      Time: 2025-10-01 14:33:05
  Windows Updates (FAILED)
      Time: 2025-10-01 14:35:01
      Error: Network not available
      Exit Code: -1978334969

  ----------------------------------------------------------------------------

  Deployment completed with 1 failure.
  Device may not be fully configured.
  Review failed steps and check log file.

  Deployment status: HKLM:\SOFTWARE\DenkoICT\Deployment\Steps

================================================================================
```

#### Status Later Opvragen
```powershell
# Methode 1: Snelle PowerShell controle
Get-ItemProperty 'HKLM:\SOFTWARE\DenkoICT\Deployment\Steps\*'

# Methode 2: Custom functions gebruiken (aanbevolen)
. .\ps_Custom-Functions.ps1
Show-DeploymentSummary

# Methode 3: Specifieke stap ophalen
Get-DeploymentStepStatus -StepName "WinGet Installation"

# Methode 4: Exporteren voor rapportage
Get-AllDeploymentSteps | Export-Csv -Path "C:\DeploymentReport.csv"
```

## Compatibiliteit

### Windows 11-validatie
| Versie | Status | Notities |
| --- | --- | --- |
| 25H2 | Getest | Primaire release; alle workflows werkend |
| 24H2 | Legacy | Wordt voorlopig ondersteund, focus ligt op 25H2 |
| 23H2 | Niet ondersteund | Niet gegarandeerd functioneel, release niet langer onderhouden |

### Hardware en scope
| Device | Status | Notities |
| --- | --- | --- |
| HP ProBook 460 G11        | Geslaagd | Volledig geautomatiseerde uitrol met HP CMSL / HPIA |
| Dell Latitude 5440        | Geslaagd | Volledig geautomatiseerde uitrol met Dell DCU-CLI |

## Gebruiksgids

### Snel Starten
1. Installeer [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) en voer scripts uit via Windows Terminal
2. Clone deze repository: `git clone https://github.com/Stensel8/DenkoICT.git`
3. Bekijk en pas scripts aan voor jouw omgeving
4. Pas `autounattend.xml` aan naar wens

### Deployment Uitvoering
1. Maak een bootable USB-stick met Windows 11 Pro 25H2 via de [Media Creation Tool](https://www.microsoft.com/software-download/windows11)
2. Plaats `autounattend.xml` in de root van de USB-stick
3. Start de doelcomputer op vanaf de USB-stick en volg de automatische installatie
4. Na OOBE, voer `ps_Deploy-Device.ps1` uit (of configureer automatische start)

### Individuele Scripts Uitvoeren
Alle scripts ondersteunen standaard PowerShell parameters:
```powershell
# Applicaties installeren met logging
.\ps_Install-Applications.ps1 -Verbose

# Specifieke applicaties installeren
.\ps_Install-Applications.ps1 -Applications @("Microsoft.PowerShell", "7zip.7zip")

# Alle apps updaten behalve specifieke
.\ps_Update-AllApps.ps1 -ExcludeApps @("Mozilla.Firefox")

# MSI installeren met custom arguments
.\ps_Install-MSI.ps1 -MSIPath "C:\Installers\MyApp.msi" -InstallArguments @('ALLUSERS=1')

# Geïnstalleerde software ophalen en exporteren
.\ps_Get-InstalledSoftware.ps1 -ExportPath "C:\Inventory.csv"
```

### Monitoring en Troubleshooting
```powershell
# Deployment samenvatting bekijken
. .\ps_Custom-Functions.ps1
Show-DeploymentSummary

# Gedetailleerde logs bekijken
Get-Content "C:\DenkoICT\Logs\Deployment-*.log" -Tail 100

# Gefaalde stappen controleren
$failed = Get-AllDeploymentSteps | Where-Object Status -eq 'Failed'
foreach ($step in $failed) {
    Write-Host "$($step.StepName): $($step.ErrorMessage)"
}

# Deployment geschiedenis wissen voor fresh start
Clear-DeploymentHistory -WhatIf  # Preview
Clear-DeploymentHistory          # Uitvoeren
```

## Geavanceerde Functies

### Exit Code Interpretatie
Scripts vertalen automatisch exit codes:
```powershell
# WinGet exit codes
Get-WinGetExitCodeDescription -ExitCode -1978334969
# Geeft terug: "No network connection"

# MSI exit codes
Get-MSIExitCodeDescription -ExitCode 1603
# Geeft terug: ErrorCode=1603, Name=ERROR_INSTALL_FAILURE, Description=Fatal error during installation
```

## Logbestanden

Alle scripts loggen naar `C:\DenkoICT\Logs\`:
- **Deployment-YYYYMMDD-HHmmss.log** - Hoofd deployment transcript
- **Install-Applications.log** - Applicatie installatie details
- **Install-Drivers.log** - Driver installatie details
- **Install-WindowsUpdates.log** - Windows Update details
- **\*.txt** - MSI installatie logs (genoemd naar MSI bestand)

Logs roteren automatisch bij overschrijding van 10MB.

Feedback, feature requests en pull requests zijn van harte welkom. Open gerust een [issue](https://github.com/Stensel8/DenkoICT/issues) of stuur me een berichtje.

## Licentie
Dit project wordt beschikbaar gesteld onder de voorwaarden van de [MIT-licentie](LICENSE). Dit is een licentie die ook veel gebruikt werd door mijn inspiratiebronnen.

## Bronnen en inspiratie

### Primaire bijdragers
Deze repositories en makers vormden de basis voor grote delen van de automatiseringslogica:
- [https://github.com/stensel8/pchealth](https://github.com/stensel8/pchealth)
- [https://github.com/realsdeals/](https://github.com/realsdeals/)
- [https://github.com/jeffdfield](https://github.com/jeffdfield)
- [https://github.com/FriendsOfMDT/PSD](https://github.com/FriendsOfMDT/PSD)
- [https://github.com/ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil)
- [https://github.com/KelvinTegelaar/RunAsUser](https://github.com/KelvinTegelaar/RunAsUser)

### Aanvullende referenties
- [https://www.smartdeploy.com/download/trial-guide/](https://www.smartdeploy.com/download/trial-guide/)
- [https://docs.microsoft.com/en-us/windows/deployment/windows-deployment-scenarios](https://docs.microsoft.com/en-us/windows/deployment/windows-deployment-scenarios)
- [https://github.com/FriendsOfMDT/PSD](https://github.com/FriendsOfMDT/PSD)
- [https://learn.microsoft.com/en-us/intune/configmgr/mdt/](https://learn.microsoft.com/en-us/intune/configmgr/mdt/)
- [https://www.microsoft.com/en-us/download/details.aspx?id=54259](https://www.microsoft.com/en-us/download/details.aspx?id=54259)
- [https://github.com/Stensel8/Intune-Deployment-Tool](https://github.com/Stensel8/Intune-Deployment-Tool)
- [https://github.com/rink-turksma/IntunePrepTool](https://github.com/rink-turksma/IntunePrepTool)
- [https://uupdump.net/](https://uupdump.net/)
- [https://2pintsoftware.com/products/deployr](https://2pintsoftware.com/products/deployr)
- [https://www.immy.bot/](https://www.immy.bot/)
- [https://github.com/Romanitho/Winget-Install](https://github.com/Romanitho/Winget-Install)
- [https://github.com/ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil)
- [https://api.github.com/repos/microsoft/winget-cli/releases/latest](https://api.github.com/repos/microsoft/winget-cli/releases/latest)
- [https://github.com/KelvinTegelaar/RunAsUser](https://github.com/KelvinTegelaar/RunAsUser)
- [https://github.com/asheroto/winget-install](https://github.com/asheroto/winget-install)
- [https://www.powershellgallery.com/packages/winget-install/](https://www.powershellgallery.com/packages/winget-install/)
- [https://www.powershellgallery.com/packages/HPCMSL/](https://www.powershellgallery.com/packages/HPCMSL/)
- [https://github.com/omaha-consulting/winstall](https://github.com/omaha-consulting/winstall)
- [https://github.com/omaha-consulting/winget.pro](https://github.com/omaha-consulting/winget.pro)
- [https://github.com/REALSDEALS/pcHealth](https://github.com/REALSDEALS/pcHealth)
- [https://github.com/REALSDEALS/pcHealthPlus-VS](https://github.com/REALSDEALS/pcHealthPlus-VS)
- [https://github.com/REALSDEALS/pcHealthPlus](https://github.com/REALSDEALS/pcHealthPlus)

### Microsoft-ecosysteempartners
- [https://learn.robopack.com/home](https://learn.robopack.com/home)
- [https://www.rimo3.com/ms-intune-migration](https://www.rimo3.com/ms-intune-migration)
- [https://winstall.app/](https://winstall.app/)
- [https://winget.pro/](https://winget.pro/)
- [https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md)
