# Modern Device Deployment - Denko-ICT

<p align="left">
	<a href="README.nl.md">
		<img src="https://img.shields.io/badge/Switch%20to-Dutch-blue?style=for-the-badge" alt="Switch to Dutch" />
	</a>
</p>

[![Codacy Security Scan](https://github.com/Stensel8/DenkoICT/actions/workflows/codacy.yml/badge.svg?branch=main)](https://github.com/Stensel8/DenkoICT/actions/workflows/codacy.yml)

[![PSScriptAnalyzer](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml/badge.svg)](https://github.com/Stensel8/DenkoICT/actions/workflows/powershell.yml)

## Why this project exists
This repository is a part of my internship at Denko ICT. I joined a team where many device deployments and configuration tasks were still performed manually. I got the opportunity to re-evaluate these processes. By building a more modern automation toolkit, I want to prove that Windows 11 Pro devices can be deployed, secured, and made productive faster and with fewer errors, without relying on legacy tooling.

I set up this GitHub repository myself as a central place to store technical documentation and scripts.

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

## 🎯 Key Features

### **Deployment Orchestration**
- Deployment continues even if individual steps fail
- Automatic retry logic with network validation
- Skips dependent steps when prerequisites fail (e.g., apps if WinGet fails)
- Visual feedback with emojis and color-coded output

### **Tracking & Reporting**
- All deployment steps recorded in `HKLM:\SOFTWARE\DenkoICT\Deployment\Steps`
- Each step stores status, timestamp, exit codes, and error messages
- Tracking survives reboots and script crashes
- Formatted summaries with `Show-DeploymentSummary`
- Query registry remotely to check deployment status on any device
- Generate CSV reports for analysis across multiple devices

### **Code Quality**
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
| [ps_Deploy-Device.ps1](Scripts/ps_Deploy-Device.ps1) | 1.3.0 | **Main orchestrator** - Coordinates entire deployment process with error handling |
| [ps_Custom-Functions.ps1](Scripts/ps_Custom-Functions.ps1) | 3.0.0 | **Function library** - Logging, network testing, exit code interpretation, status tracking |

### Installation Scripts
| Script | Version | Purpose |
| --- | --- | --- |
| [ps_Install-Winget.ps1](Scripts/ps_Install-Winget.ps1) | 2.8.1 | Installs Windows Package Manager with fallback methods |
| [ps_Install-Applications.ps1](Scripts/ps_Install-Applications.ps1) | 2.3.0 | Automates application installation using WinGet with detailed logging |
| [ps_Install-Drivers.ps1](Scripts/ps_Install-Drivers.ps1) | 2.1.0 | Handles driver deployment leveraging HP CMSL and Dell DCU-CLI |
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
| `autounattend.xml` | Baseline unattend configuration for Windows 11 Pro imaging scenarios |

## 🚀 How Deployment Works

### **Deployment Flow**
```
1. Boot from USB with autounattend.xml
2. Windows 11 Pro 25H2 installs automatically
3. ps_Deploy-Device.ps1 starts (manually or via OOBE)
4. Downloads ps_Custom-Functions.ps1 from GitHub
5. Executes deployment steps in order:
   ├─ ✓ WinGet Installation
   ├─ ✓ Driver Updates (Dell DCU / HP HPIA)
   ├─ ✓ Application Installation
   ├─ ✓ Wallpaper Configuration
   └─ ✓ Windows Updates
6. Shows summary with status of each step
7. Stores results in registry for later review
```

### **Error Handling**
The deployment process keeps going:
- If WinGet fails, it tries alternative installation methods
- If drivers fail, applications still install
- If network drops, it waits and retries (up to configurable limit)
- Every step logs its status to registry before continuing
- Final summary shows what succeeded, failed, or was skipped

### **Network Validation**
Built-in network validation prevents failures:
```powershell
# Checks network before critical operations
Wait-ForNetworkStability -MaxRetries 5 -DelaySeconds 10

# For operations needing sustained connectivity (like Office install)
Wait-ForNetworkStability -ContinuousCheck
```

## 📊 Deployment Tracking

### **Registry Structure**
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

### **Checking Deployment Status**

#### **During Deployment**
Real-time visual feedback:
```
🔄 Starting: WinGet Installation
✓ Completed: WinGet Installation

🔄 Starting: Driver Updates
✓ Completed: Driver Updates

🔄 Starting: Application Installation
✗ Failed: Application Installation
  Error details: Network connection lost
```

#### **After Deployment**
Summary:
```
================================================================================
  DENKO ICT DEPLOYMENT COMPLETE
================================================================================

  Total Steps: 5
  ✓ Successful: 4
  ✗ Failed: 1

  DETAILED STEP RESULTS:
  ----------------------------------------------------------------------------
  ✓ WinGet Installation
      Time: 2025-10-01 14:23:15
  ✓ Driver Updates
      Time: 2025-10-01 14:25:42
  ✓ Application Installation
      Time: 2025-10-01 14:32:18
  ✓ Wallpaper Configuration
      Time: 2025-10-01 14:33:05
  ✗ Windows Updates
      Time: 2025-10-01 14:35:01
      Error: Network not available
      Exit Code: -1978334969

  ----------------------------------------------------------------------------

  ⚠ Deployment completed with 1 failure(s).
  Your device may not be fully configured.
  Please review the failed steps above and check the log file.

  Deployment status stored in: HKLM:\SOFTWARE\DenkoICT\Deployment\Steps

================================================================================
```

#### **Query Status Later**
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

## Compatibility 🧪

### Windows 11 validation
| Version | Status | Notes |
| --- | --- | --- |
| 25H2 | ✅ Tested | Primary release; all workflows validated and functional |
| 24H2 | 🕐 Legacy | Supported for now, but the focus is on 25H2 |
| 23H2 | ❌ Unsupported | Cannot be guaranteed to work, since this OS is no longer maintained by Microsoft |

### Hardware and scope
| Device | Status | Notes |
| --- | --- | --- |
| HP ProBook 460 G11        | ✅ Passed | Fully automated deployment with HP CMSL / HPIA |
| Dell Latitude 5440        | ✅ Passed | Fully automated deployment with Dell DCU-CLI |

## 📖 Usage Guide

### **Quick Start**
1. Install [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) and run scripts from Windows Terminal
2. Clone this repository: `git clone https://github.com/Stensel8/DenkoICT.git`
3. Review and customize scripts for your environment
4. Customize `autounattend.xml` as desired

### **Deployment Execution**
1. Create a bootable USB drive with Windows 11 Pro 25H2 using the [Media Creation Tool](https://www.microsoft.com/software-download/windows11)
2. Place `autounattend.xml` in the root of the USB drive
3. Boot the target computer from the USB drive and follow the automated installation
4. After OOBE, run `ps_Deploy-Device.ps1` (or configure it to run automatically)

### **Running Individual Scripts**
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

### **Monitoring and Troubleshooting**
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

## 🔧 Advanced Features

### **Exit Code Interpretation**
Scripts automatically translate exit codes:
```powershell
# WinGet exit codes
Get-WinGetExitCodeDescription -ExitCode -1978334969
# Returns: "No network connection"

# MSI exit codes
Get-MSIExitCodeDescription -ExitCode 1603
# Returns: ErrorCode=1603, Name=ERROR_INSTALL_FAILURE, Description=Fatal error during installation
```

### **Network Retry Configuration**
Customize network behavior in `ps_Deploy-Device.ps1`:
```powershell
# Increase retries for unstable networks
.\ps_Deploy-Device.ps1 -NetworkRetryCount 10 -NetworkRetryDelaySeconds 15
```

### **Safe Script Execution**
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

## 📁 Log Files

All scripts log to `C:\DenkoICT\Logs\`:
- **Deployment-YYYYMMDD-HHmmss.log** - Main deployment transcript
- **Install-Applications.log** - Application installation details
- **Install-Drivers.log** - Driver installation details
- **Install-WindowsUpdates.log** - Windows Update details
- **\*.txt** - MSI installation logs (named after MSI file)

Logs automatically rotate when exceeding 10MB.

## Roadmap and contributions
- ✅ ~~Add deployment tracking and status monitoring~~ (Completed v3.0.0)
- ✅ ~~Centralize common code patterns~~ (Completed v3.0.0)
- ✅ ~~Implement error handling~~ (Completed v3.0.0)
- 🔄 Add optional Intune scripts/templates for hybrid environments
- 🔄 Build integration patterns with KaseyaOne and other RMM platforms
- 🔄 Add automated testing framework
- 🔄 Create web dashboard for deployment status monitoring

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

### Microsoft ecosystem partners
- [https://learn.robopack.com/home](https://learn.robopack.com/home)
- [https://www.rimo3.com/ms-intune-migration](https://www.rimo3.com/ms-intune-migration)
- [https://winstall.app/](https://winstall.app/)
- [https://winget.pro/](https://winget.pro/)
- [https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md)
