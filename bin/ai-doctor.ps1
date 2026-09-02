#!/usr/bin/env pwsh
# =============================================================================
# ai-doctor.ps1 — Windows client: whole-stack health check (REMOTE)
# =============================================================================
# Runs ai-doctor on the CONFIGURED REMOTE Linux NVIDIA GPU server over SSH.
# This does NOT inspect any GPU or disk installed on this Windows PC.
#
# Usage:
#   .\bin\ai-doctor.ps1 [<args forwarded to the remote command>]
#   .\bin\ai-doctor.ps1 --json            machine-readable report
#
# Configure once first:  .\bootstrap.ps1 -RemoteHost <SERVER_IP> ...
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig
$argLine = (@($args) | ForEach-Object { ConvertTo-BashSingleQuoted "$_" }) -join ' '
$remote = 'ai-doctor' + $(if ($argLine) { " $argLine" } else { '' })

Write-GrkInfo ("{0} -> {1}@{2}:{3}" -f 'ai-doctor', $cfg['RemoteUser'], $cfg['RemoteHost'], $cfg['RemotePort'])
exit (Invoke-GrkRemoteCommand -Config $cfg -RemoteCommandLine $remote)
