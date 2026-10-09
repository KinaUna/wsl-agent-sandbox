# Guide

Step-by-step setup. The scripts are the source of truth for the exact commands; this guide explains what each step does and why, and what to do when something goes wrong. Run everything from the repository root in PowerShell. `<DISTRO>` is the name in `config.env` (default `sandbox-agent`).

## 0. Before you start

- Windows 11 22H2 or later, WSL 2.0.0+ (`wsl --version`), virtualization enabled
- `ssh -V` works in PowerShell (Windows OpenSSH client)
- VS Code with the **Remote - SSH** extension (`ms-vscode-remote.remote-ssh`). Do **not** use Remote - WSL for this distro: it launches its server from your Windows profile and needs the Windows drives mounted, which this setup deliberately disables.
- `Copy-Item config.example.env config.env` and review the settings

Allowed characters in `config.env` values: letters, digits and `_ . : / @ + , -` (no spaces or quotes). Comments go on their own lines.

## 1. Create the distro

```powershell
.\windows\01-create-distro.ps1
wsl --shutdown
```

- Creates `%USERPROFILE%\.wslconfig` with `networkingMode=mirrored` if it does not exist. An existing file is never edited: you get a warning and add the line yourself.
- `.wslconfig` is **global**: it applies to every WSL2 distro. With mirrored networking the distro shares the host's network interfaces, so `localhost` works in both directions (Ollama on Windows from the distro, container ports from Windows) and ports are shared with Windows and your other distros.
- `wsl --shutdown` is needed once for `.wslconfig` to take effect; it stops all distros.
- The `[wsl2]` section name refers to the WSL 2 virtual machine, not the WSL package version.

If `wsl --install --name` is not supported by your WSL version, the script prints the install/export/import fallback.

## 2. Users and WSL settings

```powershell
.\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\10-users-and-wslconf.sh
wsl -d <DISTRO> -u root passwd wsladmin
wsl --terminate <DISTRO>
```

- Creates `wsladmin` (sudo, for maintenance) and `agent` (no sudo, no docker group, default login).
- Do **not** name the admin user `admin`: Ubuntu already has a group of that name and `adduser` fails with "The group `admin' already exists". The script checks for this.
- Writes `/etc/wsl.conf`: systemd on, default user `agent`, **automount off** (no `/mnt/c`), **interop off** (no launching Windows programs). The old file is backed up.
- `wsl --terminate` makes WSL read the new file. Check systemd is running: `.\windows\Invoke-InDistro.ps1 -User root -ScriptText 'ps -p 1 -o comm='` prints `systemd`. If it does not, run `wsl --shutdown` and retry. (`systemctl is-system-running` saying `degraded` is common in WSL and not a problem by itself.)

## 3. Packages and Docker Engine

```powershell
.\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\20-packages.sh
```

Installs base tools, Docker Engine from Docker's apt repository, and disables the **rootful** Docker daemon. Enables lingering for the agent user so its rootless Docker keeps running without a login session. Optional toolchains are controlled by `INSTALL_DOTNET` / `INSTALL_NODE` in `config.env`.

## 4. SSH server (loopback, key-only)

```powershell
.\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\30-sshd.sh
```

- sshd listens on `127.0.0.1:<SSH_PORT>` only, key-only, `AllowUsers <agent>`.
- Ubuntu 24.04 starts sshd through `ssh.socket`, which ignores `Port`/`ListenAddress` in `sshd_config`; the script sets the address on the socket unit. It does this **before** installing the package, because the package otherwise starts sshd on port 22 right away, and with mirrored networking that can clash with Windows.
- The script ends by verifying that nothing listens beyond loopback.

## 5. Agent tools: rootless Docker, git, GitHub key

```powershell
.\windows\Invoke-InDistro.ps1 -User agent -Script .\scripts\wsl\40-agent-tools.sh
```

Sets up rootless Docker for the agent user, git defaults, and generates a GitHub SSH key (`~/.ssh/id_ed25519_github`). Add the printed public key as a **deploy key with write access** on each repository the agent should push to (GitHub: repository, Settings, Deploy keys). One key per machine. Protect `main` with a ruleset (require a pull request, block force-push and deletion) so the agent can only push branches.

Set the git identity inside the distro (`ssh <DISTRO>` after step 6, or `wsl -d <DISTRO>`):

```bash
git config --global user.name "Your Name (agent)"
git config --global user.email "you@example.com"
```

## 6. Windows login key for VS Code

```powershell
.\windows\02-windows-ssh.ps1
ssh <DISTRO>
```

Creates a key pair on Windows (use a **passphrase**: this key grants access to the sandbox account), authorizes it for the agent user, and adds a `Host <DISTRO>` block to `%USERPROFILE%\.ssh\config`. `ssh <DISTRO>` should give you a shell as the agent user. If the connection is refused, start the distro first: `wsl -d <DISTRO> -e true`.

## 7. A project

```powershell
.\windows\Invoke-InDistro.ps1 -User agent -Script .\scripts\wsl\45-clone-project.sh -Env PROJECT_REPO=git@github.com:owner/repo.git
```

Push or stash uncommitted work from your Windows copy first; the clone starts from GitHub. Install the project's dependencies from inside the distro (`npm install`, `dotnet restore`, and so on).

