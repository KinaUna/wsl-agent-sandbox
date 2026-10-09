#!/usr/bin/env bash
# Optional (run as the agent user): clone PROJECT_REPO into ~/<PROJECT_DIR>.
#
#   .\windows\Invoke-InDistro.ps1 -User agent -Script .\scripts\wsl\45-clone-project.sh
#   .\windows\Invoke-InDistro.ps1 -User agent -Script .\scripts\wsl\45-clone-project.sh -Env PROJECT_REPO=git@github.com:owner/other-repo.git
#
# Run it after the deploy key (printed by 40-agent-tools.sh) has been added on GitHub.
# Push or stash uncommitted work from your Windows copy first: the clone starts from GitHub.
set -euo pipefail

: "${PROJECT_REPO:=}"
: "${PROJECT_DIR:=projects}"

[ "$(id -u)" -ne 0 ] || { echo "ERROR: run this as the agent user, not root" >&2; exit 1; }
if [ -z "$PROJECT_REPO" ]; then
  echo "ERROR: set PROJECT_REPO in config.env (SSH URL, e.g. git@github.com:owner/repo.git)" >&2
  exit 1
fi

mkdir -p "$HOME/$PROJECT_DIR"
cd "$HOME/$PROJECT_DIR"

name=$(basename "$PROJECT_REPO" .git)
if [ -d "$name/.git" ]; then
  echo "$HOME/$PROJECT_DIR/$name already exists; fetching instead."
  git -C "$name" fetch --all --prune
else
  git clone "$PROJECT_REPO"
fi

echo
echo "Project folder: $HOME/$PROJECT_DIR/$name"
echo "Tip: if the repo has a global.json, run scripts/wsl/50-dotnet-sdk.sh for the pinned SDK."
