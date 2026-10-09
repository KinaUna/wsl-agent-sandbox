#!/usr/bin/env bash
# Step 2 (run as root): create the admin and agent users and write /etc/wsl.conf.
#
#   .\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\10-users-and-wslconf.sh
#
# Settings come from config.env (see config.example.env); defaults below.
set -euo pipefail

: "${ADMIN_USER:=wsladmin}"
: "${AGENT_USER:=agent}"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run this as root" >&2; exit 1; }

# Ubuntu already has a group called "admin"; adduser creates a same-named group per user,
# so a user with a pre-existing group name fails with "The group `admin' already exists".
for u in "$ADMIN_USER" "$AGENT_USER"; do
  if getent group "$u" >/dev/null && ! id "$u" >/dev/null 2>&1; then
    echo "ERROR: a group named '$u' already exists; choose a different user name in config.env" >&2
    exit 1
  fi
done
[ "$ADMIN_USER" != "$AGENT_USER" ] || { echo "ERROR: ADMIN_USER and AGENT_USER must differ" >&2; exit 1; }

# Both accounts are created without a password. Set the admin password afterwards:
#   wsl -d <DISTRO> -u root passwd <ADMIN_USER>
id "$ADMIN_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$ADMIN_USER"
usermod -aG sudo "$ADMIN_USER"

id "$AGENT_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$AGENT_USER"
# The agent must have no privileged groups
for g in sudo docker admin; do
  if id -nG "$AGENT_USER" | tr ' ' '\n' | grep -qx "$g"; then
    gpasswd -d "$AGENT_USER" "$g"
  fi
done

# Rootless Docker needs subordinate UID/GID ranges; adduser normally creates them
if ! grep -q "^${AGENT_USER}:" /etc/subuid || ! grep -q "^${AGENT_USER}:" /etc/subgid; then
  usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$AGENT_USER"
fi

# WSL settings: systemd on, agent is the default login, no Windows drives, no interop
if [ -f /etc/wsl.conf ]; then
  cp /etc/wsl.conf "/etc/wsl.conf.bak.$(date +%s)"
fi
cat > /etc/wsl.conf <<EOF
[boot]
systemd=true

[user]
default=${AGENT_USER}

[automount]
enabled=false

[interop]
enabled=false
appendWindowsPath=false
EOF

echo
echo "Done. Next, from Windows PowerShell:"
echo "  1. wsl -d ${DISTRO:-<DISTRO>} -u root passwd ${ADMIN_USER}     # set the admin password"
echo "  2. wsl --terminate ${DISTRO:-<DISTRO>}                         # apply wsl.conf"
echo "  3. .\\windows\\Invoke-InDistro.ps1 -User root -Script .\\scripts\\wsl\\20-packages.sh"