If the project pins a .NET SDK in `global.json` (VS Code reports "Workspace Requirements Not Met: global.json specifies SDK ... which is not installed"):

```powershell
.\windows\Invoke-InDistro.ps1 -User agent -ScriptText 'jq -r .sdk.version ~/projects/<repo>/global.json'
.\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\50-dotnet-sdk.sh -Env SDK_VERSION=<version printed above>
```

Then run **Developer: Reload Window** in VS Code.

### Adding toolchains

Install other toolchains system-wide as root, for example:

```powershell
.\windows\Invoke-InDistro.ps1 -User root -ScriptText 'apt-get update && apt-get install -y python3 python3-venv python3-pip'
```

Keep project-specific tools in the project (lockfiles, `global.json`, `.nvmrc`) rather than baking them into the distro.

## 8. VS Code, Copilot and local models

```powershell
.\windows\open-vscode.ps1                      # or:  -Folder /home/agent/projects/<repo>
```

This starts the distro and runs `code --remote ssh-remote+<DISTRO> <folder>`. The first connect downloads the VS Code server inside the distro and may ask for your key passphrase.

- Install Copilot and Copilot Chat **on the SSH host** (extensions view, "Install in SSH: <DISTRO>"), plus the language extensions the project needs.
- Keep terminal-command auto-approval off at first; allow-list only harmless commands (build, test, `docker compose logs`) later. Keep Workspace Trust on.
- Put no real secrets in the distro: dev-only configuration with dummy values, no cloud logins, no personal tokens.
- **Ollama:** run Ollama for Windows (`http://localhost:11434`). With mirrored networking the distro reaches it on `localhost`. Add it in Copilot Chat's model picker (Manage Models). If it cannot connect, set the Ollama endpoint in the **remote (SSH host)** settings; at the time of writing the setting is `github.copilot.chat.byok.ollamaEndpoint`, so check the settings UI. Agent mode needs a model with tool-calling support.

## 9. Docker Desktop (if installed)

- Docker Desktop, Settings, Resources, WSL integration: turn **off** for the sandbox distro. Otherwise the agent gets Desktop's root-equivalent daemon.
- Mirrored networking shares `localhost` between Windows and the distro, so publish the sandbox's containers on different host ports than your Docker Desktop ones (for example Postgres on 5433).
- Rootless Docker cannot bind ports below 1024.
- `/mnt/wsl` is shared between WSL distros and Docker Desktop publishes proxy sockets there. Whether a non-integrated distro can use them is **not verified**; `90-verify.sh` tests it. If it reports a reachable daemon, quit Docker Desktop while agents run, or stop using it on that machine.

## 10. Verify

```powershell
.\windows\Invoke-InDistro.ps1 -User agent -Script .\scripts\wsl\90-verify.sh
```

Also check by hand from PowerShell:

| Test | Expected |
|---|---|
| `ssh -o PubkeyAuthentication=no -p <SSH_PORT> <agent>@127.0.0.1` | `Permission denied (publickey)` |
| `ssh -p <SSH_PORT> <wsladmin>@127.0.0.1` | denied (only the agent user is allowed) |
| `git push origin HEAD:main` (inside the distro) | rejected by branch protection |
| `git push origin HEAD:some-branch` | accepted |
| `.\windows\open-vscode.ps1` | VS Code opens the project on the SSH host |

## 11. Operating it

- Maintenance: `wsl -d <DISTRO> -u <ADMIN_USER>`, then `sudo ...`. As the Windows user you can also always use `wsl -d <DISTRO> -u root`.
- The distro must be running before you connect (`wsl -d <DISTRO> -e true`). Whether it stays up while only sshd and VS Code are connected is untested; if it keeps stopping, run a Windows scheduled task at logon that keeps a process running in the distro.
- Anything not pushed to GitHub exists only in the distro's virtual disk, and `wsl --unregister` deletes it permanently. Back up with `wsl --export <DISTRO> D:\backups\<DISTRO>.tar`.
- Browse the files from Windows at `\\wsl.localhost\<DISTRO>\home\<agent>`.
- Updates: `sudo apt update && sudo apt upgrade` as the admin user; pull container images; re-run `50-dotnet-sdk.sh` when a project's pinned SDK changes.

## 12. Per-machine checklist

1. [ ] Windows 11 22H2+, WSL updated, `ssh -V` works, VS Code + Remote - SSH installed
2. [ ] `config.env` created
3. [ ] `01-create-distro.ps1`, then `wsl --shutdown`
4. [ ] `10-users-and-wslconf.sh`, admin password set, `wsl --terminate`, PID 1 is systemd
5. [ ] `20-packages.sh`
6. [ ] `30-sshd.sh` (loopback-only check passes)
7. [ ] `40-agent-tools.sh`, deploy key added on GitHub, `main` protected, git identity set
8. [ ] `02-windows-ssh.ps1`, `ssh <DISTRO>` works
9. [ ] Docker Desktop WSL integration off for the distro
10. [ ] Project cloned, dependencies installed, SDK pinned versions installed if needed
11. [ ] VS Code connected, Copilot extensions installed on the SSH host
12. [ ] Ollama reachable (optional)
13. [ ] `90-verify.sh` passes
