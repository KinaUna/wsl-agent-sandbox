#!/usr/bin/env bash
# Step 4 (run as root): OpenSSH server on 127.0.0.1:<SSH_PORT>, key-only, agent user only.
#
#   .\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\30-sshd.sh
#
# Order matters: Ubuntu 24.04 starts sshd through ssh.socket on port 22 as soon as the
# package is installed, and with mirrored networking the distro shares ports with
# Windows. We therefore put the listen-address override in place BEFORE installing.
set -euo pipefail

: "${AGENT_USER:=agent}"
: "${SSH_PORT:=2222}"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run this as root" >&2; exit 1; }
[ "$(ps -p 1 -o comm= | tr -d ' ')" = "systemd" ] || { echo "ERROR: systemd is not PID 1" >&2; exit 1; }

# 1. Listen address on the socket unit (ignored if the unit does not exist yet)
mkdir -p /etc/systemd/system/ssh.socket.d
cat > /etc/systemd/system/ssh.socket.d/listen.conf <<EOF
[Socket]
ListenStream=
ListenStream=127.0.0.1:${SSH_PORT}
EOF
systemctl daemon-reload

# 2. Install. If this fails with "Could not execute systemctl", run: dpkg --configure -a
export DEBIAN_FRONTEND=noninteractive
apt-get -y -o Dpkg::Options::=--force-confold install openssh-server

# 3. Hardening: key-only, agent only, no forwarding extras
cat > /etc/ssh/sshd_config.d/10-sandbox-agent.conf <<EOF
Port ${SSH_PORT}
ListenAddress 127.0.0.1
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowUsers ${AGENT_USER}
X11Forwarding no
AllowAgentForwarding no
EOF

# 4. Start (socket-activated on Ubuntu 24.04, plain service otherwise)
if systemctl cat ssh.socket >/dev/null 2>&1; then
  systemctl daemon-reload
  systemctl enable ssh.socket
  systemctl restart ssh.socket
else
  systemctl enable ssh
  systemctl restart ssh
fi

sshd -t

# 5. Must listen on loopback only
addrs=$(ss -ltnH "sport = :${SSH_PORT}" | awk '{print $4}')
if [ -z "$addrs" ]; then
  echo "ERROR: nothing is listening on port ${SSH_PORT}" >&2
  exit 1
fi
if grep -vq '^127\.0\.0\.1:' <<<"$addrs"; then
  echo "ERROR: sshd listens beyond loopback:" >&2
  echo "$addrs" >&2
  exit 1
fi
echo "sshd listens on: $(echo "$addrs" | tr '\n' ' ')"

echo
echo "Done. Next: .\\windows\\Invoke-InDistro.ps1 -User ${AGENT_USER} -Script .\\scripts\\wsl\\40-agent-tools.sh"
