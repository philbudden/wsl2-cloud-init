# WSL2 Developer Environment Automation — Implementation Plan

## 1. Purpose and scope

This repository will automate the shared Linux baseline for a Data Engineering workstation running standard Ubuntu 24.04 on WSL2. It will replace the machine-level package and Docker setup in `setup-instructions.md` while leaving Windows preparation, personal configuration, account authentication, and project dependencies outside provisioning.

The design optimises for a low-frequency onboarding process: one repository, no custom WSL image, no separately published bootstrap artefact, no central configuration service, and no ongoing fleet-management mechanism.

### Preconditions owned by IT Ops

Before the engineer starts this workflow, IT Ops must have:

- enabled and updated WSL and the Windows features it requires;
- prepared Windows so that the standard `Ubuntu-24.04` distribution can be installed without administrator rights;
- installed Windows applications such as VS Code; and
- applied any corporate network, proxy, certificate, endpoint-security, or application controls needed to reach Ubuntu and Docker package repositories.

The implementation will check relevant preconditions where it can, but it will not configure or repair Windows.

### In scope

- Generating per-user cloud-init configuration from PowerShell.
- Creating the engineer's Linux user and making it the WSL default.
- Installing and updating the shared Ubuntu baseline.
- Installing Docker Engine, Compose, and Buildx from Docker's official Ubuntu repository.
- Enabling Docker under systemd and granting the engineer non-root Docker access.
- Creating `~/Developer`.
- Validating the completed WSL baseline.
- Automated tests that exercise rendering, provisioning, reruns, and validation as far as GitHub-hosted runners realistically allow.
- Documentation for the remaining manual steps.

### Out of scope

- Windows feature enablement, Windows application installation, or other workstation management.
- Docker Desktop.
- VS Code extension installation or sign-in.
- SSH key upload to GitHub.
- GitHub, Copilot, or Codex authentication.
- Personal Git/SSH identities, aliases, shells, prompts, editors, or optional CLI tools.
- Project-specific language runtimes, databases, libraries, or other dependencies that belong in devcontainers.
- Custom WSL images, ongoing central updates, or independently versioned provisioning artefacts.

## 2. Architecture decision

Retain the proposed architecture:

```text
repository on Windows
    |
    | setup.ps1 renders a per-user snapshot
    v
%USERPROFILE%\.cloud-init\Ubuntu-24.04.user-data
    |
    | consumed once when the distro is first installed/launched
    v
Ubuntu 24.04 WSL cloud-init
    |
    | writes embedded scripts into the distro and invokes bootstrap.sh
    v
Ubuntu baseline + Docker + ~/Developer
    |
    | engineer restarts WSL to refresh group membership
    v
validate.sh verifies the finished environment
```

This is technically supported by Ubuntu 24.04 on WSL: cloud-init is included, a distribution-specific file named `Ubuntu-24.04.user-data` is read from the Windows user's `.cloud-init` directory on first installation, and systemd is enabled by default. The implementation will still write an explicit systemd setting to `/etc/wsl.conf` so the required state is visible and testable rather than dependent on an implicit image default.

### Resolved technical decisions

