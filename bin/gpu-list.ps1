#!/usr/bin/env pwsh
# =============================================================================
# gpu-list.ps1 — Windows client: list every GPU on the remote server (REMOTE)
# =============================================================================
# Runs gpu-list on the CONFIGURED REMOTE Linux NVIDIA GPU server over SSH.
# This does NOT inspect any GPU installed on this Windows PC.
#
# Usage:
#   .\bin\gpu-list.ps1
#
# Configure once first:  .\bootstrap.ps1 -RemoteHost <SERVER_IP> ...
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig

Write-GrkInfo ("{0} -> {1}@{2}:{3}" -f 'gpu-list', $cfg['RemoteUser'], $cfg['RemoteHost'], $cfg['RemotePort'])
exit (Invoke-GrkRemoteCommand -Config $cfg -RemoteCommandLine 'gpu-list')
