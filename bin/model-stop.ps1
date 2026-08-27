#!/usr/bin/env pwsh
# =============================================================================
# model-stop.ps1 — Windows client: stop the running model server (REMOTE)
# =============================================================================
# Runs model-stop on the CONFIGURED REMOTE Linux NVIDIA GPU server over SSH.
# This does NOT inspect any GPU installed on this Windows PC.
#
# Usage:
#   .\bin\model-stop.ps1 [<args forwarded to the remote command>]
#
# Configure once first:  .\bootstrap.ps1 -RemoteHost <SERVER_IP> ...
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig
$argLine = (@($args) | ForEach-Object { ConvertTo-BashSingleQuoted "$_" }) -join ' '
$remote = 'model-stop' + $(if ($argLine) { " $argLine" } else { '' })

Write-GrkInfo ("{0} -> {1}@{2}:{3}" -f 'model-stop', $cfg['RemoteUser'], $cfg['RemoteHost'], $cfg['RemotePort'])
exit (Invoke-GrkRemoteCommand -Config $cfg -RemoteCommandLine $remote)
