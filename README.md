# DSCourier

## Description
DSCourier is a proof-of-concept that uses the WinGet Configuration COM API to apply DSC configurations through Microsoft-signed binaries. A separate blog post provides the full technical deep dive into the technique. 

DSCourier was built primarily from a research topic and should be viewed as a proof-of-concept rather than a polished or complete tool. Much of its value comes from operators modifying, extending, and experimenting with it themselves, including creating their own configuration files.

This technique has has bypassed CrowdStrike Falcon, Microsoft Defender for Endpoint (MDE) and Elastic Security EDR.

## Demo Videos
[CrowdStrike Bypass Demo](./demo/CrowdStrike_Bypass.mp4)


## Blog
Full write-up: [Read the blog](https://eclipsesec.com/posts/DSCourier/)

## Build & Release
- `Releases` contains the compiled DSCourier binary and supporting files for execution on a target system.
- `build.ps1` automates the build process, compiling the project and preparing binary.

## Requirements
Dev machine (to build DSCourier from source):
- Windows 10, 11, or Server 2025: for the build tooling to run
- .NET 8 SDK (Not just runtime, SDK needed to compile)
- Windows SDK 10.0.22621: Interop csproj targets net8.0-windows10.0.22621.0
- Git, WinGet, PowerShell: to run the build script

Target machine (to run the built DSCourier.exe):
- Windows 10, 11, or Server 2025: supported OS
- WinGet itself installed because DSCourier calls into it via COM
- WinGet Configuration Enabled: This is a WinGet feature flag (winget configure), needed because the interop uses Microsoft.Management.Configuration
- PSDscResources PowerShell Module: a runtime dependency for whatever DSC configurations DSCourier applies
