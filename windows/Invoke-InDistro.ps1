<#
.SYNOPSIS
  Runs a bash script inside the sandbox distro as a given user.

.DESCRIPTION
  Streams the script into a private temp file inside the distro (created with mktemp),
  runs it with the settings from config.env passed as environment variables, and deletes
  it afterwards. The script runs with your console attached, so prompts work.

  Why not "wsl ... bash -s < script"? A script read from stdin breaks as soon as any
  command inside it reads stdin, and PowerShell piping rewrites line endings.

.PARAMETER User
  Linux user to run as (root, the admin user, or the agent user).

.PARAMETER Script
  Path to a .sh file on Windows.

.PARAMETER ScriptText
  Inline bash text to run instead of a file.

.PARAMETER ConfigFile
  Path to config.env (default: config.env in the repo root).

.PARAMETER Env
  Extra KEY=value pairs, e.g. -Env SDK_VERSION=10.0.400

.EXAMPLE
  .\windows\Invoke-InDistro.ps1 -User root -Script .\scripts\wsl\10-users-and-wslconf.sh

.EXAMPLE
  .\windows\Invoke-InDistro.ps1 -User agent -ScriptText 'jq -r .sdk.version ~/projects/myrepo/global.json'
#>
[CmdletBinding(DefaultParameterSetName = 'File')]
param(
    [Parameter(Mandatory = $true)][string] $User,
    [Parameter(Mandatory = $true, ParameterSetName = 'File')][string] $Script,
    [Parameter(Mandatory = $true, ParameterSetName = 'Text')][string] $ScriptText,
    [string] $ConfigFile,
    [string[]] $Env = @()
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Config.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ConfigFile) { $ConfigFile = Join-Path $repoRoot 'config.env' }

$cfg = Get-SandboxConfig -ConfigFile $ConfigFile
foreach ($e in $Env) {
    if ($e -match '^([A-Za-z_][A-Za-z0-9_]*)=([A-Za-z0-9_.:/@+,-]*)$') {
        $cfg[$Matches[1]] = $Matches[2]
    }
    else {
        throw "Invalid -Env entry '$e' (use KEY=value; allowed characters: letters digits _ . : / @ + , -)"
    }
}
if ($User -notmatch '^[a-z_][a-z0-9_-]*$') { throw "Invalid user name '$User'" }

$distro = $cfg['DISTRO']
$envArgs = ($cfg.Keys | ForEach-Object { "$_=$($cfg[$_])" }) -join ' '

# Read the script and normalise to LF, UTF-8 without BOM
if ($PSCmdlet.ParameterSetName -eq 'File') {
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Script).Path)
}
else {
    $text = $ScriptText
}
$text = $text -replace "`r`n", "`n"
if (-not $text.EndsWith("`n")) { $text += "`n" }
$bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)

function Start-WslProcess {
    param([string] $Arguments, [bool] $RedirectIn, [bool] $RedirectOut)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'wsl.exe'
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $RedirectIn
    $psi.RedirectStandardOutput = $RedirectOut
    return [System.Diagnostics.Process]::Start($psi)
}

# 1. Stage: stream the script into a private temp file inside the distro
$stage = 'f=$(mktemp /tmp/wsl-agent-sandbox.XXXXXX) && cat > $f && echo $f'
$p1 = Start-WslProcess -Arguments "-d $distro -u $User -e sh -c `"$stage`"" -RedirectIn $true -RedirectOut $true
$p1.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
$p1.StandardInput.Close()
$stdout = $p1.StandardOutput.ReadToEnd()
$p1.WaitForExit()

$remote = ($stdout -split "`r?`n" |
    Where-Object { $_ -match '^/tmp/wsl-agent-sandbox\.[A-Za-z0-9]+$' } |
    Select-Object -Last 1)
if ($p1.ExitCode -ne 0 -or -not $remote) {
    throw "Could not stage the script in distro '$distro' as '$User'. Is the distro installed (wsl -l -v) and the user created? Output: $stdout"
}

# 2. Run it with the console attached, 3. always clean up
$code = 1
try {
    $p2 = Start-WslProcess -Arguments "-d $distro -u $User -e env $envArgs bash $remote" -RedirectIn $false -RedirectOut $false
    $p2.WaitForExit()
    $code = $p2.ExitCode
}
finally {
    $p3 = Start-WslProcess -Arguments "-d $distro -u $User -e rm -f $remote" -RedirectIn $false -RedirectOut $false
    $p3.WaitForExit()
}
exit $code
