#!/usr/bin/env bash
# Optional (run as root): install an exact .NET SDK version next to the one from apt.
#
# Use when a project's global.json pins a version apt does not provide and VS Code's C#
# extension reports "global.json specifies SDK x.y.z, which is not installed".
#
# 1. Read the pinned version (as the agent user):
#      .\windows\Invoke-InDistro.ps1 -User agent -ScriptText 'jq -r .sdk.version ~/projects/<repo>/global.json'
# 2. Install it (as root):
#      .\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\50-dotnet-sdk.sh -Env SDK_VERSION=10.0.400
set -euo pipefail

: "${SDK_VERSION:?Set SDK_VERSION, e.g. -Env SDK_VERSION=10.0.400}"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run this as root" >&2; exit 1; }
command -v dotnet >/dev/null || {
  echo "ERROR: dotnet is not installed. Set INSTALL_DOTNET=1 in config.env and run 20-packages.sh first." >&2
  exit 1
}

# Install into the directory of the existing dotnet so every user finds the new SDK
dotnet_dir=$(dirname "$(readlink -f "$(command -v dotnet)")")
echo "Installing SDK ${SDK_VERSION} into ${dotnet_dir}"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$tmp"
bash "$tmp" --version "$SDK_VERSION" --install-dir "$dotnet_dir"

dotnet --list-sdks
echo
echo "In VS Code run: Developer: Reload Window"
