#!/usr/bin/env bash
# Step 5 (run as the agent user): rootless Docker, git defaults, and a dedicated GitHub SSH key.
#
#   .\windows\Invoke-InDistro.ps1 -User agent -Script .\scripts\wsl\40-agent-tools.sh
#
# Git identity is not set here (names contain spaces); run once inside the distro:
#   git config --global user.name "Your Name (agent)"
#   git config --global user.email "you@example.com"
set -euo pipefail

: "${DISTRO:=sandbox-agent}"
: "${INSTALL_DOTNET:=0}"
: "${INSTALL_DOTNET_EF:=0}"

[ "$(id -u)" -ne 0 ] || { echo "ERROR: run this as the agent user, not root" >&2; exit 1; }

# A non-interactive wsl.exe session has no user systemd environment; point at the one that
# lingering keeps alive for this user.
XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_RUNTIME_DIR
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
  echo "ERROR: $XDG_RUNTIME_DIR does not exist. Run 20-packages.sh (it enables lingering for this user)," >&2
  echo "       then 'wsl --terminate ${DISTRO}' and try again." >&2
  exit 1
fi
export PATH="/usr/bin:$PATH"

# --- rootless Docker ---
if systemctl --user is-active --quiet docker.service 2>/dev/null; then
  echo "Rootless Docker is already running."
else
  dockerd-rootless-setuptool.sh install
fi

add_line() { # add_line FILE LINE  (idempotent)
  grep -qxF "$2" "$1" 2>/dev/null || echo "$2" >> "$1"
}
touch ~/.bashrc
add_line ~/.bashrc 'export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock'

# --- optional dotnet-ef tool ---
if [ "$INSTALL_DOTNET" = "1" ] && [ "$INSTALL_DOTNET_EF" = "1" ]; then
  dotnet tool install --global dotnet-ef || dotnet tool update --global dotnet-ef
  add_line ~/.bashrc 'export PATH="$HOME/.dotnet/tools:$PATH"'
fi

# --- git defaults ---
git config --global init.defaultBranch main
git config --global core.autocrlf input

# --- dedicated GitHub key (separate from the Windows -> distro login key) ---
mkdir -p ~/.ssh && chmod 700 ~/.ssh
key=~/.ssh/id_ed25519_github
if [ ! -f "$key" ]; then
  ssh-keygen -t ed25519 -C "${DISTRO}@$(hostname)" -f "$key" -N ""
fi
touch ~/.ssh/known_hosts ~/.ssh/config
chmod 600 ~/.ssh/config
if ! ssh-keygen -F github.com -f ~/.ssh/known_hosts >/dev/null 2>&1; then
  # Trust-on-first-use. Compare with https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
  ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
fi
if ! grep -q '^Host github.com$' ~/.ssh/config; then
  cat >> ~/.ssh/config <<'EOF'

Host github.com
  IdentityFile ~/.ssh/id_ed25519_github
  IdentitiesOnly yes
EOF
fi

echo
echo "Add this public key as a DEPLOY KEY (write access) on each repository the agent should push to:"
echo "(GitHub: repository > Settings > Deploy keys). One key per machine; protect main with a ruleset."
echo
cat "${key}.pub"
echo
echo "Next: .\\windows\\02-windows-ssh.ps1  (then optionally 45-clone-project.sh)"
