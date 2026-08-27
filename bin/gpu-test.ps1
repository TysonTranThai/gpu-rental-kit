#!/usr/bin/env pwsh
# =============================================================================
# gpu-test.ps1 — Windows client: GPU compute tests and light benchmark (REMOTE)
# =============================================================================
# Runs gpu-test on the CONFIGURED REMOTE Linux NVIDIA GPU server over SSH.
# This does NOT inspect any GPU installed on this Windows PC.
#
# Usage:
#   .\bin\gpu-test.ps1 [<args forwarded to the remote command>]
#
# Configure once first:  .\bootstrap.ps1 -RemoteHost <SERVER_IP> ...
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig
$argLine = (@($args) | ForEach-Object { ConvertTo-BashSingleQuoted "$_" }) -join ' '
$remote = 'gpu-test' + $(if ($argLine) { " $argLine" } else { '' })

Write-GrkInfo ("{0} -> {1}@{2}:{3}" -f 'gpu-test', $cfg['RemoteUser'], $cfg['RemoteHost'], $cfg['RemotePort'])
exit (Invoke-GrkRemoteCommand -Config $cfg -RemoteCommandLine $remote)
