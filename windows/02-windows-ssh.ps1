<#
.SYNOPSIS
  Step 6 (Windows): create the key VS Code uses to log in to the distro, authorize it for
  the agent user, and add a Host entry to your SSH config.

.DESCRIPTION
  - Creates %USERPROFILE%\.ssh\<WIN_SSH_KEY_NAME> if it does not exist. ssh-keygen asks for a
    passphrase: use one. This key grants access to the sandbox account.
  - Appends the public key to the agent user's authorized_keys (idempotent).
  - Adds a "Host <DISTRO>" block to %USERPROFILE%\.ssh\config if there is none.

.EXAMPLE
  .\windows\02-windows-ssh.ps1
#>
[CmdletBinding()]
param([string] $ConfigFile)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Config.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ConfigFile) { $ConfigFile = Join-Path $repoRoot 'config.env' }
$cfg = Get-SandboxConfig -ConfigFile $ConfigFile
$distro = $cfg['DISTRO']

if (-not (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)) {
    throw 'ssh-keygen.exe not found. Install the Windows OpenSSH Client (Settings > Optional features).'
}

$sshDir = Join-Path $env:USERPROFILE '.ssh'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
$keyPath = Join-Path $sshDir $cfg['WIN_SSH_KEY_NAME']

if (-not (Test-Path -LiteralPath $keyPath)) {
    Write-Host "Creating $keyPath (enter a passphrase when asked) ..."
    & ssh-keygen.exe -t ed25519 -f $keyPath -C "windows-to-$distro"
    if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen failed.' }
}
else {
    Write-Host "Using existing key $keyPath"
}

$pub = (Get-Content -LiteralPath "$keyPath.pub" -Raw).Trim()
if ($pub -notmatch '^ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9@._-]+)?$') {
    throw "Unexpected public key format in $keyPath.pub"
}

# Authorize the key for the agent user (idempotent)
$remoteScript = @"
set -eu
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
grep -qxF '$pub' ~/.ssh/authorized_keys || echo '$pub' >> ~/.ssh/authorized_keys
echo "authorized_keys now has `$(wc -l < ~/.ssh/authorized_keys) line(s)"
"@
& (Join-Path $PSScriptRoot 'Invoke-InDistro.ps1') -User $cfg['AGENT_USER'] -ScriptText $remoteScript -ConfigFile $ConfigFile
if ($LASTEXITCODE -ne 0) { throw 'Could not update authorized_keys in the distro.' }

# Host entry in the Windows ssh config
$sshConfig = Join-Path $sshDir 'config'
$hostPattern = '^\s*Host\s+' + [regex]::Escape($distro) + '\s*$'
$hasHost = (Test-Path -LiteralPath $sshConfig) -and (Select-String -LiteralPath $sshConfig -Pattern $hostPattern -Quiet)
if ($hasHost) {
    Write-Host "$sshConfig already has a 'Host $distro' entry; left unchanged."
}
else {
    $block = @(
        '',
        "Host $distro",
        '  HostName 127.0.0.1',
        "  Port $($cfg['SSH_PORT'])",
        "  User $($cfg['AGENT_USER'])",
        "  IdentityFile ~/.ssh/$($cfg['WIN_SSH_KEY_NAME'])",
        '  IdentitiesOnly yes',
        '  ForwardAgent no',
        '  ForwardX11 no'
    )
    Add-Content -LiteralPath $sshConfig -Encoding ascii -Value $block
    Write-Host "Added 'Host $distro' to $sshConfig"
}

Write-Host ''
Write-Host "Test it:  ssh $distro      (the distro must be running: wsl -d $distro -e true)"
