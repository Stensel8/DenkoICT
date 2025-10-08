# Windows 11 Pro Deployment Automatisering

<p align="left">
    <a href="README.md">
        <img src="https://img.shields.io/badge/Switch%20to-English-blue?style=for-the-badge" alt="Switch naar Engels" />
    </a>
</p>

[![Dependabot Updates](https://github.com/Stensel8/DenkoICT/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/dependabot/dependabot-updates)

[![DevSkim](https://github.com/Stensel8/DenkoICT/actions/workflows/devskim.yml/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/devskim.yml)

[![PSScriptAnalyzer](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml)

Geautomatiseerde Windows 11 Pro implementatie die daadwerkelijk werkt. Geen MDT, geen VBScript, geen handmatig klikken. Gebruikt PowerShell 2.0 in WinPE, PowerShell 5.1 om PowerShell 7 op te starten, en vervolgens PowerShell 7 voor de daadwerkelijke implementatie. Moderne tools waar mogelijk.

![Implementatiestroom](Docs/Deployment_Flow.png)

![Verwacht Resultaat](Docs/Expected_Result.png)

## Wat Je Krijgt

- Zero-touch Windows 11 implementatie via USB-opstart
- Automatische stuurprogramma-updates (Dell DCU-CLI, HP CMSL)
- WinGet applicatie-implementatie met retry-logica
- Registratie-gebaseerde voortgangsregistratie die crashes overleeft
- Implementatie gaat door wanneer individuele stappen falen
- RMM-agent installatie (Datto, enz.)

![Implementatiestroom](Docs/Deployment_Flow.png)

![Verwacht Resultaat](Docs/Expected_Result.png)

## Snelle Start

**Vereisten:** Windows 11 Pro 25H2, **Ethernet-verbinding** (vereist voor scriptdownloads)

1. **Maak opstartbare USB:**
   - **Optie A:** [Windows Media Creation Tool](https://www.microsoft.com/software-download/windows11) (aanbevolen)
   - **Optie B:** [Rufus](https://rufus.ie/) - **Vink de laatste aanpassingsvakken niet aan** omdat ze onze `autounattend.xml` zullen overschrijven
   - **Beste resultaten:** Gebruik een schone Windows 11 Pro 25H2 afbeelding
   - **Optioneel:** Laad RST/RAID-stuurprogramma's in boot.wim om ervoor te zorgen dat alle schijven beschikbaar zijn
2. **Kopieer bestanden naar USB-root:**
   - `autounattend.xml` 
   - Je RMM-agent (noem het `Agent.exe` voor de beste resultaten)
3. **Opstartdoelapparaat vanaf USB** met Ethernet-kabel aangesloten
4. **Wacht** - Alles gebeurt automatisch
5. **USB-verwijderingstiming:**
   - **Houd USB aangesloten** tijdens de eerste herstart (hostname-wijziging)
   - **Veilig om te verwijderen** na 2+ herstarts wanneer de voortgang >64% toont (zwarte schermfase)
   - **Als er geen RMM-agent is:** USB kan op elk moment na de eerste herstart worden verwijderd

Zonder Ethernet gebeurt alleen de basis Windows-installatie met hostname-wijziging.

## Hoe Het Werkt

**PowerShell Evolutie:**
- **Windows PE**: PowerShell 2.0 tijdens installatie (binnen autounattend.xml)
- **Eerste Opstart**: PowerShell 5.1 download en installeert PowerShell 7  
- **Implementatie**: PowerShell 7 voert alle implementatiescripts uit

1. `autounattend.xml` configureert Windows, kopieert RMM-agent van USB naar `C:\DenkoICT\Download\Agent.exe`
2. Hostnaam verandert in `PC-{SerialNumber}`, systeem herstart  
3. `ps_Init-Deployment.ps1` wordt uitgevoerd bij de eerste login (PowerShell 5.1)
4. Installeert WinGet en PowerShell 7, en start vervolgens `ps_Deploy-Device.ps1`
5. Elke implementatiestap wordt gevolgd in `HKLM:\SOFTWARE\DenkoICT\Deployment\Steps`

**Uitgevoerde stappen:**
- WinGet-installatie
- Stuurprogramma-updates (leverancier-specifieke tools)
- Applicatiebundel via WinGet
- Bloatware-verwijdering
- Windows-updates
- RMM-agent installatie

Als er iets mislukt, gaat de implementatie door. Controleer `C:\DenkoICT\Logs` voor gedetailleerde status en register voor samenvatting.

## Belangrijke Scripts

| Script | Wat Het Doet |
| --- | --- |
| [ps_Init-Deployment.ps1](Scripts/ps_Init-Deployment.ps1) | **Bootstrapper** - Installeert WinGet + PS7, start de hoofdimplementatie |
| [ps_Deploy-Device.ps1](Scripts/ps_Deploy-Device.ps1) | Hoofdcoördinator - voert alles uit in PowerShell 7 |
| [ps_Custom-Functions.ps1](Scripts/ps_Custom-Functions.ps1) | Functiebibliotheek - logging, netwerktests, exitcodes |
| [ps_Install-Winget.ps1](Scripts/ps_Install-Winget.ps1) | Installeert WinGet met fallback-methoden |
| [ps_Install-Applications.ps1](Scripts/ps_Install-Applications.ps1) | WinGet-appimplementatie |
| [ps_Install-Drivers.ps1](Scripts/ps_Install-Drivers.ps1) | Dell DCU-CLI / HP CMSL stuurprogramma-updates |

## Gebruik Voorbeelden

**Implementeer alles:**
```powershell
.\ps_Init-Deployment.ps1
```

**Installeer specifieke apps (na initialisatie):**
```powershell
.\ps_Install-Applications.ps1 -Applications @("Microsoft.PowerShell", "7zip.7zip")
```


## RMM Setup

Plaats je RMM-agentinstallateur op de USB-stick. **Noem het `Agent.exe`** voor geen gedoe. 

Tijdens de Windows-installatie zoekt `autounattend.xml` naar bestanden die overeenkomen met `*Agent*.exe`, `*RMM*.exe`, enz., en kopieert de eerste die gevonden is naar `C:\DenkoICT\Download\Agent.exe`. Na de herstart installeert het implementatiescript het automatisch.

**Ondersteunde agents:** Alles met ondersteuning voor stille installatie (`/S` parameter). Getest met Datto RMM en KaseyaOne.

**Vereisten:** RMM-agent moet stille/onbewaakte installatie ondersteunen.

## Implementatie Tracking & Probleemoplossing
