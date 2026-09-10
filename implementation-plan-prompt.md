# WSL2 Developer Environment Automation

Create an implementation plan for automating the initial WSL2 development environment used by our Data Engineering team.

## Context

At present, setting up a new engineer’s WSL2 environment involves a manual process documented in windows-11-wsl2-development-environment-setup-2026-08-20.md.

This is the first new engineer we’ve recruited in approximately five years, so this isn’t a high-frequency onboarding process. The solution should therefore favour simplicity, reproducibility and low maintenance rather than introducing infrastructure that only provides value at scale.

Windows workstation configuration is explicitly out of scope. Engineers don’t have Windows administrator access. IT Ops prepares the Windows laptop and installs applications such as VS Code before handing it to the engineer.

The automation begins with the engineer being able to open PowerShell and install/use WSL.

Read the existing setup document: `~/Developer/wsl2-cloud-init/setup-instructions.md` before planning the implementation so that the current tooling and configuration requirements are understood.

## Architecture decision

Standard Ubuntu 24.04 WSL2 + cloud-init + a Bash bootstrap script.

The objective is to retain the standard Ubuntu WSL distribution while automatically configuring it into the baseline environment required by the Data Engineering team.

## Repository

Keep the entire WSL onboarding implementation in one repository.

There is no requirement to separate cloud-init, bootstrap logic or supporting scripts into independently versioned repositories or artifacts.

A possible structure is:

wsl-development-environment/
├── README.md
├── setup.ps1
├── cloud-init/
│   └── Ubuntu-24.04.user-data.template
├── scripts/
│   ├── bootstrap.sh
│   └── validate.sh
└── tests/

Treat this as indicative rather than mandatory. Recommend a better structure if there is a clear technical reason.

## PowerShell setup

Provide a small setup.ps1 script that runs without requiring Windows administrator privileges.

Its responsibility should be limited primarily to preparing cloud-init for the new WSL installation.

It should collect whatever user-specific information is genuinely required by provisioning, for example:

* Linux username
* Full name
* Work email

Determine exactly which values are actually necessary rather than automatically implementing all of these.

The script should use those values to generate the appropriate Ubuntu 24.04 cloud-init user-data file under the Windows user’s .cloud-init directory.

Avoid putting Linux provisioning logic into PowerShell.

Once configuration is ready, the engineer should be able to install the standard Ubuntu 24.04 WSL distribution using:

`wsl --install Ubuntu-24.04`

Determine whether setup.ps1 should invoke this itself or instruct the engineer to run it afterwards. Prefer the simplest and most reliable onboarding experience within the no-admin constraint.

## Cloud-init

Cloud-init is responsible for orchestrating first-boot configuration of the Ubuntu WSL environment.

Keep the cloud-init configuration relatively small. Don’t implement substantial provisioning logic directly in YAML if it can be expressed and tested more cleanly in Bash.

Cloud-init should invoke bootstrap.sh to perform most of the Linux environment provisioning.

Determine the cleanest way for the generated cloud-init configuration to make the repository’s bootstrap.sh available inside the new WSL environment. The solution should remain self-contained and reliable without introducing unnecessary repositories, release processes or infrastructure.

## bootstrap.sh

bootstrap.sh should automate the machine-level WSL configuration currently performed manually.

Use the attached/current setup documentation as the source for the exact requirements.

Responsibilities are expected to include things such as:

* updating the Ubuntu package indexes/packages;
* installing Git;
* installing the OpenSSH client and other common prerequisites;
* installing and configuring Docker Engine;
* installing Docker Compose/Buildx as required;
* ensuring Docker operates correctly under WSL/systemd;
* configuring the engineer’s user appropriately for Docker;
* creating the standard ~/Developer directory;
* applying any other shared machine-level prerequisites currently required by our development workflow.

Project-specific dependencies should not be moved into WSL. These continue to belong in each project’s devcontainer.

Where practical, make bootstrap.sh safe and predictable to rerun, although supporting centrally managed ongoing updates isn’t a requirement.

## Dotfiles

Personal developer configuration should not be baked into the WSL baseline.

A template repository already exists:
`~/Developer/dotfiles-template/`

