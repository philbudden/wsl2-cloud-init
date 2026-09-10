---
title: Windows 11 WSL2 Development Environment Setup
type: working-note
status: current
created: 2026-08-20
updated: 2026-08-20
tags:
  - work
---

# Windows 11 WSL2 Development Environment Setup

This note captures the Windows 11 + WSL2 development environment setup tested successfully on a clean Windows 11 machine. It is a reusable implementation guide for a Windows host where WSL2 acts as the real development workstation, VS Code provides the graphical interface, and project-specific devcontainers run on Docker Engine inside WSL.

## Target architecture

- Windows 11 is the physical host.
- VS Code runs as a native Windows application.
- WSL2 / Ubuntu is the main development environment.
- Repositories live inside WSL under `~/Developer`.
- Docker Engine runs directly inside WSL, with no Docker Desktop.
- VS Code connects to WSL and uses Dev Containers against the Docker Engine inside WSL.
- Personal and work GitHub accounts coexist using separate SSH keys.
- Git automatically selects the appropriate commit identity according to the GitHub organisation.
- GitHub Copilot uses the personal GitHub account in VS Code.
- Container Tools provides graphical container management.
- Codex can be installed into the WSL VS Code environment if OpenAI authentication is available.

## 1. Install WSL2 and Ubuntu

Install WSL2 and Ubuntu using the normal Windows installation process. Once Ubuntu is running, update its package information:

```shell
sudo apt update
```

## 2. Install VS Code and connect it to WSL

Install VS Code on Windows. Install the WSL extension in VS Code.

In Ubuntu:

```shell
mkdir -p ~/Developer
cd ~/Developer
code .
```

Windows VS Code should open connected to Ubuntu. Confirm the bottom-left status area shows:

```text
WSL: Ubuntu
```

Use `~/Developer` for repositories rather than storing them under `/mnt/c/...`.

## 3. Configure GitHub Copilot

In Windows VS Code, sign into the personal GitHub account that has the GitHub Copilot Pro subscription. Install or enable GitHub Copilot and confirm it works.

GitHub Copilot authentication is separate from the SSH identities configured later for repository access.

## 4. Install Docker Engine inside WSL

Run all commands in Ubuntu.

Install prerequisites:

```shell
sudo apt install -y ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc

sudo chmod a+r /etc/apt/keyrings/docker.asc
```

Determine the Ubuntu codename:

```shell
. /etc/os-release
echo "$VERSION_CODENAME"
```

Create Docker's apt source, replacing `YOUR_UBUNTU_CODENAME` with the value returned above:

```shell
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: YOUR_UBUNTU_CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
```

Then:

```shell
sudo apt update
```

Install Docker Engine and supporting tools:

```shell
sudo apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
```

Allow the current WSL user to run Docker without `sudo`:

```shell
sudo usermod -aG docker $USER
```

Close Ubuntu. From PowerShell or Windows Terminal:

```powershell
wsl --shutdown
```

Reopen Ubuntu and verify:

```shell
docker version
docker compose version
docker run hello-world
```

`docker run hello-world` should succeed without `sudo`.

## 5. Configure VS Code Dev Containers

Open a repository or directory from WSL:

```shell
cd ~/Developer
code .
```

Install the Microsoft Dev Containers extension in `WSL: Ubuntu`.

For repositories containing:

```text
.devcontainer/devcontainer.json
```

Open the repository from WSL:

```shell
cd ~/Developer/<repo>
code .
```

Then select:

```text
Dev Containers: Reopen in Container
```

VS Code should use the Docker Engine running inside WSL to build and start the devcontainer, then reconnect to it.

The resulting chain is:

```text
Windows VS Code
    |
WSL2 Ubuntu
    |
Docker Engine
    |
Dev Container
```

No Docker Desktop or DevPod is required.

## 6. Configure graphical container management

While VS Code is connected to `WSL: Ubuntu`, install Microsoft's Container Tools extension into WSL. The Container Tools sidebar should display containers managed by the Docker Engine inside WSL.

If it reports:

> Failed to connect. Is Docker installed?

Check that:

1. VS Code is currently connected to `WSL: Ubuntu`.
2. Container Tools is installed in WSL, rather than only on the Windows host.
3. `docker ps` works from the WSL terminal.

## 7. Create the personal GitHub SSH identity

Inside WSL:

```shell
mkdir -p ~/.ssh
chmod 700 ~/.ssh

ssh-keygen -t ed25519 \
  -C "PERSONAL_GITHUB_EMAIL" \
  -f ~/.ssh/id_ed25519_github_personal
```

Display the public key:

```shell
cat ~/.ssh/id_ed25519_github_personal.pub
```

Add it to the personal GitHub account under:

```text
GitHub -> Settings -> SSH and GPG keys -> New SSH key
```

Edit the SSH configuration:

```shell
vim ~/.ssh/config
```

Add:

```sshconfig
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github_personal
    IdentitiesOnly yes
```

Secure it:

```shell
chmod 600 ~/.ssh/config
```

Test:

```shell
ssh -T git@github.com
```

