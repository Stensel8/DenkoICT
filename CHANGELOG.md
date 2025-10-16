# Changelog

All notable changes to the DenkoICT Deployment Toolkit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-10-16

### Added
- Zero-touch Windows 11 Pro deployment via USB boot
- Automated driver updates for Dell (DCU-CLI) and HP (Image Assistant)
- WinGet application deployment with retry logic and fallback methods
- Registry-based progress tracking that survives system crashes and reboots
- RMM agent installation support
- PowerShell 7 bootstrapping from PowerShell 5.1
- Comprehensive logging system in `C:\DenkoICT\Logs\`
- Bloatware removal functionality
- Windows Update automation
- Hostname generation based on device serial number (`PC-{SerialNumber}`)
- Support for multiple RMM agent filename patterns
- Network connectivity testing and retry logic

### Documentation
- Comprehensive README.md with usage instructions
- Dutch language README.nl.md
- Deployment flow and troubleshooting guides

[1.0.0]: https://github.com/Stensel8/DenkoICT/releases/tag/v1.0.0
