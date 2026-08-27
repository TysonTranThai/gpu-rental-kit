#!/usr/bin/env pwsh
<#
.SYNOPSIS
    GPU Rental Kit — Windows LOCAL CLIENT bootstrap.

.DESCRIPTION
    Prepares a Windows PC to act as a CLIENT for a remote Linux NVIDIA GPU
    server running gpu-rental-kit:

      * detects prerequisites (Git, OpenSSH client, curl, optional tooling)
      * installs missing REQUIRED tools when safely possible (prefers winget)
      * creates %USERPROFILE%\.gpu-rental-kit\ and manages client.json
      * never gives a remote server access to this PC beyond your SSH session

    This PC does NOT need an NVIDIA GPU. The actual AI/GPU setup runs on the
    remote Linux server with ./bootstrap.sh --remote-gpu (from Linux/SSH).

.PARAMETER Help
    Show full help.

.PARAMETER Yes
    Non-interactive: assume defaults, do not prompt.

.PARAMETER CheckOnly
    Detect and report only; change nothing on this PC.

.PARAMETER RemoteHost
    Hostname/IP of the remote Linux GPU server; saved to client.json.

.PARAMETER RemotePort
    SSH port of the remote server (default 22).

.PARAMETER RemoteUser
    SSH username on the remote server (default root).

.EXAMPLE
    PS> .\bootstrap.ps1
    Interactive first run: detects tools, reports what is missing.

.EXAMPLE
    PS> .\bootstrap.ps1 -RemoteHost 203.0.113.7 -RemoteUser ubuntu
    Detect/install tools AND save the remote server connection details.

.NOTES
    Elevation is NOT required for normal use. Only installing the optional
    OpenSSH Client capability may require an Administrator PowerShell window;
    the script tells you explicitly instead of elevating silently.
#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Yes,
    [switch]$CheckOnly,
    [string]$RemoteHost = '',
    [int]$RemotePort = 22,
    [string]$RemoteUser = 'root'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
USAGE:
    PS> .\bootstrap.ps1 -Help                                        full help
    PS> .\bootstrap.ps1                                              interactive first run
    PS> .\bootstrap.ps1 -Yes                                         non-interactive
    PS> .\bootstrap.ps1 -CheckOnly                                   detect/report only, change nothing
    PS> .\bootstrap.ps1 -RemoteHost 203.0.113.7 -RemoteUser ubuntu   save connection details
    PS> .\bootstrap.ps1 -RemoteHost ... -RemotePort 2222             custom SSH port
#>

