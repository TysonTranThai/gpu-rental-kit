#!/usr/bin/env pwsh
# =============================================================================
# gpu-status.ps1 — Windows client: one-screen GPU plus runtime status (REMOTE)
# =============================================================================
# Runs gpu-status on the CONFIGURED REMOTE Linux NVIDIA GPU server over SSH.
# This does NOT inspect any GPU installed on this Windows PC.
#
# Usage:
#   .\bin\gpu-status.ps1 [<args forwarded to the remote command>]
#
# Configure once first:  .\bootstrap.ps1 -RemoteHost <SERVER_IP> ...
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig
$argLine = (@($args) | ForEach-Object { ConvertTo-BashSingleQuoted "$_" }) -join ' '
$remote = 'gpu-status' + $(if ($argLine) { " $argLine" } else { '' })

Write-GrkInfo ("{0} -> {1}@{2}:{3}" -f 'gpu-status', $cfg['RemoteUser'], $cfg['RemoteHost'], $cfg['RemotePort'])
exit (Invoke-GrkRemoteCommand -Config $cfg -RemoteCommandLine $remote)