GitHub should return a greeting identifying the personal account. Legacy-organisation repositories can then use normal SSH URLs such as:

```text
git@github.com:LEGACY-ORG/repository.git
```

## 8. Create the work GitHub SSH identity

Generate a separate key:

```shell
ssh-keygen -t ed25519 \
  -C "WORK_GITHUB_EMAIL" \
  -f ~/.ssh/id_ed25519_github_work
```

Display the public key:

```shell
cat ~/.ssh/id_ed25519_github_work.pub
```

Add it to the separate work GitHub account.

Edit:

```shell
vim ~/.ssh/config
```

Add:

```sshconfig
Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github_work
    IdentitiesOnly yes
```

Test:

```shell
ssh -T git@github-work
```

GitHub should greet the work account. Repositories in the new organisation should then be cloned using the alias:

```shell
git clone git@github-work:NEW-ORG/repository.git
```

This makes repository authentication deterministic without manually switching GitHub accounts.

## 9. Configure automatic Git commit identities

Use the GitHub-provided `users.noreply.github.com` address associated with each account if email privacy is desired.

Create:

```shell
vim ~/.gitconfig-personal
```

With:

```ini
[user]
    name = YOUR_NAME
    email = PERSONAL_GITHUB_NOREPLY_EMAIL
```

Create:

```shell
vim ~/.gitconfig-work
```

With:

```ini
[user]
    name = YOUR_NAME
    email = WORK_GITHUB_NOREPLY_EMAIL
```

Then edit:

```shell
vim ~/.gitconfig
```

Configure organisation-specific conditional includes:

```ini
[includeIf "hasconfig:remote.*.url:git@github.com:LEGACY-ORG/**"]
    path = ~/.gitconfig-personal

[includeIf "hasconfig:remote.*.url:git@github-work:NEW-ORG/**"]
    path = ~/.gitconfig-work
```

The organisation names in these URL patterns are case-sensitive. Use exactly the casing present in the repository remote URL.

For example, inspect the remote with:

```shell
git remote get-url origin
```

Verify the selected identity from inside a repository:

```shell
git config --show-origin --get user.name
git config --show-origin --get user.email
```

A legacy-organisation repository should return the personal GitHub identity. A new-organisation repository should return the work GitHub identity.

## 10. Normal repository workflow

For a legacy repository:

```shell
cd ~/Developer
git clone git@github.com:LEGACY-ORG/repository.git
cd repository
code .
```

For a new-organisation repository:

```shell
cd ~/Developer
git clone git@github-work:NEW-ORG/repository.git
cd repository
code .
```

VS Code opens connected to WSL. If the repository has a devcontainer configuration, select:

```text
Dev Containers: Reopen in Container
```

Normal Git operations such as fetch, pull, and push then use the correct SSH identity automatically.

GitHub Copilot continues using the personal GitHub account configured in VS Code independently of the repository SSH identity.

## 11. Optional Codex setup

While VS Code is connected to `WSL: Ubuntu`, not inside an individual devcontainer, install the official OpenAI Codex extension into WSL.

The desired arrangement is:

```text
Windows VS Code UI
        |
WSL2 Ubuntu
   |-- Git
   |-- Docker
   |-- Codex
   `-- repositories
        |
   Dev Containers
```

Codex authentication opens an OpenAI browser authentication flow.

On a corporate laptop this may be unavailable if OpenAI or ChatGPT authentication is blocked. The environment remains fully usable with GitHub Copilot if Codex cannot authenticate.

Do not use unofficial extensions, copied credentials, or API-key workarounds merely to bypass that restriction.

## 12. Extensions required

The core VS Code extensions for this setup are:

- WSL: connects the Windows VS Code UI to Ubuntu.
- Dev Containers: creates and manages project devcontainers using Docker inside WSL.
- GitHub Copilot: AI-assisted development using the personal Copilot Pro account.
- Container Tools: graphical management of the WSL Docker environment.

Optional:

- OpenAI Codex: additional coding and review agent if authentication is permitted.
- GitHub Pull Requests and Issues: richer PR integration inside VS Code.
- CodeRabbit: local CodeRabbit review if desired.

GitHub CLI (`gh`) is not required for this workflow.

## Final architecture

```text
Windows 11
|
`-- VS Code
    |
    |-- GitHub Copilot
    |   `-- Personal GitHub account / Copilot Pro
    |
    `-- WSL: Ubuntu
        |
        |-- ~/Developer
        |   `-- repositories
        |
        |-- Git
        |   |-- Personal SSH identity -> legacy organisation
        |   `-- Work SSH identity -> new organisation
        |
        |-- Docker Engine
        |   `-- Dev Containers
        |
        |-- Container Tools
        |
        `-- Codex (if authentication is available)
```

The guiding principle is:

> **WSL is the development workstation. Devcontainers are the individual project environments. Windows primarily provides the VS Code graphical interface.**

## Next use

Use this note as the canonical checklist when setting up or validating a Windows 11 development workstation that should behave like the user's preferred WSL-first, devcontainer-capable environment. Once the setup pattern is no longer active or has been superseded, reclassify this note to `reference` and record the reason.
