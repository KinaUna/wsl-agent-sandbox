#!/usr/bin/env bash
# Verification (run as the agent user): checks the containment properties and prints PASS/FAIL.
#
#   .\windows\Invoke-InDistro.ps1 -User agent -Script .\scripts\wsl\90-verify.sh
#
# Needs network for the Docker image pulls (hello-world, alpine). Exit code 1 if any check FAILs.
set -uo pipefail

: "${SSH_PORT:=2222}"
: "${OLLAMA_URL:=http://localhost:11434}"

fails=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
warn() { printf 'WARN  %s\n' "$1"; }
check() { # check "description" command...   (passes when the command succeeds)
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}
check_not() { # check_not "description" command...   (passes when the command fails)
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi
}

XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_RUNTIME_DIR
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"

echo "== Containment =="
if [ "$(id -u)" -ne 0 ]; then pass "running as non-root user '$(id -un)'"; else fail "run this as the agent user, not root"; fi
check_not "Windows drives are not mounted (/mnt/c/Windows absent)" test -e /mnt/c/Windows
check_not "cmd.exe is not available (interop off)" bash -c 'command -v cmd.exe'
check_not "no passwordless sudo" sudo -n true
if id -nG | tr ' ' '\n' | grep -Eqx 'sudo|docker|admin'; then
  fail "user is in a privileged group: $(id -nG)"
else
  pass "user is not in sudo/docker/admin groups"
fi

echo "== sshd =="
if command -v ss >/dev/null 2>&1; then
  addrs=$(ss -ltnH "sport = :${SSH_PORT}" 2>/dev/null | awk '{print $4}')
  if [ -z "$addrs" ]; then
    fail "sshd is not listening on port ${SSH_PORT}"
  elif grep -vq '^127\.0\.0\.1:' <<<"$addrs"; then
    fail "sshd listens beyond loopback: $(echo "$addrs" | tr '\n' ' ')"
  else
    pass "sshd listens only on 127.0.0.1:${SSH_PORT}"
  fi
else
  warn "ss not installed; skipped the sshd listener check"
fi

echo "== Docker (rootless) =="
rootless_ok=0
if command -v docker >/dev/null 2>&1; then
  if docker info --format '{{.SecurityOptions}}' 2>/dev/null | grep -qi rootless; then
    pass "docker daemon is rootless"
    rootless_ok=1
  else
    fail "docker daemon is not rootless, or not running (systemctl --user status docker)"
  fi
else
  fail "docker CLI not found"
fi
if [ "$rootless_ok" = "1" ]; then
  check "can run a container (hello-world)" docker run --rm hello-world
  check_not "a container cannot write to the distro's /etc via a bind mount" \
    docker run --rm -v /etc:/host-etc alpine sh -c 'touch /host-etc/sandbox-write-test'
fi

echo "== Other Docker daemons reachable from this distro? =="
socks=""
if [ -d /mnt/wsl ]; then
  socks=$(find /mnt/wsl -maxdepth 5 -name '*.sock' 2>/dev/null | grep -i docker || true)
fi
if [ -z "$socks" ]; then
  pass "no Docker sockets visible under /mnt/wsl"
else
  warn "Docker-like sockets under /mnt/wsl (Docker Desktop?); testing whether they are usable:"
  for s in $socks; do
    if timeout 5 docker -H "unix://$s" info >/dev/null 2>&1; then
      fail "a root-equivalent Docker daemon is reachable via $s (see docs/security-model.md)"
    else
      pass "socket not usable: $s"
    fi
  done
fi

echo "== Optional =="
if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 3 "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
    pass "Ollama reachable at ${OLLAMA_URL}"
  else
    warn "Ollama not reachable at ${OLLAMA_URL} (fine if you do not use local models)"
  fi
fi
if command -v ssh >/dev/null 2>&1; then
  if ssh -T -o BatchMode=yes -o ConnectTimeout=5 git@github.com 2>&1 | grep -q 'successfully authenticated'; then
    pass "GitHub SSH authentication works"
  else
    warn "GitHub SSH authentication not working yet (deploy key added?)"
  fi
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "All required checks passed."
else
  echo "${fails} check(s) FAILED."
  exit 1
fi
