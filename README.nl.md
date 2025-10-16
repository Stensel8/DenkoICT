# Windows 11 Pro Deployment Automatisering

<p align="left">
    <a href="README.md">
        <img src="https://img.shields.io/badge/Switch%20to-English-blue?style=for-the-badge" alt="Switch naar Engels" />
    </a>
</p>

[![Dependabot Updates](https://github.com/Stensel8/DenkoICT/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/dependabot/dependabot-updates)
[![DevSkim](https://github.com/Stensel8/DenkoICT/actions/workflows/devskim.yml/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/devskim.yml)
[![PSScriptAnalyzer](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml)

**Huidige Versie:** [v1.0.0](https://github.com/Stensel8/DenkoICT/releases/tag/v1.0.0) | [Changelog](CHANGELOG.md) | [Releases](RELEASES.md) | [Scope](SCOPE.md)

Geautomatiseerde Windows 11 Pro deployment tools. Geen handmatige kliks. Gebruikt PowerShell 2.0 in WinPE, PowerShell 5.1 om PowerShell 7 aan te roepen en vervolgens PowerShell 7 voor de daadwerkelijke deployment. Gebruikt moderne tools waar mogelijk.

![Terminalscherm dat een succesvol Windows-implementatieproces toont. De console-uitvoer laat voltooide stappen zien: WinGet-installatie, Driverupdates voor HP en Dell, Applicatie-implementatie, Bloatware-verwijdering, Bureaubladachtergrond-configuratie, en Windows Updates. Alle zes stappen zijn succesvol uitgevoerd met PowerShell 7, zonder fouten of overgeslagen onderdelen. Logbestand opgeslagen op C:\DenkoICT\Logs\Deploy-Device.ps1.log](Docs/Deployment_Flow.png)

![Schermafbeelding van het verwachte eindresultaat na een succesvolle Windows 11 deployment. Toont een volledig geconfigureerd bureaublad met geïnstalleerde applicaties, bijgewerkte drivers, en een schoon systeem zonder bloatware. Alle deployment-stappen zijn voltooid, inclusief Windows Updates en RMM-agentinstallatie, klaar voor gebruik door eindgebruikers.](Docs/Expected_Result.png)

## Wat Je Krijgt

- Zero-touch Windows 11 deployment via USB boot
- Automatische driver updates (Dell DCU-CLI, HP IA)
- WinGet applicatie deployment met retry logic
- Registry-based progress tracking die crashes overleeft
- Deployment gaat door wanneer individuele stappen falen
- RMM agent installatie (Datto, etc.)

## Snelle Start

**Vereisten:** Windows 11 Pro 25H2, **Ethernet verbinding** (vereist voor script downloads)

1. **Maak bootable USB:**
   - **Optie A:** [Windows Media Creation Tool](https://www.microsoft.com/software-download/windows11) (aanbevolen)
   - **Optie B:** [Rufus](https://rufus.ie/) - **Vink de laatste customization boxes niet aan** omdat ze onze `autounattend.xml` zullen overschrijven
   - **Beste resultaten:** Gebruik een schone Windows 11 Pro 25H2 image
   - **Optioneel:** Pre-load RST/RAID drivers in boot.wim om ervoor te zorgen dat alle drives beschikbaar zijn
2. **Kopieer files naar USB root:**
   - `autounattend.xml` 
   - Je RMM agent (noem het `Agent.exe` voor de beste resultaten)
3. **Boot target device vanaf USB** met Ethernet kabel aangesloten
4. **Wacht** - Alles gebeurt automatisch
5. **USB removal timing:**
   - **Houd USB aangesloten** tijdens de eerste reboot (hostname change)
   - **Safe to remove** na 2+ reboots wanneer de progress >64% toont (black screen phase)
   - **Als er geen RMM agent benodigd is:** De USB kan op elk moment na de eerste reboot worden verwijderd

Zonder Ethernet gebeurt alleen de basis Windows install met hostname change.

## Hoe Het Werkt

**PowerShell versie:**
- **Windows PE**: PowerShell 2.0 tijdens setup (binnen autounattend.xml)
- **First Boot**: PowerShell 5.1 download en installeert PowerShell 7  
- **Deployment**: PowerShell 7 voert alle deployment scripts uit

1. `autounattend.xml` configureert Windows, kopieert RMM agent van USB naar `C:\DenkoICT\Download\Agent.exe`
2. Hostname verandert naar `PC-{SerialNumber}`, systeem reboot  
3. `Start.ps1` wordt uitgevoerd bij de eerste login (PowerShell 5.1)
4. Installeert WinGet en PowerShell 7, en start vervolgens `Deploy-Device.ps1`
5. Elke deployment step wordt gevolgd in `HKLM:\SOFTWARE\DenkoICT\Deployment\Steps`

**Steps executed:**
- WinGet installatie
- Driver updates (vendor-specific tools)
- Application bundle via WinGet
- Bloatware removal
- Windows Updates
- RMM agent installatie

Als er iets mislukt, gaat de deployment door. Check `C:\DenkoICT\Logs` voor detailed status en registry voor summary.

## Key Scripts

| Script | Wat Het Doet |
| --- | --- |
| [Start.ps1](Scripts/Start.ps1) | **Bootstrapper** - Installeert WinGet + PS7, start de main deployment |
| [Deploy-Device.ps1](Scripts/Deploy-Device.ps1) | Main orchestrator - voert alles uit in PowerShell 7 |
| [Custom-Functions.ps1](Scripts/Custom-Functions.ps1) | Function library - logging, network tests, exit codes |
| [Install-Winget.ps1](Scripts/Install-Winget.ps1) | Installeert WinGet met fallback methods |
| [Install-Applications.ps1](Scripts/Install-Applications.ps1) | WinGet app deployment |
| [Install-Drivers.ps1](Scripts/Install-Drivers.ps1) | Dell DCU-CLI / HP IA driver updates |

## Gebruik Voorbeelden

**Deploy everything:**
```powershell
.\Start.ps1
```

**Installeer specifieke apps (na initialization):**
```powershell
.\Install-Applications.ps1 -Applications @("Microsoft.PowerShell", "7zip.7zip")
```


## RMM Setup

Plaats je RMM agent installer op de USB drive. **Noem het `Agent.exe`** voor zero hassle. 

Tijdens Windows setup zoekt `autounattend.xml` naar files die matchen met `*Agent*.exe`, `*RMM*.exe`, etc., en kopieert de eerste die gevonden wordt naar `C:\DenkoICT\Download\Agent.exe`. Na reboot installeert het deployment script het automatisch.

**Supported agents:** Alles met silent install support (`/S` parameter). Getest met Datto RMM en KaseyaOne.

**Requirements:** RMM agent moet silent/unattended installation ondersteunen.

## Deployment Tracking & Troubleshooting

**Status tracking:**
- Progress opgeslagen in `HKLM:\SOFTWARE\DenkoICT\Deployment\Steps` met timestamps en exit codes
- Elke step wordt vastgelegd met success/failure status
- Registry entries overleven crashes en reboots

**Troubleshooting resources:**
- **Logs directory:** `C:\DenkoICT\Logs\`
- **Common issues:**
    - Network connectivity
    - Windows Update service draait niet
    - USB te vroeg removed tijdens setup

**Common fixes:**
- Network issues: Verhoog retry count in `Deploy-Device.ps1`
- WinGet faalt: Check Windows versie, run `.\Install-Winget.ps1` handmatig
- Driver issues: Verifieer Dell DCU-CLI of HP IA installation en run ze handmatig.
    - HP: C:\SWSetup\
    - Dell: C:\Program Files\Dell\CommandUpdate

## Windows 11 25H2 Compatibiliteit & Target Versie

Dit project is specifiek **geoptimaliseerd voor Windows 11 25H2** en target deze versie actief. Er zijn **geen compatibiliteitsrisico's** bij het gebruik van 25H2 voor deployment.

### Waarom 25H2?

Windows 11 25H2 is technisch **identiek aan 24H2** omdat beide dezelfde servicing branch delen [[1](https://techcommunity.microsoft.com/blog/windows-itpro-blog/get-ready-for-windows-11-version-25h2/4426437)][[2](https://www.tomshardware.com/software/windows/early-windows-11-25h2-benchmarks-confirm-the-update-provides-no-performance-improvements-over-24h2)]. De belangrijkste voordelen zijn:

- **Extended support lifecycle**: 25H2 krijgt support tot oktober 2027 (Pro) versus oktober 2026 voor 24H2 [[3](https://pureinfotech.com/should-install-windows-11-25h2/)][[4](https://endoflife.date/windows)]
- **Identieke codebase**: Beide versies draaien dezelfde kernel en hebben identieke driver compatibiliteit [[1](https://techcommunity.microsoft.com/blog/windows-itpro-blog/get-ready-for-windows-11-version-25h2/4426437)]
- **Zero performance overhead**: Benchmarks tonen 0% verschil tussen 24H2 en 25H2 [[2](https://www.tomshardware.com/software/windows/early-windows-11-25h2-benchmarks-confirm-the-update-provides-no-performance-improvements-over-24h2)]
- **Geen compatibiliteitsrisico's**: Microsoft bevestigt dat 25H2 geen impact heeft op bestaande driver- en applicatiecompatibiliteit [[1](https://techcommunity.microsoft.com/blog/windows-itpro-blog/get-ready-for-windows-11-version-25h2/4426437)]

### Wat is een Servicing Branch?

Een **servicing branch** is de onderliggende codebasis van een Windows-versie [[1](https://techcommunity.microsoft.com/blog/windows-itpro-blog/get-ready-for-windows-11-version-25h2/4426437)]. Wanneer twee versies dezelfde branch delen (zoals 24H2 en 25H2), betekent dit:

- Identieke kernel, drivers, en core componenten
- Nieuwe features voor 25H2 worden maanden vooraf in **disabled state** naar 24H2-systemen gepusht via reguliere updates
- Het "upgraden" naar 25H2 is simpelweg het enableren van deze features via een klein enablement package (~500MB) [[5](https://www.free-codecs.com/news/windows-11-25h2-download-available-before-official-launch.htm)]

Dit staat in contrast met grote versiesprong zoals 23H2 → 24H2, waar een volledige OS-swap nodig was.

### Geteste Hardware

Dit deployment project is succesvol getest op de volgende apparaten:

| Apparaat Model | Status | Opmerkingen |
|---|---|---|
| HP ProBook 460 G11 | ✅ Geslaagd | Volledig geautomatiseerde implementatie met HP CMSL / HPIA |
| Dell Latitude 5440 | ✅ Geslaagd | Volledig geautomatiseerde implementatie met Dell DCU-CLI |
| Dell OptiPlex Micro Plus 7020 | ✅ Geslaagd | Volledig geautomatiseerde implementatie met Dell DCU-CLI |

Alle tests zijn uitgevoerd met Windows 11 Pro 25H2 (build 26100.x).

## Licentie
Ik breng dit project uit onder de [MIT Licentie](LICENSE)

## Credits
Gebouwd met inspiratie van:
- [stensel8](https://github.com/stensel8)
- [realsdeals](https://github.com/realsdeals)
- [jeffdfield](https://github.com/jeffdfield)
- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil)
- [asheroto/winget-install](https://github.com/asheroto/winget-install)
- [FriendsOfMDT/PSD](https://github.com/FriendsOfMDT/PSD)
- [KelvinTegelaar/RunAsUser](https://github.com/KelvinTegelaar/RunAsUser)
- [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat)
- [Romanitho/Winget-Install](https://github.com/Romanitho/Winget-Install)
- [omaha-consulting/winstall](https://github.com/omaha-consulting/winstall)
- [omaha-consulting/winget.pro](https://github.com/omaha-consulting/winget.pro)
- [REALSDEALS/pcHealth](https://github.com/REALSDEALS/pcHealth)
- [REALSDEALS/pcHealthPlus-VS](https://github.com/REALSDEALS/pcHealthPlus-VS)
- [REALSDEALS/pcHealthPlus](https://github.com/REALSDEALS/pcHealthPlus)
- [Stensel8/pchealth](https://github.com/stensel8/pchealth)
- [Stensel8/Intune-Deployment-Tool](https://github.com/Stensel8/Intune-Deployment-Tool)
- [rink-turksma/IntunePrepTool](https://github.com/rink-turksma/IntunePrepTool)

### Aanvullende referenties
- [Microsoft Windows Deployment Documentation](https://docs.microsoft.com/en-us/windows/deployment/windows-deployment-scenarios)
- [Microsoft Intune/MDT Documentation](https://learn.microsoft.com/en-us/intune/configmgr/mdt/)
- [Microsoft Deployment Toolkit](https://www.microsoft.com/en-us/download/details.aspx?id=54259)
- [SmartDeploy Trial Guide](https://www.smartdeploy.com/download/trial-guide/)
- [UUP Dump](https://uupdump.net/)
- [2PintSoftware DeployR](https://2pintsoftware.com/products/deployr)
- [ImmyBot](https://www.immy.bot/)
- [WinGet CLI GitHub](https://api.github.com/repos/microsoft/winget-cli/releases/latest)
- [PowerShell Gallery: winget-install](https://www.powershellgallery.com/packages/winget-install/)
- [PowerShell Gallery: HPCMSL](https://www.powershellgallery.com/packages/HPCMSL/)
- [WinGet Return Codes](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md)

### Microsoft-ecosysteempartners
- [RoboPack](https://learn.robopack.com/home)
- [Rimo3](https://www.rimo3.com/ms-intune-migration)
- [winstall.app](https://winstall.app/)
- [winget.pro](https://winget.pro/)