# ============================================================================
# Paths (works from any current directory)
# ============================================================================
$KitRoot    = $PSScriptRoot
$GrkDir     = Join-Path $env:USERPROFILE '.gpu-rental-kit'
$LogFile    = Join-Path $GrkDir ('install-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

function Write-GrkLog {
    param(
        [string]$Level,
        [string]$Message
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    try {
        Add-Content -LiteralPath $LogFile -Value $line -ErrorAction SilentlyContinue
    } catch {
        # Logging must never crash setup.
    }
}

function Show-GrkHelp {
    Get-Help -Detailed $PSCommandPath | Out-String | Write-Output
}

if ($Help) {
    Show-GrkHelp
    exit 0
}

# ============================================================================
# Helper: command presence
# ============================================================================
function Test-CmdExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-IsAdmin {
    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# Detection results table rows: Name, Kind(REQUIRED/OPTIONAL), Status, Detail
$detections = New-Object System.Collections.Generic.List[object]

function Add-Detection {
    param(
        [string]$Name,
        [string]$Kind,
        [string]$Status,
        [string]$Detail = ''
    )
    $script:detections.Add([pscustomobject]@{
        Name = $Name; Kind = $Kind; Status = $Status; Detail = $Detail
    })
}

# ============================================================================
# Banner
# ============================================================================
Write-Host ''
Write-Host '============================================================'
Write-Host '  GPU RENTAL KIT — Windows Local Client Bootstrap'
Write-Host '============================================================'
Write-Host ''
Write-Host '  This prepares THIS PC to CONNECT to a remote Linux NVIDIA'
Write-Host '  GPU server. No NVIDIA GPU is required or inspected here.'
Write-Host ''

New-Item -ItemType Directory -Path $GrkDir -Force | Out-Null
Write-GrkLog 'INFO' "bootstrap started (CheckOnly=$CheckOnly Yes=$Yes)"

# ============================================================================
# Step 1 — environment detection
# ============================================================================
Write-Host '-- Environment --'

$osInfo   = Get-CimInstance -ClassName Win32_OperatingSystem
$osLine   = '{0} ({1})' -f $osInfo.Caption, $osInfo.Version
$psVer    = $PSVersionTable.PSVersion.ToString()
$edition  = $PSVersionTable.PSEdition
$archBits = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'x86_64 (64-bit)' }
    'ARM64' { 'ARM64' }
    default { "$($env:PROCESSOR_ARCHITECTURE)" }
}
Write-Host ("  Windows      : {0}" -f $osLine)
Write-Host ("  PowerShell   : {0} ({1})" -f $psVer, $edition)
Write-Host ("  Architecture : {0}" -f $archBits)
Write-Host ("  Admin shell  : {0}" -f ((Test-IsAdmin) ? 'yes' : 'no'))
Write-GrkLog 'INFO' "windows=$osLine powershell=$psVer/$edition arch=$archBits"

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-GrkLog 'ERROR' 'PowerShell 5.1 or newer is required.'
    exit 1
}

# ============================================================================
# Step 2 — dependency detection
# ============================================================================
Write-Host ''
Write-Host '-- Dependency detection --'

$gitExists    = Test-CmdExists 'git'
$sshExists    = Test-CmdExists 'ssh'
$curlExists   = Test-CmdExists 'curl.exe'
$pythonExists = (Test-CmdExists 'py') -or (Test-CmdExists 'python')
$wingetExists = Test-CmdExists 'winget'

$wslStatus = 'unknown'
try {
    $wslOut = & wsl.exe --status 2>$null
    if ($LASTEXITCODE -eq 0 -and $wslOut) { $wslStatus = 'installed' }
} catch {
    $wslStatus = 'not installed'
}

Add-Detection 'Git'                'REQUIRED' $(if ($gitExists) {'OK'} else {'MISSING'}) $(if ($gitExists) { (& git --version) -join '' })
Add-Detection 'OpenSSH client'     'REQUIRED' $(if ($sshExists) {'OK'} else {'MISSING'}) 'powers ssh sessions to the GPU server'
Add-Detection 'curl'               'BUILT-IN' $(if ($curlExists) {'OK'} else {'MISSING'}) 'ships with Windows 10 1803+'
Add-Detection 'winget'             'RECOMMENDED' $(if ($wingetExists) {'OK'} else {'MISSING'}) 'used to install missing tools'
Add-Detection 'Python'             'OPTIONAL' $(if ($pythonExists) {'OK'} else {'NOT INSTALLED'}) 'only some local workflows need it'
Add-Detection 'WSL2'               'OPTIONAL' $wslStatus 'not required by gpu-rental-kit'
Add-Detection 'Docker Desktop'     'NOT REQUIRED' 'SKIPPED' 'never needed just to connect/use a remote GPU'

foreach ($d in $detections) {
    $mark = switch ($d.Status) {
        'OK'            { '[OK]' }
        'MISSING'       { if ($d.Kind -eq 'REQUIRED') { '[!!]' } else { '[--]' } }
        default         { '[--]' }
    }
    Write-Host ('  {0,-6} {1,-18} {2,-14} {3}' -f $mark, $d.Name, $d.Status, $d.Detail)
    Write-GrkLog 'INFO' ('detect {0} status={1} detail={2}' -f $d.Name, $d.Status, $d.Detail)
}