1. **Only the Linux username is collected.** Full name and work email are not required to provision the shared baseline. They belong to later Git/dotfiles configuration. The username will be accepted as a non-interactive parameter or prompted for interactively.
2. **The cloud-init user has passwordless sudo.** It will be created with a locked password and `sudo: ALL=(ALL) NOPASSWD:ALL`. This is simple to express in cloud-init and avoids handling a password in PowerShell, generated YAML, logs, or repository files. It is a deliberate local-development baseline decision, not an accidental omission.
3. **`setup.ps1` does not install the distribution.** It performs narrow, deterministic preparation and prints the exact next command: `wsl --install Ubuntu-24.04`. Keeping installation explicit makes first-boot failures easier to understand, preserves the boundary with IT-managed WSL readiness, and prevents a configuration-rendering script from unexpectedly launching a long-running installation.
4. **Scripts are embedded into generated user-data.** `setup.ps1` reads the checked-out `bootstrap.sh` and `validate.sh`, encodes their bytes as base64, and substitutes those payloads into the cloud-init template. Cloud-init `write_files` decodes them to root-owned executable files inside WSL. This creates a self-contained, immutable installation snapshot without relying on GitHub access, repository visibility, `/mnt/c` mount timing, Windows path translation, or a separately published release artefact.
5. **Cloud-init orchestrates; Bash provisions.** YAML creates the user, writes `/etc/wsl.conf` and the embedded scripts, and invokes one bootstrap command. Package repositories, packages, services, groups, directories, and detailed checks remain in testable Bash.
6. **Provisioning is rerunnable, installation is first-boot only.** `bootstrap.sh` must converge safely when run again. Cloud-init itself remains a once-per-instance trigger. The README will document a manual bootstrap rerun for recovery or verification, but no updater is introduced.
7. **Use Docker's official apt repository.** The bootstrap will derive the Ubuntu codename and Debian architecture at runtime, install the repository key and deb822 `.sources` file idempotently, then install `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`.

## 3. Repository structure

```text
wsl-development-environment/
├── README.md
├── setup.ps1
├── cloud-init/
│   └── Ubuntu-24.04.user-data.template
├── scripts/
│   ├── bootstrap.sh
│   └── validate.sh
├── tests/
│   ├── setup.Tests.ps1
│   ├── bootstrap-test.sh
│   ├── validate-test.sh
│   └── fixtures/
│       └── generated-user-data.expected.yml   # only if a stable golden fixture proves useful
├── .github/
│   └── workflows/
│       └── ci.yml
├── .editorconfig
└── .gitignore
```

The existing `setup-instructions.md`, `implementation-plan-prompt.md`, and this plan may remain as design inputs/history. The implementation README becomes the engineer-facing canonical workflow. A golden generated cloud-config fixture should be added only if structural assertions are insufficient; avoiding a large duplicate fixture reduces maintenance.

## 4. Responsibility map from the manual guide

| Manual setup concern | Destination | Planned treatment |
|---|---|---|
| Enable WSL and prepare Windows | IT Ops precondition | Document only; never modify Windows features. |
| Install standard Ubuntu 24.04 | Deliberate manual step | Run `wsl --install Ubuntu-24.04` after `setup.ps1`. |
| Create Linux user | `setup.ps1` + cloud-init | Prompt/parameterise username; cloud-init creates a locked-password user with passwordless sudo and makes it the default. |
| `apt update` and shared OS updates | `bootstrap.sh` | Non-interactive `apt-get update` and upgrade with failure propagated to cloud-init. |
| Git | `bootstrap.sh` | Install Ubuntu's `git` package. |
| SSH client | `bootstrap.sh` | Install `openssh-client`; do not create or upload account keys. |
| Docker apt prerequisites | `bootstrap.sh` | Install `ca-certificates`, `curl`, and supporting baseline packages. |
| Docker repository and Engine | `bootstrap.sh` | Configure official key/source, install Engine/CLI/containerd. |
| Docker Compose and Buildx | `bootstrap.sh` | Install official Docker plugins. |
| Docker under WSL/systemd | cloud-init + `bootstrap.sh` | Make systemd requirement explicit in `wsl.conf`; enable and start `docker.service`. |
| Non-root Docker access | `bootstrap.sh` + restart/manual boundary | Add the user to `docker`; instruct `wsl --shutdown` after cloud-init finishes so the next login receives the group. |
| `~/Developer` | `bootstrap.sh` | Create it with the target engineer as owner. |
| Compiler/base utilities needed by Linux Homebrew | `bootstrap.sh` | Install only the shared prerequisites required to run the existing dotfiles template: `build-essential`, `procps`, `file`, `git`, `curl`, and CA certificates. |
| Repository storage inside WSL | README | Explain that source belongs under `~/Developer`, not `/mnt/c`. |
| VS Code WSL connection | Manual onboarding | Open `code .` from `~/Developer` and confirm the WSL connection. |
| WSL, Dev Containers, Copilot, Container Tools, optional Codex extensions | Manual onboarding | Install/enable in the correct Windows/WSL extension context; provisioning must not manipulate the VS Code profile. |
| Personal and work SSH keys/config | Dotfiles + deliberate manual onboarding | Dotfiles may manage `~/.ssh/config`; key creation can remain documented; public-key upload and authentication stay manual. Never bake keys into provisioning. |
| Conditional Git identities | Dotfiles | Keep `~/.gitconfig`, account-specific includes, names, emails, and organisation mappings personal. |
| Homebrew, `gh`, `ripgrep`, `fd`, `fzf`, `jq`, `bat`, `stow` | Dotfiles | Use the existing `dotfiles-template` bootstrap/Brewfile after baseline provisioning. Do not duplicate these packages in the WSL bootstrap. |
| GitHub/Copilot/Codex sign-in | Deliberate manual onboarding | Document explicit user actions only. |
| Clone work repositories and enter devcontainers | Deliberate manual onboarding | Final acceptance workflow after SSH/account setup. Project dependencies remain in each `.devcontainer`. |

