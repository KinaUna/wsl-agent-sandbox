# Shared helper: reads config.env into an ordered dictionary with defaults applied.
# Usage (dot-source it):  . (Join-Path $PSScriptRoot 'Config.ps1')

function Get-SandboxConfig {
    param(
        [Parameter(Mandatory = $true)][string] $ConfigFile
    )

    $cfg = [ordered]@{}

    if (Test-Path -LiteralPath $ConfigFile) {
        foreach ($line in Get-Content -LiteralPath $ConfigFile) {
            # KEY=VALUE on its own line; value limited to a safe character set
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=([A-Za-z0-9_.:/@+,-]*)\s*$') {
                $cfg[$Matches[1]] = $Matches[2]
            }
        }
    }

    $defaults = [ordered]@{
        DISTRO            = 'sandbox-agent'
        UBUNTU_DISTRO     = 'Ubuntu-24.04'
        ADMIN_USER        = 'wsladmin'
        AGENT_USER        = 'agent'
        SSH_PORT          = '2222'
        WIN_SSH_KEY_NAME  = 'id_ed25519_sandbox_agent'
        INSTALL_DOTNET    = '0'
        DOTNET_CHANNEL    = '10.0'
        INSTALL_DOTNET_EF = '0'
        INSTALL_NODE      = '0'
        PROJECT_REPO      = ''
        PROJECT_DIR       = 'projects'
    }
    foreach ($key in $defaults.Keys) {
        if (-not $cfg.Contains($key) -or [string]::IsNullOrEmpty($cfg[$key])) {
            $cfg[$key] = $defaults[$key]
        }
    }

    return , $cfg
}
