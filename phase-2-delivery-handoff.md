# Phase 2 delivery handoff

This document records the completed Phase 2 work for the agent taking on Phase 3. The authoritative Phase 3 scope remains [implementation-plan.md](implementation-plan.md#phase-3--installed-validation-and-recovery-experience).

## Delivered machine baseline

`scripts/bootstrap.sh` now replaces the Phase 1 stub with a rerunnable root-only bootstrap for Ubuntu 24.04 (Noble).

- It requires exactly one valid, existing Linux username, validates Ubuntu 24.04/Noble and a supported Debian architecture, and requires systemd as PID 1 before changing package sources.
- It runs non-interactive apt metadata refresh and upgrade, then installs only the shared baseline packages: `ca-certificates`, `curl`, `file`, `git`, `openssh-client`, `procps`, and `build-essential`.
- It downloads Docker's official Ubuntu signing key atomically, writes one canonical deb822 source file at `/etc/apt/sources.list.d/docker.sources`, refreshes apt metadata, and installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`.
- It enables and starts `docker.service`, emits `systemctl` and journal diagnostics on service failures, adds the target user to the `docker` group, and creates `/home/<user>/Developer` with correct ownership.
- It validates root-safe binary, plugin, systemd, and daemon state; then writes a root-owned diagnostic marker at `/var/lib/wsl-development-environment/bootstrap-success`.
- It is intentionally safe to rerun: the Docker key/source are replaced atomically, group membership is not duplicated, and existing content in `~/Developer` is retained.

The implementation follows Docker's official Ubuntu apt-repository installation method. [Docker documentation](https://docs.docker.com/engine/install/ubuntu/)

## Tests delivered and passed

- `tests/bootstrap-failure-test.sh` verifies rejection of an unsupported Ubuntu release, malformed codename, malformed Docker architecture, missing user, and malformed username before provisioning can continue.
- `tests/bootstrap-integration-test.sh` is deliberately destructive and requires `WSL_BOOTSTRAP_TEST_DISPOSABLE=1`. It removes pre-existing Docker state in a disposable Ubuntu 24.04 systemd environment, proves a forced Docker-key retrieval failure exits non-zero, performs a real first provision, checks packages/repository/service/plugins/daemon/non-root Docker access/directory ownership, then reruns bootstrap and proves the Docker source, group membership, and a user file in `~/Developer` are preserved.
- ShellCheck, Bash syntax checks, and the focused failure test passed in a disposable Ubuntu 24.04 container.
- The full destructive integration test passed on the disposable WSL Ubuntu 24.04 instance.
- The user also reported that the manual Phase 2 checks passed: Docker enabled and active, Docker CLI/Compose/Buildx/daemon reachable without sudo after WSL restart, and `~/Developer` present and owned by the configured user.

## Cloud-init finding to carry forward

On the fresh WSL instance, `sudo cloud-init status --wait --long` returned `status: disabled`, despite successful cloud-init-created user state and completed bootstrap artifacts. Ubuntu's WSL cloud-init documentation demonstrates verification with `sudo cloud-init schema --system`, which was used successfully for the rendered configuration, rather than treating `cloud-init status` as the WSL completion signal. [Ubuntu WSL cloud-init guide](https://documentation.ubuntu.com/wsl/latest/howto/cloud-init/)

Phase 3 should investigate and document the supported WSL completion/failure diagnostic sequence before retaining the plan's `cloud-init status --wait --long` instruction. Do not label a successful WSL bootstrap as failed solely because that command reports `disabled`; use concrete artifacts, schema validation, and logs to distinguish a disabled status from a failed `runcmd`.

## Relevant commits

- `0cd160d` — Phase 2 baseline/Docker bootstrap, tests, and current README status.
- `8218f2c` — case-sensitive lowercase username enforcement exposed by PowerShell rendering tests.
- `19dcd05` — Phase 1 LF normalisation for embedded Linux shell scripts; preserve this renderer contract.

## Boundary for the next agent

Phase 3 starts with the existing `scripts/validate.sh` stub. Implement only installed validation, its unit/integration tests, and the recovery/documentation experience required by the plan. Preserve the Phase 1 renderer and Phase 2 bootstrap contracts. Do not add personal Git/SSH/dotfiles setup, CI workflow assembly, or unrelated onboarding work.