The baseline package list should remain intentionally short. Apart from Docker and its documented prerequisites, add a package only when it is required by Ubuntu/WSL operation or is a prerequisite for the standard dotfiles path. Optional convenience tools belong in dotfiles.

## 5. First-install interaction in detail

### 5.1 `setup.ps1`

The script will:

1. Resolve all repository inputs relative to `$PSScriptRoot`, not the caller's working directory.
2. Verify that the cloud-init template and both Bash scripts exist.
3. Verify that `wsl.exe` is available and that the IT-managed WSL installation responds to a harmless status/list command.
4. Fail if an `Ubuntu-24.04` instance is already registered. Cloud-init is a first-boot mechanism and silently rendering configuration for an existing instance would create false confidence. Recovery instructions can point to a manual bootstrap rerun; removing an existing distro remains an explicit, destructive user/IT decision.
5. Accept `-LinuxUsername` for automation/tests, otherwise prompt once.
6. Validate the username against a conservative Linux account pattern (lowercase initial letter or underscore, followed by lowercase letters, digits, underscores, or hyphens, with an implementation-defined maximum consistent with Ubuntu account tooling). Reject empty, malformed, and reserved/root usernames.
7. Read script bytes as UTF-8 without relying on Windows line-ending conversion, base64-encode them, and safely replace explicit template tokens. User input must never be evaluated as PowerShell or inserted into YAML without validation.
8. Render `%USERPROFILE%\.cloud-init\Ubuntu-24.04.user-data` in UTF-8 without a BOM.
9. Refuse to overwrite an existing user-data file by default. A clearly named explicit override switch may replace it after showing the exact path; tests must cover both paths.
10. Perform structural post-render checks: no template tokens remain, the output begins with `#cloud-config`, and the embedded payloads decode to the source scripts.
11. Print the output path, selected username, and next command. It must not call `wsl --install`.

The script must not request full name, email, GitHub organisation, SSH information, or secrets.

### 5.2 Cloud-init template

The rendered cloud-config will:

- define the target user, Bash shell, required administrative groups, locked password, and passwordless sudo rule;
- write `/etc/wsl.conf` with an explicit default user and systemd enabled;
- write `bootstrap.sh` and `validate.sh` under a stable root-owned location such as `/usr/local/lib/wsl-development-environment/`, mode `0755`, using base64 content;
- optionally install a small wrapper or symlink such as `/usr/local/bin/validate-wsl-development-environment` so validation is discoverable;
- invoke the bootstrap as an argv-style `runcmd` item with the username as an explicit argument; and
- allow a bootstrap failure to remain a cloud-init failure rather than masking it.

The template should not contain apt repository commands, multiline provisioning shell, remote clone commands, secrets, or identity data.

### 5.3 `bootstrap.sh`

The bootstrap will run as root and use `set -Eeuo pipefail`. It will:

