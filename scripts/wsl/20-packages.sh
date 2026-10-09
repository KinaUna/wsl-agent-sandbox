#!/usr/bin/env bash
# Step 3 (run as root): base packages, Docker Engine (rootful daemon disabled), optional
# toolchains, and lingering for the agent user's services (rootless Docker).
#
#   .\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\20-packages.sh
#
# Requires systemd as PID 1 (set by 10-users-and-wslconf.sh after "wsl --terminate").
set -euo pipefail

: "${AGENT_USER:=agent}"
: "${INSTALL_DOTNET:=0}"
: "${DOTNET_CHANNEL:=10.0}"
: "${INSTALL_NODE:=0}"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run this as root" >&2; exit 1; }

if [ "$(ps -p 1 -o comm= | tr -d ' ')" != "systemd" ]; then
  echo "ERROR: systemd is not PID 1. Check /etc/wsl.conf has [boot] systemd=true, then run" >&2
  echo "       'wsl --shutdown' from Windows and try again." >&2
  exit 1
fi
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
  echo "ERROR: these scripts target Ubuntu (found ID=${ID:-unknown})" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -y -o Dpkg::Options::=--force-confold)

"${APT[@]}" update
"${APT[@]}" upgrade
"${APT[@]}" install ca-certificates curl gnupg git openssh-client jq unzip zip ripgrep \
  postgresql-client uidmap dbus-user-session slirp4netns fuse-overlayfs iproute2

# --- Docker Engine from Docker's apt repository ---
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
"${APT[@]}" update
"${APT[@]}" install docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
  docker-compose-plugin docker-ce-rootless-extras

# The root daemon must not run: the agent uses its own rootless daemon
systemctl disable --now docker.service docker.socket
rm -f /var/run/docker.sock

# --- Optional: .NET SDK ---
if [ "$INSTALL_DOTNET" = "1" ]; then
  if ! "${APT[@]}" install "dotnet-sdk-${DOTNET_CHANNEL}"; then
    echo "apt has no dotnet-sdk-${DOTNET_CHANNEL}; using Microsoft's install script"
    tmp=$(mktemp)
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$tmp"
    bash "$tmp" --channel "$DOTNET_CHANNEL" --install-dir /usr/share/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet
    rm -f "$tmp"
  fi
  echo "NOTE: a project's global.json may pin an exact SDK version; see scripts/wsl/50-dotnet-sdk.sh"
fi

# --- Optional: Node.js LTS (NodeSource) ---
if [ "$INSTALL_NODE" = "1" ]; then
  tmp=$(mktemp)
  curl -fsSL https://deb.nodesource.com/setup_lts.x -o "$tmp"
  bash "$tmp"
  rm -f "$tmp"
  "${APT[@]}" install nodejs
fi

# Keep the agent's user services (rootless Docker) running without an open login session
loginctl enable-linger "$AGENT_USER"

echo
echo "Done. Next: .\\windows\\Invoke-InDistro.ps1 -User root -Script .\\scripts\\wsl\\30-sshd.sh"
