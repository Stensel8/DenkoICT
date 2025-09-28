# Denko ICT Moderne Endpoint Deployment

<p align="right">
	<a href="README.md">
		<img src="https://img.shields.io/badge/Switch%20to-English-blue?style=for-the-badge" alt="Switch to English" />
	</a>
</p>

## Waarom dit project bestaat
Deze repository vormt het hoofdonderdeel van mijn stage bij Denko ICT. Ik kreeg de taak om het automatiseringsproces en het apparaat uitrol proces te herzien. Tijdens deze evaluatie zag ik mogelijkheden om handmatige configuratietaken verder te automatiseren met moderne tooling. Met deze eigentijdse automatiseringstoolkit wil ik aantonen dat Windows 11 Pro-apparaten nog sneller, veiliger en consistenter inzetbaar zijn, door gebruik te maken van de nieuwste beschikbare technologieën.

## Wat deze repository oplevert
- Een PowerShell 7-aanpak die aansluit op de actuele Microsoft-richtlijnen voor endpointbeheer.
- Geen afhankelijkheid van verouderde technologieën zoals Microsoft MDT, klassieke batch/CMD-scripts, VBScript, PowerShell 2.0 of WMIC.
- Geïntegreerde leveranciers-tools voor Dell (Dell Command | Update CLI) en HP (HP Image Assistant & HP Client Management Script Library (HP CMSL)) zodat apparaten direct hun patches installeren via Windows Terminal.
- Herbruikbare scripts voor applicatie-installatie, driverbeheer, devicevoorbereiding en algemeen onderhoud.
- Documentatie waarmee collega’s dezelfde moderne aanpak binnen en buiten Denko ICT kunnen overnemen.

## Kernprincipes
- **Modern first:** Gericht op Windows 11 Pro 25H2 met volledige ondersteuning voor PowerShell 7 en Windows Terminal.
- **Automatiseren waar mogelijk:** Elke manuele taak die ik tijdens de stage tegenkom, krijgt een script of herhaalbare workflow.
- **Leveranciers-specifiek:** Dell- en HP-enterprise hardware hebben prioriteit omdat deze ook onze productieomgeving vertegenwoordigen.
- **Best practices als basis:** Scripts volgen de actuele aanbevelingen van Microsoft, Dell en HP voor endpointconfiguratie en lifecyclemanagement.

## Hybride uitrolaanpak
- **Microsoft Intune & AutoPilot:** Een deel van het devicepark wordt uitgerold via Windows AutoPilot, waarbij Intune de baseline policies, apps en compliance-regels toepast. De scripts in deze repository breiden die basis uit met extra automatisering in PowerShell 7.
- **Lokale/on-premises registratie:** Een ander deel wordt voorbereid via lokale infrastructuur. Ondanks het ontbreken van cloudinschrijving profiteren deze systemen van dezelfde moderne PowerShell-7-scripts om handwerk te elimineren.
- **Gedeelde automatiseringslaag:** Of het apparaat nu cloud-managed of on-premises is, beheerders kunnen vanuit dezelfde toolkit consistente build-, patch- en configuratieroutines draaien.

## Repositorystructuur
| Map/Bestand | Doel |
| --- | --- |
| `autounattend.xml` | Baseline unattend-configuratie voor Windows 11 Pro imaging-scenario's. |
| `Scripts/Invoke-AdminToolkit.ps1` | Hoofdscript dat de toolkit orkestreert voor beheerders. |
| `Scripts/ps_Install-Applications.ps1` | Automatiseert applicatie-installaties met winget en geselecteerde installers. |
| `Scripts/ps_Install-Drivers.ps1` | Regelt driveruitrol met HP CMSL en Dell DCU-CLI. |
| `Scripts/ps_Remove-Bloat.ps1` | Verwijdert overbodige OEM- en consumentenapps van beheerde apparaten. |
| `Scripts/ps_Update-AllApps.ps1` | Forceert updates na de uitrol zodat systemen volledig gepatcht opleveren. |

> In de map `Scripts` vind je scripts voor onder andere het instellen van hostname op basis van een serienummer, wallpaperconfiguratie, Microsoft 365-installatie en meer.

## Compatibiliteit 🧪

### Windows 11-validatie
| Versie | Status | Notities |
| --- | --- | --- |
| 25H2 | ✅ Getest | Primaire release; alle workflows werkend. |
| 24H2 | 🕒 Legacy | Wordt voorlopig ondersteund, maar de focus ligt op 25H2. |
| 23H2 | ❌ Niet ondersteund | Niet gegarandeerd functioneel, want deze release wordt niet langer onderhouden door Microsoft. |

