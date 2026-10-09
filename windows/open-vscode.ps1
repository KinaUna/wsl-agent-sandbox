<#
.SYNOPSIS
  Starts the distro (if needed) and opens a folder in VS Code over Remote - SSH.

.PARAMETER Folder
  Folder inside the distro. Default: /home/<AGENT_USER>/<PROJECT_DIR>

.EXAMPLE
  .\windows\open-vscode.ps1
  .\windows\open-vscode.ps1 -Folder /home/agent/projects/my-repo
#>
[CmdletBinding()]
param(
    [string] $Folder,
    [string] $ConfigFile
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Config.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ConfigFile) { $ConfigFile = Join-Path $repoRoot 'config.env' }
$cfg = Get-SandboxConfig -ConfigFile $ConfigFile
$distro = $cfg['DISTRO']

if (-not $Folder) { $Folder = "/home/$($cfg['AGENT_USER'])/$($cfg['PROJECT_DIR'])" }
if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    throw "The 'code' command is not on PATH. Reinstall VS Code with 'Add to PATH' enabled."
}

# Make sure the distro (and therefore sshd) is running
& wsl.exe -d $distro -e true
if ($LASTEXITCODE -ne 0) { throw "Could not start distro '$distro'." }

& code --remote "ssh-remote+$distro" $Folder
