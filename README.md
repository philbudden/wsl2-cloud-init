# WSL2 developer environment

This repository prepares a per-user cloud-init snapshot for a standard Ubuntu 24.04 WSL2 installation. It establishes the future shared Linux baseline; it does not configure Windows, install the distribution, authenticate accounts, install personal tooling, or add project dependencies.

## Prerequisites

You or your operations team must have enabled and updated WSL, prepared Windows so `Ubuntu-24.04` can be installed without administrator rights, installed any required Windows applications (such as VS Code for example), and applied any proxy, certificate, network, endpoint-security, or application controls necessary to reach Ubuntu and Docker repositories.

This workflow deliberately does not attempt to repair or configure those prerequisites.

## Generate first-boot configuration

From PowerShell, in this repository, run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\setup.ps1
```

The script asks only for a Linux username. It validates the name, checks that `Ubuntu-24.04` is not already registered, and writes `%USERPROFILE%\.cloud-init\Ubuntu-24.04.user-data`. The file is a self-contained snapshot: its embedded scripts come from this checkout at generation time. It contains the supplied Linux username, but it contains no passwords, SSH keys, or email addresses.

For unattended use, supply the username explicitly:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\setup.ps1 -LinuxUsername engineer
```

The script refuses to overwrite existing user-data unless `-Force` is supplied. Use that switch only before first installation, after confirming that `Ubuntu-24.04` has not been installed.

Next, run this command explicitly. `setup.ps1` never installs or launches a distribution itself:

```powershell
wsl --install Ubuntu-24.04
```

Cloud-init consumes this distribution-specific file only on the distribution's first launch. If Ubuntu is already registered, do not assume a newly rendered file will apply; use the recovery guidance added in a later phase or seek support before making any destructive WSL change.

## Current implementation status

The embedded `bootstrap.sh` provisions the shared Ubuntu baseline (`ca-certificates`, `curl`, `file`, `git`, `openssh-client`, `procps`, and `build-essential`), Docker Engine from Docker's official Ubuntu repository, Compose, Buildx, Docker service enablement, Docker-group membership, and `~/Developer` ownership. It is safe to rerun after an interrupted provision.

The installed validation command verifies the completed baseline. Personal Git/SSH configuration, dotfiles, account authentication, VS Code extensions, and project dependencies remain outside baseline provisioning.

## Complete installation and validate it

After Ubuntu first launches, cloud-init creates the configured user and runs the bootstrap. Confirm that cloud-init accepted the installed configuration:

```bash
sudo cloud-init schema --system
```

On Ubuntu WSL, `sudo cloud-init status --wait --long` may report `status: disabled` after DataSourceWSL provisioning has completed. Do not treat that status alone as a bootstrap failure. If the bootstrap marker is absent or `cloud-final.service` is failed, inspect the logs before proceeding:

```bash
sudo test -r /var/lib/wsl-development-environment/bootstrap-success
sudo systemctl is-failed cloud-final.service
sudo tail -n 100 /var/log/cloud-init.log
sudo tail -n 100 /var/log/cloud-init-output.log
```

From PowerShell, restart WSL to refresh the new user's Docker group membership:

```powershell
wsl --shutdown
wsl -d Ubuntu-24.04
```

Run validation as the normal Linux user, not with `sudo`:

```bash
validate-wsl-development-environment
```

It runs as the normal user and checks the Ubuntu and WSL2 environment, cloud-init/bootstrap evidence, baseline tools, `~/Developer`, Docker service and non-root access, Compose, Buildx, and `docker run --rm hello-world`. It uses non-interactive `sudo` only to inspect root-owned cloud-init state; Docker commands remain non-root checks. The final smoke test downloads an image on its first run and therefore needs network access.

For network diagnosis only, omit that one smoke test:

```bash
validate-wsl-development-environment --skip-network-smoke-test
```

A skipped smoke test is not a full installation acceptance result; all other required checks must still pass.

## Recovery

Do not unregister the distribution or overwrite generated user-data to recover from a failed bootstrap. First inspect the cloud-init logs above and correct the underlying network, repository, or service issue. Then rerun the installed bootstrap as root with the normal user name:

```bash
sudo /usr/local/lib/wsl-development-environment/bootstrap.sh "$USER"
```

After it completes, run `wsl --shutdown` from PowerShell, reopen Ubuntu, and run `validate-wsl-development-environment` as the normal user.

## Test the renderer

Run the focused PowerShell test from Windows PowerShell (included with supported Windows installations) with `cloud-init` available:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tests\setup.Tests.ps1
```

The test verifies username handling, overwrite and existing-distro safeguards, UTF-8-without-BOM output, token replacement, and byte-for-byte embedded scripts. It also runs `cloud-init schema --config-file` when `cloud-init` is installed; CI will treat schema validation as required.

## Continuous integration

GitHub Actions runs static checks, focused failure tests, and cloud-init rendering/schema validation on `ubuntu-24.04` for pushes, pull requests, and manual dispatch. The destructive bootstrap integration test runs only for pull requests or when manually dispatched. It provisions a fresh disposable runner user, validates the resulting environment, reruns bootstrap, and validates again to cover both first-run convergence and practical idempotency.