### Hardware en scope
| Device | Status | Notities |
| --- | --- | --- |
| HP ProBook G9 en hoger | ✅ Geslaagd | Volledig geautomatiseerde uitrol met HP CMSL & HPIA. |
| HP EliteBook G9 en hoger | ✅ Geslaagd | Volledig geautomatiseerde uitrol met HP CMSL & HPIA. |
| HP ZBook G9 en hoger | ✅ Geslaagd | Volledig geautomatiseerde uitrol met HP CMSL & HPIA. |
| Dell Latitude 5000-serie | ✅ Geslaagd | Geautomatiseerde deployment met Dell Command \| Update CLI en toolkit-scripts. |
| Dell Latitude 7000-serie | ✅ Geslaagd | Volledig geautomatiseerde deployment via Dell Command \| Update CLI. |
| Dell Latitude 9000-serie | ✅ Geslaagd | Volledig geautomatiseerde deployment via Dell Command \| Update CLI. |
| Dell OptiPlex 3000-serie | ✅ Geslaagd | Desktoplijn geautomatiseerd via Dell Command \| Update CLI. |
| Dell OptiPlex 5000-serie | ✅ Geslaagd | Desktoplijn geautomatiseerd via Dell Command \| Update CLI. |
| Dell OptiPlex 7000-serie | ✅ Geslaagd | Desktoplijn geautomatiseerd via Dell Command \| Update CLI. |
| Dell OptiPlex Micro | ✅ Geslaagd | Micro form factor geautomatiseerd via Dell Command \| Update CLI. |
| Dell OptiPlex Tower | ✅ Geslaagd | Tower-chassis geautomatiseerd via Dell Command \| Update CLI. |
| Dell OptiPlex Small Form Factor | ✅ Geslaagd | SFF-modellen geautomatiseerd via Dell Command \| Update CLI. |
| Dell OptiPlex All-In-One | ✅ Geslaagd | AIO-devices geautomatiseerd via Dell Command \| Update CLI. |
| Dell Precision 3000-serie | ✅ Geslaagd | Workstations geautomatiseerd via Dell Command \| Update CLI. |
| Dell Precision 5000-serie | ✅ Geslaagd | Workstations geautomatiseerd via Dell Command \| Update CLI. |
| Dell Precision 7000-serie | ✅ Geslaagd | Workstations geautomatiseerd via Dell Command \| Update CLI. |

## Aan de slag
1. Installeer [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) en voer scripts uit via Windows Terminal.
2. Clone deze repository en bekijk de scripts die aansluiten op jouw deploy-scenario.
3. Start `Invoke-AdminToolkit.ps1` met verhoogde rechten om de voorkeursworkflow te draaien.
4. Pas de applicatie- en drivermanifests in `Scripts` aan om te matchen met jouw devicecatalogus.

> Alle scripts draaien zonder Microsoft Deployment Toolkit, batchbestanden, CMD, VBScript, PowerShell 2.0 of WMIC.

## Roadmap en bijdragen
- Optionele Intune-scripts en templates toevoegen voor hybride omgevingen.
- Documentatie en techniek uitbouwen richting integratie met KaseyaOne en andere RMM-platformen.

Feedback, feature requests en pull requests zijn van harte welkom. Open gerust een [issue](https://github.com/Stensel8/DenkoICT/issues) of stuur me een berichtje.

## Licentie
Dit project wordt beschikbaar gesteld onder de voorwaarden van de [MIT-licentie](LICENSE). Dit is een licentie die ook veel gebruikt werd door mijn inspiratiebronnen.

## Bronnen en inspiratie

### Primaire bijdragers
Deze repositories en makers vormden de basis voor grote delen van de automatiseringslogica:
- https://github.com/stensel8/pchealth
- https://github.com/realsdeals/
- https://github.com/jeffdfield
- https://github.com/FriendsOfMDT/PSD
- https://github.com/ChrisTitusTech/winutil
- https://github.com/KelvinTegelaar/RunAsUser

### Aanvullende referenties
- https://www.smartdeploy.com/download/trial-guide/
- https://docs.microsoft.com/en-us/windows/deployment/windows-deployment-scenarios
- https://github.com/FriendsOfMDT/PSD
- https://learn.microsoft.com/en-us/intune/configmgr/mdt/
- https://www.microsoft.com/en-us/download/details.aspx?id=54259
- https://github.com/Stensel8/Intune-Deployment-Tool
- https://github.com/rink-turksma/IntunePrepTool
- https://uupdump.net/
- https://2pintsoftware.com/products/deployr
- https://www.immy.bot/
- https://github.com/Romanitho/Winget-Install
- https://github.com/ChrisTitusTech/winutil
- https://api.github.com/repos/microsoft/winget-cli/releases/latest
- https://github.com/KelvinTegelaar/RunAsUser
- https://github.com/asheroto/winget-install
- https://www.powershellgallery.com/packages/winget-install/
- https://www.powershellgallery.com/packages/HPCMSL/
- https://github.com/omaha-consulting/winstall
- https://github.com/omaha-consulting/winget.pro
- https://github.com/REALSDEALS/pcHealth
- https://github.com/REALSDEALS/pcHealthPlus-VS
- https://github.com/REALSDEALS/pcHealthPlus

### Microsoft-ecosysteempartners
- https://learn.robopack.com/home
- https://www.rimo3.com/ms-intune-migration
- https://winstall.app/
- https://winget.pro/
