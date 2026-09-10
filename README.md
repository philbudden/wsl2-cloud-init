# WSL2 developer environment

This repository prepares a per-user cloud-init snapshot for a standard Ubuntu 24.04 WSL2 installation. It establishes the future shared Linux baseline; it does not configure Windows, install the distribution, authenticate accounts, install personal tooling, or add project dependencies.

## Prerequisites owned by IT Ops

Before starting, IT Ops must have enabled and updated WSL, prepared Windows so `Ubuntu-24.04` can be installed without administrator rights, installed required Windows applications (including VS Code where applicable), and applied any corporate proxy, certificate, network, endpoint-security, or application controls necessary to reach Ubuntu and Docker repositories.

This workflow deliberately does not attempt to repair or configure those prerequisites.

## Generate first-boot configuration

From PowerShell, in this repository, run:

```powershell
.\setup.ps1
```

The script asks only for a Linux username. It validates the name, checks that `Ubuntu-24.04` is not already registered, and writes `%USERPROFILE%\.cloud-init\Ubuntu-24.04.user-data`. The file is a self-contained snapshot: its embedded scripts come from this checkout at generation time. It contains no passwords, SSH keys, email addresses, or other identity data.

For unattended use, supply the username explicitly:

```powershell
.\setup.ps1 -LinuxUsername engineer
```

The script refuses to overwrite existing user-data unless `-Force` is supplied. Use that switch only before first installation, after confirming that `Ubuntu-24.04` has not been installed.

Next, run this command explicitly. `setup.ps1` never installs or launches a distribution itself:

```powershell
wsl --install Ubuntu-24.04
```

Cloud-init consumes this distribution-specific file only on the distribution's first launch. If Ubuntu is already registered, do not assume a newly rendered file will apply; use the recovery guidance added in a later phase or seek support before making any destructive WSL change.

## Phase 1 status

Phase 1 provides deterministic rendering only. The embedded `bootstrap.sh` and `validate.sh` are intentional stubs so the generated cloud-config has the final installation shape without provisioning packages, Docker, or user-level validation. Those capabilities arrive in later phases.

## Test the renderer

Run the focused PowerShell test from a shell with PowerShell 7 and `cloud-init` available:

```powershell
pwsh -File .\tests\setup.Tests.ps1
```

The test verifies username handling, overwrite and existing-distro safeguards, UTF-8-without-BOM output, token replacement, and byte-for-byte embedded scripts. It also runs `cloud-init schema --config-file` when `cloud-init` is installed; CI will treat schema validation as required.
