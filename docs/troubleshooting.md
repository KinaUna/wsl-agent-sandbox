# Troubleshooting

Problems met during the first manual setup, with what caused them and how to fix them.

## `fatal: The group 'admin' already exists` when creating the admin user

Ubuntu already has a group called `admin`, and `adduser` creates a group with the same name as the user. Use a different admin user name (default `wsladmin`). `10-users-and-wslconf.sh` checks for this.

## VS Code (Remote - WSL): `Failed to translate ...` / `/scripts/wslServer.sh: not found`

The Remote - WSL extension needs the Windows drives mounted in the distro; this setup turns automount off. Use **Remote - SSH** instead (`.\windows\open-vscode.ps1`). Mounting `C:` only for VS Code would expose your Windows profile to the agent.

## `ps -p 1 -o comm=` does not print `systemd`

`/etc/wsl.conf` needs `[boot]` / `systemd=true`. After writing it run `wsl --terminate <DISTRO>`; if PID 1 is still not systemd, run `wsl --shutdown` (stops all distros) and retry. `systemctl is-system-running` printing `degraded` is common in WSL and not a problem by itself.

## `openssh-server` install fails: `Could not execute systemctl` / `dpkg ... exit status 1`

Seen on the first setup. The suspected cause (not confirmed) is that the package's first start of `ssh.socket` on port 22 clashed with a port already in use on the shared mirrored network. `30-sshd.sh` puts the port override in place before installing. If the install still fails, finish it and re-run the script:

```powershell
.\windows\Invoke-InDistro.ps1 -User root -ScriptText 'dpkg --configure -a'
.\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\30-sshd.sh
```

## `Connection refused` on `ssh <DISTRO>`

The distro is not running (WSL stops idle distros, and does not start them at boot). Run `wsl -d <DISTRO> -e true` and retry. Then check from inside the distro: `ss -ltn | grep <SSH_PORT>` should show `127.0.0.1:<SSH_PORT>`.

## VS Code: "Workspace Requirements Not Met: global.json specifies SDK x.y.z, which is not installed"

The distro has a different .NET SDK than the project pins. Install the exact version with `scripts/wsl/50-dotnet-sdk.sh` (see the guide, step 7), then **Developer: Reload Window**.

## `40-agent-tools.sh`: `/run/user/<uid> does not exist`

Lingering is not active for the agent user, so there is no user systemd session. Run `20-packages.sh` (it runs `loginctl enable-linger`), then `wsl --terminate <DISTRO>` and retry.

## Mirrored networking seems inactive

After editing `.wslconfig` you must run `wsl --shutdown`. Inside the distro, `ip addr` should show the same addresses as `ipconfig` on Windows, and `curl http://localhost:11434/api/tags` should reach Ollama on Windows. Mirrored mode requires Windows 11 22H2 or later and a recent WSL.

## Ports already in use

With mirrored networking the distro, Windows and your other distros share ports. Pick different host ports for the sandbox's containers than your Docker Desktop ones.

## `Invoke-InDistro.ps1` cannot stage the script

The distro or the user does not exist yet (`wsl -l -v`), or `wsl.exe` printed something unexpected before the temp-file path; the error message includes the output. Check that the `-User` name matches `ADMIN_USER` / `AGENT_USER` in `config.env`.

## Bash errors like `\r: command not found`

A script was checked out with Windows line endings. `.gitattributes` forces LF for `*.sh`; after changing it run `git add --renormalize .` and re-checkout the files.
