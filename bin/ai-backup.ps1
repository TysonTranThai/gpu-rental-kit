#!/usr/bin/env pwsh
# =============================================================================
# ai-backup.ps1 — Windows client: back up the remote AI environment
# =============================================================================
# Runs ai-backup on the CONFIGURED REMOTE Linux NVIDIA GPU server over SSH.
# The backup tarball is created ON THE SERVER under ~/ai/backups.
#
# Usage:
#   .\bin\ai-backup.ps1                    back up config/scripts/manifests
#   .\bin\ai-backup.ps1 --include-models   include model files (slow)
#   .\bin\ai-backup.ps1 --list             list existing backups on the server
#   .\bin\ai-backup.ps1 -Download          back up AND copy the newest tarball
#                                          to this PC's current directory
#
# Credentials are never stored or transmitted beyond the normal ssh session.
# =============================================================================

param(
    [switch]$Download,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\bin\ai-backup.ps1 [--include-models | --list] [-Download] [-Help]'
    Write-Host ''
    Write-Host '  (no flags)          back up config/scripts/manifests on the remote server'
    Write-Host '  --include-models    include model files (slow)'
    Write-Host '  --list              list existing backups on the server'
    Write-Host '  -Download           after backing up, scp the newest tarball here'
    Write-Host '  -Help               show this help'
    exit 0
}

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig

$remoteArgs = (@($args) | Where-Object { "$_" -notin @('-Download') } |
    ForEach-Object { ConvertTo-BashSingleQuoted "$_" }) -join ' '
$remote = 'ai-backup' + $(if ($remoteArgs) { " $remoteArgs" } else { '' })

Write-GrkInfo ("ai-backup -> {0}@{1}:{2}" -f $cfg['RemoteUser'], $cfg['RemoteHost'], $cfg['RemotePort'])
$code = Invoke-GrkRemoteCommand -Config $cfg -RemoteCommandLine $remote
if ($code -ne 0 -or -not $Download) {
    if ($Download -and $code -ne 0) {
        Write-GrkWarn 'Remote backup failed — nothing to download.'
        return
    }
    exit $code
}

# --- download newest backup tarball ---
Write-Host ''
Write-GrkInfo 'Locating newest backup on the server...'
$listSshArgs = @()
if ([int]$cfg['RemotePort'] -ne 22) { $listSshArgs += @('-p', "$($cfg['RemotePort'])") }
$listSshArgs += ('{0}@{1}' -f $cfg['RemoteUser'], $cfg['RemoteHost'])
$listCmd = "ls -t `"`$HOME/ai/backups/`"ai-backup-*.tar.gz 2>/dev/null | head -n 1 | tr -d '\r'"

$latest = (& ssh @listSshArgs $listCmd | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace("$latest")) {
    Write-GrkWarn 'No ai-backup-*.tar.gz found on the server.'
    exit 1
}

Write-GrkInfo "Downloading $latest ..."
& scp -P $cfg['RemotePort'] ('{0}@{1}:{2}' -f $cfg['RemoteUser'], $cfg['RemoteHost'], $latest) .
if ($LASTEXITCODE -eq 0) {
    Write-GrkInfo ("Saved to this PC: {0}" -f (Split-Path -Leaf $latest))
} else {
    Write-GrkError 'scp download failed.'
}
exit $LASTEXITCODE
