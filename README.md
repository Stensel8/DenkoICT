# Modern Device Deployment - Denko-ICT

<p align="left">
	<a href="README.nl.md">
		<img src="https://img.shields.io/badge/Switch%20to-Dutch-blue?style=for-the-badge" alt="Switch to Dutch" />
	</a>
</p>

[![Dependabot Updates](https://github.com/Stensel8/DenkoICT/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/dependabot/dependabot-updates)

[![DevSkim](https://github.com/Stensel8/DenkoICT/actions/workflows/devskim.yml/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/devskim.yml)

[![PSScriptAnalyzer](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml)

## Why this project exists
This repository is a part of my internship at Denko ICT. I joined a team where many device deployments and configuration tasks were still performed manually. I got the opportunity to re-evaluate these processes. By building a more modern automation toolkit, I want to prove that Windows 11 Pro devices can be deployed, secured, and made productive faster and with fewer errors, without relying on legacy tooling.

I set up this GitHub repository myself as a central place to store technical documentation and scripts.

![Deployment Flow](Docs/Deployment_Flow.png)

![Expected Result](Docs/Expected_Result.png)

## What this repository delivers
- A PowerShell 7 automation framework that aligns with current Microsoft endpoint management guidance
- Zero reliance on deprecated stacks such as Microsoft MDT, classic batch/CMD scripts, VBScript, PowerShell 2.0, or WMIC
- Integrated vendor tooling for Dell (Dell Command | Update CLI) and HP (HP Image Assistant & HP CMSL) with automatic driver updates
- Registry-based status monitoring and reporting
- Deployment continues when individual steps fail
- Reusable scripts for application deployment, driver management, device preparation, and general maintenance
- Centralized logging and error handling with detailed exit code interpretation
- Documentation to help colleagues adopt the same modern approach inside and outside Denko ICT

## Key Features

### Deployment Orchestration
- Deployment continues even if individual steps fail
- Automatic retry logic with network validation
- Skips dependent steps when prerequisites fail (e.g., apps if WinGet fails)
- Visual feedback with color-coded output

### Tracking & Reporting
- All deployment steps recorded in `HKLM:\SOFTWARE\DenkoICT\Deployment\Steps`
- Each step stores status, timestamp, exit codes, and error messages
- Tracking survives reboots and script crashes
- Formatted summaries with `Show-DeploymentSummary`
- Query registry remotely to check deployment status on any device
- Generate CSV reports for analysis across multiple devices

### Code Quality
- Centralized functions: 350+ lines of duplicate code eliminated through shared library
- Exit code interpretation: WinGet and MSI exit codes translated to readable descriptions
- Error handling: Try-catch-finally blocks with detailed logging
- Parameter validation: ValidateScript, ValidateSet, ValidateRange on all inputs
- PSScriptInfo metadata: All scripts PowerShell Gallery compliant
- Follows Microsoft PowerShell best practices

## Guiding principles
- **Modern only:** Everything targets Windows 11 Pro 25H2 with full support for PowerShell 7 and Windows Terminal
- **Automate first:** Every manual task encountered during the internship is captured as code or a repeatable script
- **Vendor-aware:** Dell and HP devices are the current focus because they represent our production fleet
- **Best practices aligned:** Each script follows current recommendations from Microsoft, Dell, and HP
- **Keep going:** Scripts continue working even when individual components fail
- **Observable:** All operations logged and tracked for audit and troubleshooting

## Hybrid deployment approach
- **Microsoft Intune & AutoPilot:** A portion of our fleet is provisioned through Windows AutoPilot, letting Intune apply baseline policies, applications, and compliance rules. The scripts in this repository extend those baselines with richer post-enrollment automation, still running in PowerShell 7
- **On-premises enrollment:** Another slice of devices is prepared on local infrastructure. Even without cloud enrollment, these systems benefit from the same modern PowerShell 7 tooling to eliminate manual steps
- **Shared automation layer:** Whether cloud-managed or on-premises, administrators can orchestrate consistent build, patch, and configuration routines from a single toolkit

## Repository structure

### Core Scripts
| Script | Version | Purpose |
| --- | --- | --- |
| [ps_Deploy-Device.ps1](Scripts/ps_Deploy-Device.ps1) | 2.2.0 | **Main orchestrator** - Coordinates entire deployment process with error handling, runs child scripts in separate windows |
| [ps_Custom-Functions.ps1](Scripts/ps_Custom-Functions.ps1) | 3.0.0 | **Function library** - Logging, network testing, exit code interpretation, status tracking |

### Installation Scripts
| Script | Version | Purpose |
| --- | --- | --- |
| [ps_Install-Winget.ps1](Scripts/ps_Install-Winget.ps1) | 2.8.1 | Installs Windows Package Manager with fallback methods |
| [ps_Install-Applications.ps1](Scripts/ps_Install-Applications.ps1) | 2.3.0 | Automates application installation using WinGet with detailed logging |
| [ps_Install-Drivers.ps1](Scripts/ps_Install-Drivers.ps1) | 2.1.0 | Handles driver deployment leveraging HP CMSL and Dell DCU-CLI |
| [ps_Install-RMM.ps1](Scripts/ps_Install-RMM.ps1) | 1.0.0 | Installs Datto RMM agent for remote monitoring (config-based, secure) |
| [ps_Install-MSI.ps1](Scripts/ps_Install-MSI.ps1) | 3.0.0 | MSI package installer with property extraction and exit code handling |
| [ps_Install-WindowsUpdates.ps1](Scripts/ps_Install-WindowsUpdates.ps1) | 1.0.0 | Windows Update installation using PSWindowsUpdate module |

### Maintenance Scripts
| Script | Version | Purpose |
| --- | --- | --- |
| [ps_Update-AllApps.ps1](Scripts/ps_Update-AllApps.ps1) | 2.1.0 | Forces application updates to deliver a fully patched experience |
| [ps_Remove-Bloat.ps1](Scripts/ps_Remove-Bloat.ps1) | 1.0.2 | Removes unnecessary Windows, OEM and consumer applications |

### Utility Scripts
| Script | Version | Purpose |
| --- | --- | --- |
| [ps_Get-InstalledSoftware.ps1](Scripts/ps_Get-InstalledSoftware.ps1) | 1.3.0 | Software inventory (Win32 + Store apps) |
| [ps_Get-SerialNumber.ps1](Scripts/ps_Get-SerialNumber.ps1) | 1.0.0 | Retrieves device serial number and generates hostname |
| [ps_Set-Wallpaper.ps1](Scripts/ps_Set-Wallpaper.ps1) | 1.0.0 | Configures company wallpaper |
| [ps_DisableFirstLogonAnimation.ps1](Scripts/ps_DisableFirstLogonAnimation.ps1) | 1.0.0 | Disables first logon animation for faster deployment |

### Configuration Files
| File | Purpose |
| --- | --- |
| `autounattend.xml` | Windows unattend configuration - searches USB for RMM agent and copies to C:\DenkoICT\Download\Agent.exe |


## How Deployment Works

### Deployment Flow
```
1. Boot from USB with autounattend.xml
2. Windows 11 Pro 25H2 installs automatically
3. During setup: Searches USB drives for RMM agent (*Agent*.exe)
4. Copies found agent to C:\DenkoICT\Download\Agent.exe
5. Hostname changed (PC-XXXX based on serial number)
6. System reboots after hostname change
7. First logon: ps_Deploy-Device.ps1 starts automatically
8. Downloads ps_Custom-Functions.ps1 from GitHub
9. Executes deployment steps in separate PowerShell windows:
   ├─ ✓ WinGet Installation
   ├─ ✓ Driver Updates (Dell DCU / HP HPIA)
   ├─ ✓ Application Installation
   ├─ ✓ Bloatware Removal
   ├─ ✓ Wallpaper Configuration
   ├─ ✓ Windows Updates
   └─ ✓ RMM Agent Installation (executes C:\DenkoICT\Download\Agent.exe)
10. Shows summary with status of each step
11. Stores results in registry for later review
```
   ├─ ✓ Bloatware Removal
   ├─ ✓ Wallpaper Configuration
   ├─ ✓ Windows Updates
   └─ ✓ RMM Agent Installation (Datto RMM)
9. Shows summary with status of each step
10. Stores results in registry for later review
```

### Error Handling
The deployment process keeps going:
- If WinGet fails, it tries alternative installation methods
- If drivers fail, applications still install
- If network drops, it waits and retries (up to configurable limit)
- Every step logs its status to registry before continuing
- Final summary shows what succeeded, failed, or was skipped

### Network Validation
Built-in network validation prevents failures:
```powershell
# Checks network before critical operations
Wait-ForNetworkStability -MaxRetries 5 -DelaySeconds 10

# For operations needing sustained connectivity (like Office install)
Wait-ForNetworkStability -ContinuousCheck
```

## Deployment Tracking

### Registry Structure
Every deployment step is tracked in the Windows Registry:
```
HKLM:\SOFTWARE\DenkoICT\
├── Intune\                    (Application success tracking)
│   ├── ApplicationBundle = "2025.10.01"
│   ├── WindowsUpdates = "2025.10.01"
│   └── ...
└── Deployment\Steps\          (Deployment step tracking)
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

### Checking Deployment Status

#### During Deployment
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

#### After Deployment
Summary:
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

#### Query Status Later
```powershell
# Method 1: Quick PowerShell check
Get-ItemProperty 'HKLM:\SOFTWARE\DenkoICT\Deployment\Steps\*'

# Method 2: Using custom functions (recommended)
. .\ps_Custom-Functions.ps1
Show-DeploymentSummary

# Method 3: Get specific step
Get-DeploymentStepStatus -StepName "WinGet Installation"

# Method 4: Export for reporting
Get-AllDeploymentSteps | Export-Csv -Path "C:\DeploymentReport.csv"
```

## Compatibility

### Windows 11 validation
| Version | Status | Notes |
| --- | --- | --- |
| 25H2 | Tested | Primary release; all workflows validated |
| 24H2 | Legacy | Supported for now, focus is on 25H2 |
| 23H2 | Unsupported | Not guaranteed to work, OS no longer maintained by Microsoft |

### Hardware and scope
| Device | Status | Notes |
| --- | --- | --- |
| HP ProBook 460 G11        | Passed | Fully automated deployment with HP CMSL / HPIA |
| Dell Latitude 5440        | Passed | Fully automated deployment with Dell DCU-CLI |

## Remote Monitoring & Management (RMM)

The deployment includes automated installation of RMM agents (like Datto RMM), enabling remote monitoring, management, and support for deployed devices.

### Features
- **USB-based deployment**: Simply place your RMM agent installer on the USB drive
- **No secrets in Git**: Agent executable stays on your USB, never committed to version control
- **Automatic detection**: Searches USB drives (D: through H:) for any file matching `*Agent*.exe`
- **Auto-copy during setup**: Copies agent to `C:\DenkoICT\RMM-Agent.exe` during Windows installation
- **Post-reboot installation**: RMM installs AFTER hostname change for proper device identification
- **Pre-installation check**: Detects existing installations to avoid duplicates
- **Silent installation**: No user interaction required
- **Verification**: Confirms successful installation and service status

### Setup Instructions

#### Step 1: Download Your RMM Agent
1. Log into your Datto RMM portal (or other RMM system)
2. Navigate to Setup → Agent Installation → Windows
3. Download the Windows agent installer
   - Example filename: `DattoRMMAgent-Setup.exe`

#### Step 2: Prepare USB Drive
1. Create bootable Windows 11 USB using [Media Creation Tool](https://www.microsoft.com/software-download/windows11)
2. Copy `autounattend.xml` to USB root
3. **Copy your RMM agent installer to USB root**
   - The filename MUST contain the word "Agent" (case-insensitive)
   - ✅ Valid examples: `DattoRMMAgent.exe`, `RMM-Agent-Installer.exe`, `Agent.exe`, `MyCompanyAgent.exe`
   - ❌ Invalid examples: `rmm-installer.exe`, `setup.exe`, `datto.exe`

#### Step 3: Deploy
1. Boot target device from USB
2. Windows installs automatically
3. During setup, `autounattend.xml` searches USB drives and copies agent to `C:\DenkoICT\Download\Agent.exe`
4. After hostname change and reboot, deployment script executes the agent
5. Device appears in your RMM portal within 5-10 minutes

### How It Works

**During Windows Installation (Specialize Pass):**
```powershell
# autounattend.xml searches USB drives D: through H:
$usbDrives = @('D:', 'E:', 'F:', 'G:', 'H:')
foreach ($drive in $usbDrives) {
    $agentFiles = Get-ChildItem -Path $drive -Filter '*Agent*.exe'
    if ($agentFiles) {
        Copy-Item $agentFiles[0] -Destination 'C:\DenkoICT\Download\Agent.exe'
        break
    }
}
```

**During Deployment (After Reboot):**
```powershell
# ps_Deploy-Device.ps1 executes the agent
if (Test-Path 'C:\DenkoICT\Download\Agent.exe') {
    Start-Process 'C:\DenkoICT\Download\Agent.exe' -ArgumentList '/S' -NoNewWindow -PassThru
    # Waits up to 30 seconds for service/files to appear
    Wait-ForRMMAgentInstallation -MaxWaitSeconds 30
}
```

### Manual Installation
To install the RMM agent manually after deployment:
```powershell
# If agent exists from USB
if (Test-Path 'C:\DenkoICT\Download\Agent.exe') {
    Start-Process 'C:\DenkoICT\Download\Agent.exe' -ArgumentList '/S' -NoNewWindow -PassThru
}
```

### Verification
Check if the agent installed successfully:
```powershell
# Check service status
Get-Service -Name "CagService"

# Check installation path
Test-Path "$env:ProgramFiles\CentraStage"
```

Devices appear in your RMM portal within 5-10 minutes of installation.

### Why RMM Installs After Reboot

The RMM agent installation is intentionally scheduled **after** the hostname change and reboot because:
- Datto RMM identifies devices by hostname
- Changing hostname after RMM installation causes duplicate device entries
- Installing after reboot ensures clean device registration with correct hostname

## Usage Guide

### Quick Start
1. Install [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) and run scripts from Windows Terminal
2. Clone this repository: `git clone https://github.com/Stensel8/DenkoICT.git`
3. Review and customize scripts for your environment
4. Customize `autounattend.xml` as desired

### Deployment Execution
1. Create a bootable USB drive with Windows 11 Pro 25H2 using the [Media Creation Tool](https://www.microsoft.com/software-download/windows11)
2. Place `autounattend.xml` in the root of the USB drive
3. Boot the target computer from the USB drive and follow the automated installation
4. After OOBE, run `ps_Deploy-Device.ps1` (or configure it to run automatically)

### Running Individual Scripts
All scripts support standard PowerShell parameters:
```powershell
# Install applications with logging
.\ps_Install-Applications.ps1 -Verbose

# Install specific applications
.\ps_Install-Applications.ps1 -Applications @("Microsoft.PowerShell", "7zip.7zip")

# Update all apps excluding specific ones
.\ps_Update-AllApps.ps1 -ExcludeApps @("Mozilla.Firefox")

# Install MSI with custom arguments
.\ps_Install-MSI.ps1 -MSIPath "C:\Installers\MyApp.msi" -InstallArguments @('ALLUSERS=1')

# Get installed software and export
.\ps_Get-InstalledSoftware.ps1 -ExportPath "C:\Inventory.csv"
```

### Monitoring and Troubleshooting
```powershell
# Check deployment summary
. .\ps_Custom-Functions.ps1
Show-DeploymentSummary

# View detailed logs
Get-Content "C:\DenkoICT\Logs\Deployment-*.log" -Tail 100

# Check specific failed step
$failed = Get-AllDeploymentSteps | Where-Object Status -eq 'Failed'
foreach ($step in $failed) {
    Write-Host "$($step.StepName): $($step.ErrorMessage)"
}

# Clear deployment history for fresh start
Clear-DeploymentHistory -WhatIf  # Preview
Clear-DeploymentHistory          # Execute
```

## Advanced Features

### Exit Code Interpretation
Scripts automatically translate exit codes:
```powershell
# WinGet exit codes
Get-WinGetExitCodeDescription -ExitCode -1978334969
# Returns: "No network connection"

# MSI exit codes
Get-MSIExitCodeDescription -ExitCode 1603
# Returns: ErrorCode=1603, Name=ERROR_INSTALL_FAILURE, Description=Fatal error during installation
```

### Network Retry Configuration
Customize network behavior in `ps_Deploy-Device.ps1`:
```powershell
# Increase retries for unstable networks
.\ps_Deploy-Device.ps1 -NetworkRetryCount 10 -NetworkRetryDelaySeconds 15
```

### Safe Script Execution
Error handling wrapper:
```powershell
$result = Invoke-SafeScriptBlock -OperationName "Custom Operation" -ScriptBlock {
    # Your code here
    Install-Something
} -Critical  # Add -Critical to fail on error

if ($result.Success) {
    Write-Host "Operation succeeded: $($result.Result)"
} else {
    Write-Host "Operation failed: $($result.Error)"
}
```

## Log Files

All scripts log to `C:\DenkoICT\Logs\`:
- **Deployment-YYYYMMDD-HHmmss.log** - Main deployment transcript
- **Install-Applications.log** - Application installation details
- **Install-Drivers.log** - Driver installation details
- **Install-WindowsUpdates.log** - Windows Update details
- **\*.txt** - MSI installation logs (named after MSI file)

Logs automatically rotate when exceeding 10MB.

Feedback, feature requests, and pull requests are welcome. Please [open an issue](https://github.com/Stensel8/DenkoICT/issues) to start. You can also ping me.

## License
This project is distributed under the terms of the [MIT License](LICENSE). This is a license also used by many of my sources of inspiration.

## References and inspiration

### Primary contributors
These repositories and users shaped large parts of the automation logic:
- [https://github.com/stensel8/pchealth](https://github.com/stensel8/pchealth)
- [https://github.com/realsdeals/](https://github.com/realsdeals/)
- [https://github.com/jeffdfield](https://github.com/jeffdfield)
- [https://github.com/FriendsOfMDT/PSD](https://github.com/FriendsOfMDT/PSD)
- [https://github.com/ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil)
- [https://github.com/KelvinTegelaar/RunAsUser](https://github.com/KelvinTegelaar/RunAsUser)

### Additional references
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
- [https://github.com/Raphire/Win11Debloat/tree/master](https://github.com/Raphire/Win11Debloat/tree/master)

### Microsoft ecosystem partners
- [https://learn.robopack.com/home](https://learn.robopack.com/home)
- [https://www.rimo3.com/ms-intune-migration](https://www.rimo3.com/ms-intune-migration)
- [https://winstall.app/](https://winstall.app/)
- [https://winget.pro/](https://winget.pro/)
- [https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md)