1. Require and validate exactly one target username and verify that the account exists.
2. Verify Ubuntu 24.04 before changing package sources. A different OS/release is a hard failure because the implementation and tests target Noble.
3. Set non-interactive apt behaviour and run package index/update operations with clear progress and failure output.
4. Install the shared Ubuntu packages: `ca-certificates`, `curl`, `file`, `git`, `openssh-client`, `procps`, and `build-essential`. Add `gnupg` only if the chosen Docker key installation mechanism actually requires it.
5. Create `/etc/apt/keyrings`, fetch Docker's official signing key atomically, set readable permissions, and create a deb822 Docker source using the detected Ubuntu codename and `dpkg --print-architecture`.
6. Refresh apt metadata and install Docker Engine, CLI, containerd, Buildx, and Compose plugin.
7. Enable and start Docker through systemd. Treat failure as fatal and show useful service status/journal diagnostics.
8. Add the target user to the `docker` group without duplicating membership.
9. Create `/home/<user>/Developer` and enforce correct ownership without modifying unrelated home content.
10. Run root-safe installation checks: required binaries resolve, package/plugin commands return successfully, systemd is PID 1, and Docker's daemon answers. User-session permission validation is deferred until after WSL restarts.
11. Write a root-owned success marker containing the bootstrap version/repository revision if one is available without introducing a Git dependency at runtime. The marker is diagnostic only; actual checks remain authoritative.

Idempotency requirements:

- Re-running must not duplicate apt source entries, group memberships, or configuration blocks.
- Existing valid key/source files may be replaced atomically with the repository's canonical content.
- Apt installs and directory creation may safely repeat.
- The script must not delete user data, SSH/Git configuration, dotfiles, repositories, or unrelated package sources.
- A partial failure must exit non-zero and be safe to retry after the underlying problem is corrected.

### 5.4 Completion and validation sequence

The README will instruct the engineer to:

1. Run `./setup.ps1` from PowerShell.
2. Run `wsl --install Ubuntu-24.04`.
3. In Ubuntu, wait explicitly for provisioning with `sudo cloud-init status --wait --long` (exact supported flags will be confirmed during implementation).
4. If cloud-init reports failure, inspect `cloud-init status`, `/var/log/cloud-init.log`, and `/var/log/cloud-init-output.log`; do not continue as if setup succeeded.
5. From PowerShell, run `wsl --shutdown`, then reopen Ubuntu. This refreshes the user's `docker` group membership and applies WSL configuration consistently.
6. Run the installed validation command as the normal user.
7. Continue with dotfiles, account setup, VS Code extensions, and repository cloning only after validation passes.

## 6. `validate.sh` contract

Validation must be read-only apart from Docker's unavoidable transient test container/image state. It will print one labelled pass/fail line per check, collect all failures, and exit non-zero if any required check fails.

Required checks:

- Operating system is Ubuntu 24.04.
- Kernel/environment identifies WSL2, not a generic Ubuntu host or WSL1.
- PID 1 is systemd and systemd can report service state.
- Cloud-init completed successfully, with no reported cloud-init error.
- The current user is the configured non-root default user.
- `git`, `ssh`, `curl`, `file`, and required compiler/build commands are available.
- `~/Developer` exists, is a directory, and is owned/writable by the current user.
- Docker CLI, Compose plugin, and Buildx plugin respond.
- `docker.service` is enabled and active.
- The current user is listed in the `docker` group.
- The Docker socket is accessible without `sudo`, and `docker info` reaches the daemon.
- A small container smoke test (`docker run --rm hello-world`) succeeds. Document that this final check requires network access on its first run; provide a clearly labelled option to omit only this network-dependent check for diagnosis, not to turn an otherwise failing validation green.

Checks for personal SSH keys, GitHub connectivity, Git identity, VS Code extensions, Copilot, Codex, dotfiles packages, and project devcontainers are not baseline validation and must not be included.

## 7. Automated test strategy

CI will provide strong confidence in rendering and Ubuntu provisioning, but it cannot prove the WSL data source, Windows-to-WSL first-launch sequencing, or corporate laptop policy on a standard GitHub-hosted runner. The strategy therefore has layered tests and one explicit manual acceptance gate.

