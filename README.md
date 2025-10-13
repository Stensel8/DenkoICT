# Windows 11 Pro Deployment Automation

<p align="left">
   <a href="README.nl.md">
      <img src="https://img.shields.io/badge/Switch%20to-Dutch-blue?style=for-the-badge" alt="Switch to Dutch" />
   </a>
</p>

[![Dependabot Updates](https://github.com/Stensel8/DenkoICT/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/dependabot/dependabot-updates)

[![DevSkim](https://github.com/Stensel8/DenkoICT/actions/workflows/devskim.yml/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/devskim.yml)

[![PSScriptAnalyzer](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml)

Automated Windows 11 Pro deployment tools. No manual clicking. Uses PowerShell 2.0 in WinPE, PowerShell 5.1 to bootstrap PowerShell 7, then PowerShell 7 for the actual deployment. Uses modern tools where possible. 

![Terminal console showing successful deployment progress with green checkmarks indicating completed steps: WinGet Installation, Driver Updates for HP and Dell, Applications, Bloatware Removal, Wallpaper Configuration, and Windows Updates. The summary shows 6 successful steps, 0 failures, and 0 skipped, with a log file location at C:\DenkoICT\Logs\ps_Deploy-Device.ps1.log](Docs/Deployment_Flow.png)

![Windows 11 deployment completion screen showing successful installation with all components properly configured. The interface displays the final desktop environment with installed applications and configured settings, providing visual confirmation that the automated deployment process completed as expected.](Docs/Expected_Result.png)

## What You Get

- Zero-touch Windows 11 deployment via USB boot
- Automatic driver updates (Dell DCU-CLI, HP IA)
- WinGet application deployment with retry logic
- Registry-based progress tracking that survives crashes
- Deployment continues when individual steps fail
- RMM agent installation (Datto, etc.)

## Quick Start

**Prerequisites:** Windows 11 Pro 25H2, **Ethernet connection** (required for script downloads)

1. **Create bootable USB:**
   - **Option A:** [Windows Media Creation Tool](https://www.microsoft.com/software-download/windows11) (recommended)
   - **Option B:** [Rufus](https://rufus.ie/) - **Don't check the final customization boxes** as they will overwrite our `autounattend.xml`
   - **Best results:** Use a clean Windows 11 Pro 25H2 image
   - **Optional:** Pre-load RST/RAID drivers into boot.wim to ensure all drives are available
2. **Copy files to USB root:**
   - `autounattend.xml` 
   - Your RMM agent (name it `Agent.exe` for best results)
3. **Boot target device from USB** with Ethernet cable connected
4. **Wait** - Everything happens automatically
5. **USB removal timing:**
   - **Keep USB connected** through the first reboot (hostname change)
   - **Safe to remove** after 2+ reboots when progress shows >64% (black screen phase)
   - **If no RMM agent is used:** The USB can be removed anytime after first reboot

Without Ethernet, only the base Windows install with hostname change happens.

## How It Works

**PowerShell version:**
- **Windows PE**: PowerShell 2.0 during setup (inside autounattend.xml)
- **First Boot**: PowerShell 5.1 downloads and installs PowerShell 7  
- **Deployment**: PowerShell 7 runs all deployment scripts

1. `autounattend.xml` configures Windows, copies RMM agent from USB to `C:\DenkoICT\Download\Agent.exe`
2. Hostname changes to `PC-{SerialNumber}`, system reboots  
3. `ps_Init-Deployment.ps1` runs on first login (PowerShell 5.1)
4. Installs WinGet and PowerShell 7, then launches `ps_Deploy-Device.ps1`
5. Each deployment step tracked in `HKLM:\SOFTWARE\DenkoICT\Deployment\Steps`

**Steps executed:**
- WinGet installation
- Driver updates (vendor-specific tools)
- Application bundle via WinGet
- Bloatware removal
- Windows Updates
- RMM agent installation

If something fails, deployment continues. Check `C:\DenkoICT\Logs` for detailed status and registry for summary.

## Key Scripts

| Script | What It Does |
| --- | --- |
| [ps_Init-Deployment.ps1](Scripts/ps_Init-Deployment.ps1) | **Bootstrapper** - Installs WinGet + PS7, launches main deployment |
| [ps_Deploy-Device.ps1](Scripts/ps_Deploy-Device.ps1) | Main orchestrator - runs everything in PowerShell 7 |
| [ps_Custom-Functions.ps1](Scripts/ps_Custom-Functions.ps1) | Function library - logging, network tests, exit codes |
| [ps_Install-Winget.ps1](Scripts/ps_Install-Winget.ps1) | Installs WinGet with fallback methods |
| [ps_Install-Applications.ps1](Scripts/ps_Install-Applications.ps1) | WinGet app deployment |
| [ps_Install-Drivers.ps1](Scripts/ps_Install-Drivers.ps1) | Dell DCU-CLI / HP IA driver updates |

## Usage Examples

**Deploy everything:**
```powershell
.\ps_Init-Deployment.ps1
```

**Install specific apps (after initialization):**
```powershell
.\ps_Install-Applications.ps1 -Applications @("Microsoft.PowerShell", "7zip.7zip")
```


## RMM Setup

Put your RMM agent installer on the USB drive. **Name it `Agent.exe`** for zero hassle. 

During Windows setup, `autounattend.xml` searches for files matching `*Agent*.exe`, `*RMM*.exe`, etc., and copies the first one found to `C:\DenkoICT\Download\Agent.exe`. After reboot, deployment script installs it automatically.

**Supported agents:** Anything with silent install support (`/S` parameter). Tested with Datto RMM and KaseyaOne.

**Requirements:** RMM agent must support silent/unattended installation.

## Deployment Tracking & Troubleshooting

**Status tracking:**
- Progress stored in `HKLM:\SOFTWARE\DenkoICT\Deployment\Steps` with timestamps and exit codes
- Each step is recorded with success/failure status
- Registry entries survive crashes and reboots

**Troubleshooting resources:**
- **Logs directory:** `C:\DenkoICT\Logs\`
- **Common issues:**
   - Network connectivity
   - Windows Update service not running
   - USB removed too early during setup

**Common fixes:**
- Network issues: Increase retry count in `ps_Deploy-Device.ps1`
- WinGet fails: Check Windows version, run `.\ps_Install-Winget.ps1` manually
- Driver issues: Verify Dell DCU-CLI or HP IA installation and run them manually.
   - HP: C:\SWSetup\
   - Dell: C:\Program Files\Dell\CommandUpdate

## Windows 11 25H2 Compatibility & Target Version

This project is specifically **optimized for Windows 11 25H2** and actively targets this version. There are **no compatibility risks** when using 25H2 for deployment.

### Why 25H2?

Windows 11 25H2 is technically **identical to 24H2** because both share the same servicing branch [[1](https://techcommunity.microsoft.com/blog/windows-itpro-blog/get-ready-for-windows-11-version-25h2/4426437)][[2](https://www.tomshardware.com/software/windows/early-windows-11-25h2-benchmarks-confirm-the-update-provides-no-performance-improvements-over-24h2)]. The main advantages are:

- **Extended support lifecycle**: 25H2 receives support until October 2027 (Pro) versus October 2026 for 24H2 [[3](https://pureinfotech.com/should-install-windows-11-25h2/)][[4](https://endoflife.date/windows)]
- **Identical codebase**: Both versions run the same kernel and have identical driver compatibility [[1](https://techcommunity.microsoft.com/blog/windows-itpro-blog/get-ready-for-windows-11-version-25h2/4426437)]
- **Zero performance overhead**: Benchmarks show 0% difference between 24H2 and 25H2 [[2](https://www.tomshardware.com/software/windows/early-windows-11-25h2-benchmarks-confirm-the-update-provides-no-performance-improvements-over-24h2)]
- **No compatibility risks**: Microsoft confirms that 25H2 has no impact on existing driver and application compatibility [[1](https://techcommunity.microsoft.com/blog/windows-itpro-blog/get-ready-for-windows-11-version-25h2/4426437)]

### What is a Servicing Branch?

A **servicing branch** is the underlying codebase of a Windows version [[1](https://techcommunity.microsoft.com/blog/windows-itpro-blog/get-ready-for-windows-11-version-25h2/4426437)]. When two versions share the same branch (like 24H2 and 25H2), this means:

- Identical kernel, drivers, and core components
- New features for 25H2 are pushed months in advance to 24H2 systems in **disabled state** via regular updates
- "Upgrading" to 25H2 is simply enabling these features via a small enablement package (~500MB) [[5](https://www.free-codecs.com/news/windows-11-25h2-download-available-before-official-launch.htm)]

This contrasts with major version jumps like 23H2 → 24H2, which required a full OS swap.

### Tested Hardware

This deployment project has been successfully tested on the following devices:

| Device Model | Status | Notes |
|---|---|---|
| HP ProBook 460 G11 | ✅ Passed | Fully automated deployment with HP CMSL / HPIA |
| Dell Latitude 5440 | ✅ Passed | Fully automated deployment with Dell DCU-CLI |
| OptiPlex Micro Plus 7020 | ✅ Passed | Fully automated deployment with Dell DCU-CLI |

All tests were performed with Windows 11 Pro 25H2 (build 26100.x).

## License
I am building this project under the [MIT License](LICENSE)

## Credits
Built with inspiration from:
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

### Additional references
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

### Microsoft ecosystem partners
- [RoboPack](https://learn.robopack.com/home)
- [Rimo3](https://www.rimo3.com/ms-intune-migration)
- [winstall.app](https://winstall.app/)
- [winget.pro](https://winget.pro/)