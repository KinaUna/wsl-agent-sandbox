<#
.SYNOPSIS
  Step 1 (Windows): enable mirrored networking and create the dedicated distro.

.DESCRIPTION
  - Creates %USERPROFILE%\.wslconfig with networkingMode=mirrored if the file does not exist.
    An existing file is never edited; you get a warning instead.
  - Installs the distro under the name from config.env without launching it.
  - Does NOT run "wsl --shutdown" for you (it stops all your distros).

.EXAMPLE
  .\windows\01-create-distro.ps1
#>
[CmdletBinding()]
param([string] $ConfigFile)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Config.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ConfigFile) { $ConfigFile = Join-Path $repoRoot 'config.env' }
$cfg = Get-SandboxConfig -ConfigFile $ConfigFile
$distro = $cfg['DISTRO']

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'wsl.exe not found. Install WSL first: wsl --install --no-distribution'
}

# wsl.exe prints UTF-16; read it correctly, restore the console encoding afterwards
$oldEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.Encoding]::Unicode
try {
    Write-Host 'WSL version:'
    & wsl.exe --version | ForEach-Object { Write-Host "  $_" }

    $existing = & wsl.exe --list --quiet |
        ForEach-Object { ($_ -replace "`0", '').Trim() } |
        Where-Object { $_ }
}
finally {
    [Console]::OutputEncoding = $oldEncoding
}
if ($existing -contains $distro) {
    throw "A WSL distro named '$distro' already exists. Change DISTRO in config.env, or remove it with: wsl --unregister $distro (this deletes its data)."
}

# --- .wslconfig (global: applies to ALL WSL2 distros) ---
$wslconfig = Join-Path $env:USERPROFILE '.wslconfig'
$needsShutdown = $false
if (-not (Test-Path -LiteralPath $wslconfig)) {
    Set-Content -LiteralPath $wslconfig -Encoding ascii -Value @('[wsl2]', 'networkingMode=mirrored')
    Write-Host "Created $wslconfig with networkingMode=mirrored"
    $needsShutdown = $true
}
elseif (-not (Select-String -LiteralPath $wslconfig -Pattern '^\s*networkingMode\s*=\s*mirrored' -Quiet)) {
    Write-Warning "$wslconfig exists but does not set networkingMode=mirrored. Add this under [wsl2] yourself:  networkingMode=mirrored"
    $needsShutdown = $true
}
else {
    Write-Host "$wslconfig already enables mirrored networking."
}

# --- create the distro ---
Write-Host "Installing $($cfg['UBUNTU_DISTRO']) as '$distro' ..."
& wsl.exe --install -d $cfg['UBUNTU_DISTRO'] --name $distro --no-launch
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'wsl --install failed. If your WSL does not support --name, do this instead:'
    Write-Host "  wsl --install -d $($cfg['UBUNTU_DISTRO']) --no-launch"
    Write-Host "  wsl --export $($cfg['UBUNTU_DISTRO']) `$env:TEMP\base.tar"
    Write-Host "  wsl --import $distro <install-dir> `$env:TEMP\base.tar"
    Write-Host "  wsl --unregister $($cfg['UBUNTU_DISTRO'])   # optional: removes the original"
    throw 'Distro creation failed.'
}

Write-Host ''
Write-Host 'Next steps:'
if ($needsShutdown) {
    Write-Host '  1. wsl --shutdown        (applies .wslconfig; stops ALL running distros)'
}
Write-Host '  2. .\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\10-users-and-wslconf.sh'