### 7.1 Fast static checks on every change

Run on `ubuntu-24.04`:

- `shellcheck` for all Bash files.
- Bash syntax checks (`bash -n`).
- PowerShell parse/static checks using `pwsh`; use PSScriptAnalyzer only if it can be pinned with low maintenance.
- YAML/cloud-config syntax and schema validation on a generated test configuration using `cloud-init schema`.
- Assertions that templates contain only known placeholders and no unresolved token survives rendering.

Pin the runner to `ubuntu-24.04`, not `ubuntu-latest`, because the production target is Ubuntu 24.04.

### 7.2 PowerShell rendering tests

Exercise `setup.ps1` non-interactively with a temporary output/home location so CI never writes a real profile:

- valid username produces the correctly named file;
- username and default-user configuration are rendered correctly;
- embedded payloads decode byte-for-byte to repository scripts;
- output is UTF-8 without BOM and valid cloud-config;
- missing input files, invalid/reserved usernames, unresolved placeholders, existing distro detection, and existing-output protection fail clearly;
- explicit overwrite behaviour works only when requested; and
- no full name, email, password, SSH key, or other identity field is emitted.

Use Pester if the repository adopts it as the sole PowerShell test dependency; otherwise a small native PowerShell assertion script is sufficient. Prefer the smaller choice unless Pester materially improves test clarity.

### 7.3 Bootstrap integration test on an ephemeral Ubuntu 24.04 runner

Use the disposable GitHub-hosted `ubuntu-24.04` VM as the closest maintainable systemd-capable analogue:

1. Create a temporary test user.
2. Remove or neutralise preinstalled Docker state that would otherwise mask repository/key installation, while preserving enough diagnostics to troubleshoot runner-image changes.
3. Run `bootstrap.sh <test-user>` as root.
4. Assert package source/key contents, installed packages, active Docker service, plugins, user group membership, directory ownership, and daemon operation.
5. Start a fresh login context for the test user and run `validate.sh`, including the hello-world container.
6. Run `bootstrap.sh` a second time and validate again to prove practical idempotency.

The test must not modify a shared or persistent runner. If clean Docker removal/reinstallation proves unstable because of GitHub runner image changes, fall back to an Ubuntu 24.04 systemd container only after documenting the lost coverage; do not silently replace an integration test with mocked command success.

### 7.4 Focused unit/failure tests

Add small tests for logic that is difficult or costly to force in integration:

- unsupported Ubuntu release is rejected before source changes;
- missing/nonexistent user is rejected;
- malformed Docker architecture/codename input cannot generate a corrupt source file;
- validation aggregates failures and exits non-zero;
- validation rejects root when it expects the engineer's session; and
- an optional network-smoke-test skip affects only that one labelled check.

Mocks should test control flow and error reporting, not substitute for the real apt/Docker integration job.

### 7.5 Manual WSL acceptance test

Before the first onboarding and after changes to `setup.ps1`, cloud-init structure, WSL configuration, or bootstrap invocation, test on a disposable Windows 11 machine that matches the IT Ops handoff:

- no `Ubuntu-24.04` instance is already registered;
- run the documented PowerShell and install flow as a non-admin engineer;
- confirm cloud-init consumes the generated file on first launch;
- confirm provisioning reaches success without an interactive password;
- shut down/reopen WSL and run validation as the engineer;
- confirm Docker runs without sudo, `code .` opens the WSL directory, and a representative devcontainer can start; and
- record the tested Windows build, WSL version, Ubuntu image version/date, and result in the release/change record.

Standard GitHub-hosted Windows runners are not an adequate substitute for this test because the workflow depends on nested WSL2 virtualisation, feature enablement, first launch, and reboot/admin state. Do not add a permanent self-hosted Windows runner for this low-frequency process unless repeated changes later justify its maintenance.

## 8. Implementation phases

Each phase is independently hand-offable. An implementation agent must stop at the stated boundary and must not begin the next phase unless it is explicitly assigned.

### Phase 1 — Repository contract and cloud-init rendering