A new engineer who doesn’t already maintain their own dotfiles can create a repository from this template. Engineers who already have their own dotfiles can continue using them.

Use dotfiles for appropriate personalised/developer-specific configuration and tooling rather than duplicating it in the WSL bootstrap.

The intended separation is broadly:

WSL provisioning
────────────────
Ubuntu/WSL baseline
Docker
Git
SSH client
systemd/WSL configuration
common prerequisites
~/Developer
Dotfiles
────────
shell configuration
prompt
editor/terminal preferences
aliases
personal tooling
Git personalisation
other developer-specific configuration

Review the existing setup instructions when determining exactly where individual configuration belongs.

## SSH and GitHub

GitHub account configuration and authentication should remain deliberate user actions.

In particular:

Do not automate uploading SSH public keys to GitHub.

Provisioning may install the SSH tooling required by the engineer. Key generation may either remain documented as a manual onboarding step or be assisted locally if there is a compelling reason, but adding the resulting public key to GitHub must be performed manually by the engineer.

GitHub/Copilot authentication should likewise remain outside machine provisioning where it requires the engineer’s identity/account interaction.

## Validation and automated testing

Add automated tests around the provisioning process, particularly bootstrap.sh.

The objective isn’t simply to lint the scripts. CI should give us reasonable confidence that changes to the provisioning repository would still result in a usable WSL development baseline.

Investigate what can realistically be tested in GitHub Actions and recommend an appropriate testing strategy.

Also consider providing a validate.sh script that can verify a completed installation.

Expected validation may include checks such as:

Git installed                 ✓
Docker installed              ✓
Docker daemon operational     ✓
Docker Compose available      ✓
Docker Buildx available       ✓
systemd operational           ✓
correct Docker permissions    ✓
~/Developer exists            ✓
required baseline tools       ✓

Determine the appropriate checks from the actual setup requirements.

## Intended onboarding experience

Aim for an onboarding process approximately like:

1. IT Ops supplies the configured Windows laptop.
2. Engineer obtains the WSL setup repository.
3. Engineer runs:
      .\setup.ps1
4. setup.ps1 gathers the small amount of required personal information
   and prepares cloud-init.
5. Engineer installs Ubuntu 24.04:
      `wsl --install Ubuntu-24.04`
   (unless there is a good reason for setup.ps1 to invoke this itself).
6. Ubuntu starts and cloud-init automatically runs bootstrap.sh.
7. Provisioning completes and validate.sh confirms that the WSL
   baseline is working.
8. Engineer sets up their dotfiles, using dotfiles-template if required.
9. Engineer creates/configures their SSH keys as necessary and manually
   adds the public key(s) to GitHub.
10. Engineer completes any GitHub/Copilot authentication.
11. Engineer can clone the required repositories and work through their
    existing devcontainers.

The desired result is that the existing lengthy manual WSL package/configuration process largely disappears. What remains should primarily be personal configuration and account authentication, rather than Linux environment provisioning.

## Implementation plan required

Do not implement anything yet.

First inspect the existing WSL setup documentation and, where useful, the existing dotfiles-template repository.

Then produce a concrete implementation plan.

The plan should:

1. Confirm the proposed architecture and identify any technical issues that need resolving before implementation.
2. Map the relevant steps from the existing manual setup guide to:
    * setup.ps1;
    * cloud-init;
    * bootstrap.sh;
    * dotfiles;
    * deliberate manual onboarding steps.
3. Define the proposed repository structure.
4. Explain how setup.ps1, cloud-init and bootstrap.sh interact during first installation.
5. Determine how bootstrap.sh should be made available to cloud-init during first boot.
6. Define the automated testing and validation strategy.
7. Break implementation into logical phases.
8. Give every phase a clear Definition of Done and stop condition, so that individual phases can subsequently be handed to an implementation agent in separate sessions.
9. Identify decisions or ambiguities that genuinely require human input rather than silently making assumptions.

Optimise for the simplest reliable implementation. Don’t introduce additional repositories, image-building pipelines, scheduled rebuilds, central update infrastructure or other operational machinery unless there is a concrete requirement that cannot reasonably be satisfied without them.

Write out the plan to a markdown repository in the repo.
