# Phase 1 delivery handoff

This document records the completed Phase 1 work and its current evidence for the agent taking on Phase 2. The authoritative scope and requirements for Phase 2 remain in [implementation-plan.md](implementation-plan.md#phase-2--baseline-bootstrap-and-docker-provisioning).

## Delivered repository contract

Phase 1 established deterministic, per-user cloud-init rendering for the `Ubuntu-24.04` WSL distribution.

- `setup.ps1` resolves all inputs from `$PSScriptRoot`, rather than the caller's directory.
- It reads the cloud-init template plus the two embedded shell scripts, accepts only `-LinuxUsername` (or one interactive prompt), and validates a conservative Linux username pattern and reserved names.
- It checks that `wsl.exe` is available and lists registered distributions. It refuses to render if `Ubuntu-24.04` is already registered.
- It writes `%USERPROFILE%\.cloud-init\Ubuntu-24.04.user-data`, refuses to overwrite it unless `-Force` is explicitly supplied, emits UTF-8 without a BOM, and prints—but does not execute—`wsl --install Ubuntu-24.04`.
- It renders the username in the cloud-init user record and `/etc/wsl.conf`, base64-embeds both scripts, rejects unresolved tokens, checks the cloud-config header, and round-trips the rendered payloads before writing the file.

The documented Windows invocation is:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\setup.ps1
```

The `-ExecutionPolicy Bypass` setting applies to that one PowerShell process; it does not make a persistent policy change. Corporate Group Policy may still override it.

## Cloud-init shape delivered

`cloud-init/Ubuntu-24.04.user-data.template` creates the requested Linux user with:

- `/bin/bash` as the shell;
- `adm` and `sudo` groups;
- a locked password;
- passwordless sudo (`NOPASSWD`), a deliberate baseline decision from the plan.

It writes root-owned `/etc/wsl.conf` with `systemd=true` and the configured default user. It also writes root-owned, mode `0755` copies of `bootstrap.sh` and `validate.sh` at `/usr/local/lib/wsl-development-environment/`, then invokes the bootstrap with the username as an argv-style `runcmd` item.

At Phase 1, both embedded scripts are intentional stubs. No packages, Docker configuration, `~/Developer` directory, installed validation command, personal setup, or GitHub Actions workflow has been implemented.

## Tests and local verification

- `tests/setup.Tests.ps1` covers valid rendering; username/default-user output; locked password and passwordless sudo; systemd and bootstrap path presence; base64 payload round-tripping; invalid/reserved usernames; overwrite protection; explicit overwrite; and the existing-distro safeguard.
- The test runs `cloud-init schema --config-file` when `cloud-init` is available. The local development host did not have PowerShell or cloud-init, so the PowerShell test and actual cloud-init schema command were not run there.
- Local static verification passed: Bash syntax checks, YAML parsing, no unresolved renderer tokens, base64 payload round-tripping, and `git diff --check`.
- `.editorconfig`, `.gitattributes`, and `.gitignore` establish UTF-8/LF conventions and exclude generated per-user cloud-init output.

## Test-machine findings

An initial run on the disposable Windows/WSL test machine showed that the renderer created the expected user:

- `whoami` returned `philbudden`.
- `sudo -n true` succeeded without output.
- After `wsl --shutdown` and relaunch, `whoami` still returned `philbudden` and `ps -p 1 -o comm=` returned `systemd`.

That first run did **not** complete cloud-init successfully. `cloud-init status --wait --long` reported a `scripts_user`/`runcmd` failure. The installed bootstrap then showed `/usr/bin/env: 'bash\r': No such file or directory`, confirming Windows CRLF bytes in the embedded script.

Commit `19dcd05` addresses this for subsequent renders in two ways:

1. `.gitattributes` enforces LF checkout for shell scripts.
2. `setup.ps1` normalizes the script text to UTF-8 LF before base64 embedding, so a Windows checkout cannot inject a CRLF shebang into Linux.

The existing instance was repaired only for diagnosis by normalizing its installed scripts. Its bootstrap stub then ran successfully and printed its expected Phase 1 message. Its earlier cloud-init failure remains historical and is not clean acceptance evidence.

## Required clean acceptance still outstanding

The test machine is disposable, and the user has explicitly said that removing the instance is acceptable. A clean first-boot Phase 1 acceptance run is still needed after commit `19dcd05`:

1. Deliberately unregister the disposable `Ubuntu-24.04` instance only when assigned; this removes all of its data.
2. Regenerate user-data from the current revision. The existing generated file requires explicit `-Force` only after confirming no `Ubuntu-24.04` instance remains.
3. Install `Ubuntu-24.04` and require `sudo cloud-init status --wait --long` to succeed.
4. Verify the normal user, passwordless sudo, `/etc/wsl.conf` with `systemd=true`, root-owned executable embedded scripts, and systemd after a WSL shutdown/relaunch.

This is a manual Phase 1 acceptance gap, not permission to broaden the implementation. It can be performed alongside later testing only when explicitly assigned.

## Relevant commits

- `6e31fdd` — initial Phase 1 renderer, template, stubs, tests, and README.
- `c847985` — README discloses that generated user-data contains the supplied Linux username.
- `1655cd8`, `5e21f1c`, `49c6a2b` — README uses the built-in Windows PowerShell execution-policy-bypass invocation.
- `e724e15` — selects one resolved `wsl.exe` command entry when Windows resolves more than one.
- `d4b5f43` — fixes rendered payload verification regex and diagnostics.
- `19dcd05` — normalizes embedded shell scripts to LF and adds Git LF enforcement.