Implement the structure, `setup.ps1`, cloud-init template, focused rendering tests, and an initial README describing prerequisites and the generation/install boundary. Use stub embedded scripts only if necessary to finish rendering tests; do not provision Linux packages yet.

**Definition of Done**

- `setup.ps1` collects only a validated Linux username.
- It renders the correctly named user-data file from repository-relative inputs without secrets or unresolved tokens.
- User creation, locked password, passwordless sudo, default WSL user, explicit systemd setting, embedded-script paths, permissions, and bootstrap invocation are represented in valid cloud-config.
- Existing distro/output safeguards and non-interactive test hooks are implemented.
- PowerShell rendering tests and cloud-init schema validation pass.
- README clearly states the IT Ops preconditions and explicit `wsl --install Ubuntu-24.04` next step.

**Stop condition**

Stop once rendering is deterministic and schema-valid. Do not implement package or Docker provisioning in this phase.

### Phase 2 — Baseline bootstrap and Docker provisioning

Implement `bootstrap.sh` with OS/user guards, apt updates, baseline packages, Docker repository/packages, systemd service management, Docker group membership, `~/Developer`, diagnostics, and safe rerun behaviour.

**Definition of Done**

- The package list matches the responsibility map and contains no personal or project-specific tools.
- Docker is installed from the official repository with Compose and Buildx.
- Docker is enabled/running through systemd.
- The target user has Docker group membership and owns `~/Developer`.
- Running the bootstrap twice succeeds without duplicated configuration or loss of user data.
- ShellCheck, syntax tests, focused failure tests, and the Ubuntu 24.04 integration test pass.
- A forced provisioning failure returns non-zero and remains visible to cloud-init.

**Stop condition**

Stop after repeatable machine-level convergence is proven on the CI Ubuntu environment. Do not add personal Git/SSH/dotfiles setup.

### Phase 3 — Installed validation and recovery experience

Implement `validate.sh`, install/expose it through cloud-init, add its unit/integration tests, and document cloud-init waiting, failure diagnostics, WSL shutdown/reopen, bootstrap rerun, and validation.

**Definition of Done**

- Every required check in section 6 produces a clear result and contributes to the final exit code.
- Validation works as the normal engineer user after a fresh login context.
- Docker daemon, non-root access, Compose, Buildx, and a real container smoke test are covered.
- Failure tests prove that broken required state cannot report success.
- README distinguishes cloud-init completion from the restart required for group membership.
- Recovery instructions do not unregister/delete a distro or overwrite user data automatically.

**Stop condition**

Stop when a completed installation can be assessed deterministically and failures route the engineer to useful logs. Do not perform a real Windows/WSL install unless separately assigned with an appropriate disposable machine.

### Phase 4 — CI completion and documentation of personal onboarding

Assemble the GitHub Actions workflow and finish the README's post-baseline sequence using the existing `dotfiles-template` as the recommended optional starting point.

**Definition of Done**

- CI runs static, render/schema, failure, first-run integration, second-run idempotency, and validation tests on relevant changes.
- Dependencies/actions are pinned to stable major versions or commits according to repository policy, and the workflow does not depend on unpublished internal infrastructure.
- README gives one linear onboarding path from IT handoff to a devcontainer-ready clone.
- Dotfiles, SSH/GitHub keys, Git identities, VS Code extensions, Copilot, optional Codex, and repository cloning are clearly separated from baseline provisioning.
- README explicitly says public SSH keys are uploaded manually and secrets/private keys are never consumed by provisioning.
- No additional repository, image build, scheduler, self-hosted runner, or update service has been introduced.

**Stop condition**

Stop when CI is green and the documentation is internally consistent. Do not declare WSL end-to-end acceptance based only on Linux CI.

### Phase 5 — Disposable Windows/WSL acceptance

Execute the documented flow on a clean, IT-equivalent Windows 11 handoff and fix only issues exposed by that test.

**Definition of Done**