# ============================================================================
# Step 3 — install missing REQUIRED dependencies (idempotent)
# ============================================================================
if ($CheckOnly) {
    Write-Host ''
    Write-Host '-- CheckOnly: skipping any installation --'
    Write-GrkLog 'INFO' 'checkonly: no changes made'
} else {
    $missingRequired = @()
    foreach ($d in $detections) {
        if ($d.Kind -eq 'REQUIRED' -and $d.Status -eq 'MISSING') {
            $missingRequired += $d.Name
        }
    }

    foreach ($dep in $missingRequired) {
        Write-Host ''
        Write-Host "-- Installing missing required dependency: $dep --"
        switch ($dep) {

            'Git' {
                if (-not $wingetExists) {
                    Write-GrkLog 'WARN' 'Git missing and winget unavailable.'
                    Write-Host '  Install Git manually from https://git-scm.com/download/win , then re-run this script.'
                    continue
                }
                & winget install --id Git.Git -e --source winget `
                    --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -eq 0 -and (Test-CmdExists 'git')) {
                    Write-GrkLog 'INFO' 'installed Git via winget'
                    Add-Detection 'Git' 'REQUIRED' 'INSTALLED' 'via winget'
                } else {
                    Write-GrkLog 'ERROR' 'winget could not install Git. Install it manually: https://git-scm.com/download/win'
                    exit 1
                }
            }

            'OpenSSH client' {
                if (-not (Test-IsAdmin)) {
                    Write-GrkLog 'WARN' 'OpenSSH client missing; adding it needs an Administrator PowerShell.'
                    Write-Host '  Open PowerShell AS ADMINISTRATOR and run:'
                    Write-Host '    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0'
                    Write-Host '  Then re-run this script.'
                    exit 1
                }
                try {
                    Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0' -ErrorAction Stop
                    Write-GrkLog 'INFO' 'installed OpenSSH client capability'
                    Add-Detection 'OpenSSH client' 'REQUIRED' 'INSTALLED' 'windows capability'
                } catch {
                    Write-GrkLog 'ERROR' ("Could not add OpenSSH client capability: {0}" -f $_.Exception.Message)
                    exit 1
                }
            }

            default {
                Write-GrkLog 'WARN' ("Unhandled required dependency: {0}" -f $dep)
            }
        }
    }

    if (-not $missingRequired) {
        Write-Host ''
        Write-Host '-- All required dependencies already present (nothing installed) --'
    }
}

# Re-check the hard requirements after installation attempts.
foreach ($req in @(@('git','Git'), @('ssh','OpenSSH client'))) {
    if (-not (Test-CmdExists $req[0])) {
        Write-GrkLog 'ERROR' ("REQUIRED dependency still missing after setup: {0}. See messages above." -f $req[1])
        exit 1
    }
}

# ============================================================================
# Step 4 — client configuration (client.json), with backup-on-overwrite.
# Stores ONLY host/port/user identity needed to build ssh commands.
# Never stores credentials, keys, or secrets of any kind.
# ============================================================================
# === sample-client-json BEGIN ===
$sampleClientJson = @'
{
  "RemoteHost":   "",
  "RemotePort":   22,
  "RemoteUser":   "root",
  "LlamaCppPort": 8080,
  "VllmPort":     8000,
  "OllamaPort":   11434
}
'@
# === sample-client-json END ===

$GrkConfigFile = Join-Path $GrkDir 'client.json'
$configWritten = $false

function Save-ClientConfig {
    <# Writes client.json; backs up any previous version first. Never stores
       credentials — only host/port/user identity used to build ssh commands. #>
    param([hashtable]$Data)

    if (Test-Path -LiteralPath $GrkConfigFile) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPath = "${GrkConfigFile}.bak-${stamp}"
        Copy-Item -LiteralPath $GrkConfigFile -Destination $backupPath -Force
        Write-GrkLog 'INFO' ("backed up existing client.json -> {0}" -f (Split-Path -Leaf $backupPath))
        Write-Host "  Existing client.json backed up to $(Split-Path -Leaf $backupPath)"
    }

    $pairs = foreach ($key in ($Data.Keys | Sort-Object)) {
        if ($key -in @('RemotePort','LlamaCppPort','VllmPort','OllamaPort')) {
            '  "{0}": {1}' -f $key, [int]$Data[$key]
        } else {
            '  "{0}": "{1}"' -f $key, $Data[$key]
        }
    }
    ($('{'+ "`n" + (($pairs) -join ",`n") + "`n" + '}')) |
        Set-Content -LiteralPath $GrkConfigFile -Encoding UTF8

    Write-GrkLog 'INFO' 'wrote client.json'
    $script:configWritten = $true
}

$wantsRemoteSet = -not [string]::IsNullOrWhiteSpace($RemoteHost)

if (-not $CheckOnly) {
    if (-not $wantsRemoteSet -and -not $Yes -and -not (Test-Path -LiteralPath $GrkConfigFile)) {
        Write-Host ''
        $answer = Read-Host 'Configure a remote GPU server now? [y/N]'
        if ($answer -match '^[Yy]') {
            $RemoteHost = Read-Host '  Remote server IP/host '
            $userIn     = Read-Host '  SSH user [root] '
            $portIn     = Read-Host '  SSH port [22] '
            if ($userIn) { $RemoteUser = $userIn }
            if ($portIn) { $RemotePort = [int]$portIn }
            $wantsRemoteSet = $true
        }
    }

    if ($wantsRemoteSet) {
        Save-ClientConfig @{
            RemoteHost   = $RemoteHost
            RemotePort   = $RemotePort
            RemoteUser   = $RemoteUser
            LlamaCppPort = 8080
            VllmPort     = 8000
            OllamaPort   = 11434
        }
    } elseif (-not (Test-Path -LiteralPath $GrkConfigFile)) {
        # Leave a ready-to-edit placeholder so users can also fill it in manually.
        $sampleClientJson | Set-Content -LiteralPath $GrkConfigFile -Encoding UTF8
        Write-GrkLog 'INFO' 'wrote placeholder client.json (RemoteHost empty)'
        $configWritten = $true
    } else {
        Write-GrkLog 'INFO' 'client.json already present; left untouched'
    }
}

# ============================================================================
# Summary + next steps
# ============================================================================
Write-Host ''
Write-Host '============================================================'
if ($configWritten) {
    Write-Host "  Config directory: $GrkDir  (client.json written)"
} else {
    Write-Host "  Config directory: $GrkDir"
}
if ($CheckOnly) {
    Write-Host '  Mode: CHECK ONLY — nothing was changed on this PC.'
}
Write-Host '============================================================'
Write-Host ''
Write-Host 'Next steps:'
Write-Host ''
Write-Host '  1. On the REMOTE Linux GPU server (SSH in), run the real setup:'
Write-Host '       git clone https://github.com/TysonTranThai/gpu-rental-kit.git'
Write-Host '       cd gpu-rental-kit'
Write-Host '       ./bootstrap.sh --remote-gpu'
Write-Host ''
Write-Host '  2. Back on Windows, configure the connection (if you skipped it):'
Write-Host '       .\bootstrap.ps1 -RemoteHost <SERVER_IP> -RemoteUser <user> [-RemotePort <port>]'
Write-Host ''
Write-Host '  3. Use the remote from Windows:'
Write-Host '       .\bin\gpu-status.ps1              REMOTE GPU overview'
Write-Host '       .\bin\model-list.ps1              downloaded models'
Write-Host '       .\bin\ai-start.ps1 ollama llama3.1:8b'
Write-Host ''
Write-Host '  4. Reach the API through an SSH tunnel (recommended):'
Write-Host '       ssh -N -L 8080:127.0.0.1:8080 user@SERVER_IP'
Write-Host '       .\bin\api-status.ps1              verifies http://127.0.0.1:<port>/v1'
Write-Host ''
Write-Host '  Full guide: README.md  (see the "Windows Support" section)'
Write-Host ''

exit 0
