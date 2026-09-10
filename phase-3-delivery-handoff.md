# Phase 3 delivery handoff

This document records the completed Phase 3 work. The authoritative next-phase scope remains [implementation-plan.md](implementation-plan.md#phase-4--ci-completion-and-documentation-of-personal-onboarding).

## Delivered validation and recovery experience

`scripts/validate.sh` is now installed by cloud-init and exposed as `validate-wsl-development-environment`. It is designed to run in the normal engineer's login session and aggregates labelled `PASS`/`FAIL` outcomes, returning non-zero when any required check fails.

- It checks Ubuntu 24.04/Noble, a WSL2 kernel, systemd as PID 1, cloud-init/bootstrap evidence, a non-root session, baseline commands, and an owned writable `~/Developer` directory.
- It checks the Docker CLI, Compose, Buildx, enabled and active `docker.service`, membership of the current user in `docker`, socket/daemon access without `sudo`, and `docker run --rm hello-world`.
- `--skip-network-smoke-test` omits only the `hello-world` pull/run for diagnosis and explicitly reports that the result is incomplete; it cannot hide other failures.
- Cloud-init state is inspected using `sudo -n` because its schema/status data is root-owned. Docker validation remains non-root. A WSL `cloud-init status` result of `disabled` is accepted only alongside a valid schema, the bootstrap-success marker, and a non-failed `cloud-final.service`.

The cloud-init template writes an executable wrapper at `/usr/local/bin/validate-wsl-development-environment`, which invokes the embedded validation snapshot. The README now explains cloud-init schema/log diagnostics, the required WSL shutdown/reopen to refresh Docker group membership, the installed validation command, the narrow network skip option, and the non-destructive bootstrap recovery command.

## Tests and acceptance evidence

- `tests/validate-test.sh` covers failure aggregation, rejection of a root session, and the narrow network-smoke-test skip behaviour.
- `tests/bootstrap-integration-test.sh` invokes validation after both first provisioning and a bootstrap rerun. Its disposable test account receives temporary passwordless sudo solely to allow the validator to read cloud-init metadata; cleanup removes that sudoers entry and the test account.
- ShellCheck, Bash syntax checks, `tests/bootstrap-failure-test.sh`, and `tests/validate-test.sh` passed in a disposable Ubuntu 24.04 container after the final validator change.
- Manual WSL acceptance passed after a fresh-login restart: `validate-wsl-development-environment` reported `Validation passed all required checks.` This confirms normal-user Docker access and the installed validator on the supported WSL baseline.

## Relevant commits

- `4b018b0` — installed validation, cloud-init wrapper, recovery documentation, and focused validation tests.
- `14db623` — reads root-owned cloud-init state through non-interactive sudo while retaining non-root Docker validation and integration coverage.

## Boundary for the next agent

Phase 3 is complete. Phase 4 may add the GitHub Actions workflow and complete the documented personal-onboarding sequence only. Preserve the completed renderer, bootstrap, validation, and recovery contracts. Do not add Windows provisioning, personal Git/SSH identity setup, dotfiles installation, authentication, project dependencies, or an ongoing update service.
