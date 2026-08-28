#!/usr/bin/env pwsh
# =============================================================================
# gpu-topology.ps1 — Windows client: GPU interconnect of the remote server (REMOTE)
# =============================================================================
# Runs gpu-topology on the CONFIGURED REMOTE Linux NVIDIA GPU server over SSH.
# This does NOT inspect any GPU installed on this Windows PC.
#
# Usage:
#   .\bin\gpu-topology.ps1
#
# Configure once first:  .\bootstrap.ps1 -RemoteHost <SERVER_IP> ...
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig

Write-GrkInfo ("{0} -> {1}@{2}:{3}" -f 'gpu-topology', $cfg['RemoteUser'], $cfg['RemoteHost'], $cfg['RemotePort'])
exit (Invoke-GrkRemoteCommand -Config $cfg -RemoteCommandLine 'gpu-topology')
