# wsl-agent-sandbox

A reusable setup for running coding agents (GitHub Copilot agent mode, local models via Ollama, and similar) against your projects **inside a dedicated WSL2 distro** that cannot see your Windows drives, so an agent that goes wrong can damage the sandbox but not the rest of your machine.

What you get:

- A dedicated WSL2 Ubuntu distro with Windows drives **not mounted** and Windows interop **off**
- An unprivileged `agent` user with **no sudo** and no `docker` group, plus a separate `wsladmin` user for maintenance
- **Rootless Docker**, so agents can build images, run your stack and read logs without a root-equivalent daemon
- **VS Code Remote - SSH** into the distro over key-only SSH on `127.0.0.1` (the Remote - WSL extension does not work without drive mounts)
- Per-project **deploy keys** and protected branches, so the agent can push branches but not `main`
- A verification script that checks the containment properties

> **Status:** the commands in these scripts come from a setup done by hand on Windows 11, WSL 3.0.1.0 and Ubuntu 24.04. The scripts themselves are a first port of those steps and have **not yet been run end to end**. Treat your first run as a test and fix whatever breaks (see [docs/troubleshooting.md](docs/troubleshooting.md)).

## What this protects against (and what it does not)

Goal: **accidental** damage, namely deleted or overwritten files outside the project, and agents reading or uploading files that were never meant to be in their reach.

It does **not** give you a hard security boundary against a deliberately malicious process: WSL2 distros share one VM and kernel, network egress is open, and you (the Windows user) can always reach into the distro. See [docs/security-model.md](docs/security-model.md).

## Requirements

- Windows 11 22H2 or later (mirrored networking), WSL 2.0.0 or later, virtualization enabled
- Windows OpenSSH client (`ssh -V`), VS Code with the **Remote - SSH** extension
- GitHub access to the repos you want to work on (to add deploy keys)
- Optional: Ollama for Windows, Docker Desktop (for your own use; WSL integration must be **off** for the sandbox distro)

## Quick start

Run in PowerShell from the repository root. `<DISTRO>` is the name in `config.env` (default `sandbox-agent`).

```powershell
Copy-Item config.example.env config.env      # then edit config.env

.\windows\01-create-distro.ps1               # .wslconfig (mirrored networking) + the distro
wsl --shutdown                               # applies .wslconfig; stops ALL running distros

.\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\10-users-and-wslconf.sh
wsl -d <DISTRO> -u root passwd wsladmin      # set the maintenance user's password
wsl --terminate <DISTRO>                     # applies /etc/wsl.conf (systemd on, no drives)

.\windows\Invoke-InDistro.ps1 -User root  -Script .\scripts\wsl\20-packages.sh
.\windows\Invoke-InDistro.ps1 -User root  -Script .\scripts\wsl\30-sshd.sh
.\windows\Invoke-InDistro.ps1 -User agent -Script .\scripts\wsl\40-agent-tools.sh
#   -> add the printed public key as a deploy key on GitHub (write access)

.\windows\02-windows-ssh.ps1                 # Windows login key + ssh config entry
ssh <DISTRO>                                 # should give you a shell as the agent user

.\windows\Invoke-InDistro.ps1 -User agent -Script .\scripts\wsl\45-clone-project.sh   # optional
.\windows\Invoke-InDistro.ps1 -User agent -Script .\scripts\wsl\90-verify.sh
.\windows\open-vscode.ps1
```

The full walkthrough, with explanations and the manual commands, is in [docs/guide.md](docs/guide.md).

## Configuration

Copy `config.example.env` to `config.env` (git-ignored). Everything has a default, so the file is optional. The settings are the distro name, user names, SSH port, optional toolchains (.NET, Node) and an optional project to clone. The scripts read them as environment variables via `windows/Invoke-InDistro.ps1`.

## Repository layout

```
config.example.env          settings template
windows/                    PowerShell, run on the Windows side
  Invoke-InDistro.ps1         runs a bash script in the distro as a chosen user
  01-create-distro.ps1        .wslconfig + distro creation
  02-windows-ssh.ps1          Windows login key, authorized_keys, ssh config entry
  open-vscode.ps1             start the distro and open VS Code over SSH
  Config.ps1                  shared config loader
scripts/wsl/                bash, run inside the distro
  10-users-and-wslconf.sh     users, /etc/wsl.conf                       (root)
  20-packages.sh              packages, Docker Engine, toolchains        (root)
  30-sshd.sh                  key-only sshd on loopback                  (root)
  40-agent-tools.sh           rootless Docker, git defaults, GitHub key  (agent)
  45-clone-project.sh         clone a project                            (agent, optional)
  50-dotnet-sdk.sh            exact .NET SDK from global.json            (root, optional)
  90-verify.sh                containment checks                         (agent)
docs/
  guide.md                    step-by-step guide
  security-model.md           design, guarantees, residual risks
  troubleshooting.md          problems met during the first setup, and their fixes
```

## Using it for other projects

The sandbox is not tied to a project. For another project: set `PROJECT_REPO` (or run `45-clone-project.sh -Env PROJECT_REPO=...`), add a deploy key to that repository, and install whatever toolchain it needs (see "Adding toolchains" in the guide). You can keep one distro for several projects, or create one distro per project by using a different `config.env` (`-ConfigFile` is supported by the scripts).

## License

No license file is included yet. Add one before making the repository public.
