# Security model

## Goal

Protect against **accidental** damage by an agent: deleting or overwriting files outside the project, and reading or sending files that were never meant to be in its reach. This is strong containment, not a guarantee against deliberately malicious code.

## Layers

| Layer | What it does |
|---|---|
| Dedicated WSL2 distro | The agent only sees the distro's own filesystem |
| `automount` off, interop off (`/etc/wsl.conf`) | No `/mnt/c` or `/mnt/e`; cannot launch `cmd.exe` or `powershell.exe` |
| Agent user without sudo, not in `docker` | Cannot mount drives, install system packages or edit `/etc` |
| Separate admin user | Privileged work happens in a different account the agent never runs as |
| Rootless Docker for the agent | No root-equivalent daemon; containers can only touch what the agent user can already write |
| Rootful Docker daemon disabled | The root daemon from the Docker packages never runs |
| Docker Desktop WSL integration off for the distro | The agent does not get Desktop's daemon |
| Project cloned inside the distro | The Windows copy of the project is not exposed |
| Per-repository deploy key, protected `main` | The agent can push branches to the repositories you chose, not to `main` |
| sshd on `127.0.0.1`, key-only, agent only | VS Code gets in; the LAN does not |
| Mirrored networking | `localhost` works both ways (Ollama on Windows, container ports) |

## Why Remote - WSL is not used

VS Code's Remote - WSL extension starts its server from your Windows profile (`C:\Users\<you>\.vscode\extensions\...`) and needs WSL to translate Windows paths to `/mnt/c/...`. With `automount` off that fails with `Failed to translate ...` and `/scripts/wslServer.sh: not found`. Mounting a drive just for VS Code would expose your Windows profile to the agent, so this setup uses Remote - SSH instead.

## Residual risks

- **Not a hard boundary.** All WSL2 distros share one VM and kernel; a kernel-level escape is theoretically possible.
- **The agent can destroy its own workspace.** It can delete anything in its distro and in the project folder. Frequent commits and pushes (to non-protected branches) are the safety net.
- **Network egress is open.** A deploy key limits what the agent can push, but it can still send data to the internet.
- **Local access to sshd.** With mirrored networking, `localhost:<SSH_PORT>` is reachable by any local process on your Windows machine. sshd is key-only and allows only the agent user. Protect the Windows private key with a passphrase: it grants access to the sandbox account.
- **Docker Desktop's sockets (unverified).** `/mnt/wsl` is shared between WSL distros and Docker Desktop publishes proxy sockets there. If a non-integrated distro can use them, the rootless setup is bypassed. `scripts/wsl/90-verify.sh` tests this. Mitigation: quit Docker Desktop while agents run, or do not use it on that machine.
- **You can always reach into the distro** (`wsl -u root`); the agent cannot reach back into Windows.
- **Trust on first use.** `40-agent-tools.sh` fetches GitHub's host key with `ssh-keyscan`; compare it with GitHub's published fingerprints if that matters to you.
- **Supply chain.** Packages come from Ubuntu, Docker and (optionally) NodeSource and Microsoft over HTTPS. Review `20-packages.sh` before you run it.

## Rootless Docker limits

No ports below 1024; `--privileged` has no real host power; some networking features (host networking, ping) behave differently. If `dockerd-rootless-setuptool.sh` fails on user namespaces, see the Troubleshooting section of Docker's rootless documentation (Ubuntu 24.04 can restrict unprivileged user namespaces).