- `setup.ps1` runs without elevation.
- `wsl --install Ubuntu-24.04` consumes the correct user-data file on first launch.
- Cloud-init completes successfully and logs the bootstrap output.
- After `wsl --shutdown` and reopening, the normal user passes all validation without sudo for Docker.
- VS Code can open `~/Developer` through WSL and a representative existing devcontainer starts using the in-WSL Docker Engine.
- The tested versions and any known environmental limitations are recorded.
- The engineer-facing README is corrected to match observed behaviour.

**Stop condition**

Stop after one clean end-to-end pass on the supported platform. Do not generalise the solution to other Ubuntu releases, WSL distributions, or Windows provisioning.

## 9. Human decisions and escalation points

The two material design questions raised during planning are resolved:

- IT Ops owns WSL/Windows readiness; the engineer workflow starts after that boundary.
- The Linux user uses passwordless sudo with a locked password.

No further human decision is required before implementation. Implementation must stop and ask rather than guess if any of the following emerges:

- corporate policy forbids passwordless sudo or requires a specific Linux password/enrolment mechanism;
- outbound access to Ubuntu or Docker repositories requires a corporate proxy, private mirror, or custom CA not already supplied by IT Ops;
- the supported distribution name differs from exactly `Ubuntu-24.04`, because the cloud-init filename must match the installed instance name;
- GitHub Actions cannot access the repository/package sources or organisational policy forbids the proposed integration job;
- IT Ops expects `setup.ps1` to install/launch the distribution despite the explicit boundary chosen here; or
- additional tools are proposed for the shared baseline but their ownership between baseline, dotfiles, and devcontainer is unclear.

Minor implementation details that do not change scope—function names, internal file layout under `/usr/local/lib`, test helper choice, and diagnostic wording—may be resolved by the implementation agent using the simplest maintainable option.

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Cloud-init config is created after the distro has already launched | `setup.ps1` detects an existing `Ubuntu-24.04` registration and fails with an explanation. |
| Bootstrap source changes after user-data generation | Treat generated user-data as an intentional snapshot; rerun `setup.ps1` before installation to regenerate it. |
| Network/package outage leaves partial provisioning | Fail visibly, retain cloud-init logs, and keep bootstrap safe to rerun. |
| Docker group change is not active in the first shell | Require `cloud-init status --wait`, then `wsl --shutdown` and reopen before user-level validation. |
| GitHub runner already contains Docker and masks installation defects | Integration setup removes/neutralises preinstalled Docker state and asserts repository/key contents before validating reinstall. |
| CI passes but WSL-specific first boot is broken | Retain a documented disposable Windows/WSL acceptance gate for relevant releases. |
| Baseline expands into personal tooling | Enforce the responsibility map and package-list test/review; direct convenience tools to dotfiles. |
| Generated YAML is corrupted by quoting or line endings | Constrain username syntax, embed scripts as base64, emit UTF-8 without BOM, and schema/decode-test generated output. |
| Passwordless sudo conflicts with later security policy | Record it prominently as a deliberate choice and treat any policy change as a human decision requiring redesign. |

## 11. Authoritative implementation references

- [Ubuntu: Automatic setup of Ubuntu on WSL with cloud-init](https://documentation.ubuntu.com/wsl/latest/howto/cloud-init/)
- [Ubuntu: Manage and configure instances of Ubuntu on WSL](https://documentation.ubuntu.com/wsl/latest/howto/manage-and-configure/)
- [Microsoft: Install WSL](https://learn.microsoft.com/windows/wsl/install)
- [Microsoft: Basic commands for WSL](https://learn.microsoft.com/windows/wsl/basic-commands)
- [cloud-init module reference (`write_files` and `runcmd`)](https://cloudinit.readthedocs.io/en/latest/reference/modules.html)
- [Docker Engine installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [GitHub-hosted runners reference](https://docs.github.com/actions/reference/runners/github-hosted-runners)

Repository-local requirements remain authoritative for the desired team workflow:

- `setup-instructions.md`
- `implementation-plan-prompt.md`
- `~/Developer/dotfiles-template/README.md`
- `~/Developer/dotfiles-template/bootstrap.sh`
- `~/Developer/dotfiles-template/Brewfile`
