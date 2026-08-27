#!/usr/bin/env pwsh
# =============================================================================
# model-run.ps1 — Windows client: run a downloaded model (REMOTE)
# =============================================================================
# Interactive session against the CONFIGURED REMOTE Linux NVIDIA GPU server.
# This does NOT inspect or use any GPU installed on this Windows PC.
#
# Usage:
#   .\bin\model-run.ps1 [<args forwarded to the remote command>]
#
# Configure once first:  .\bootstrap.ps1 -RemoteHost <SERVER_IP> ...
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig
$argLine = (@($args) | ForEach-Object { ConvertTo-BashSingleQuoted "$_" }) -join ' '
$remote = 'model-run' + $(if ($argLine) { " $argLine" } else { '' })

Write-GrkInfo ("{0} -> {1}@{2}:{3}" -f 'model-run', $cfg['RemoteUser'], $cfg['RemoteHost'], $cfg['RemotePort'])
Write-GrkWarn 'Interactive remote session — close it to stop the selected runtime.'
exit (Invoke-GrkRemoteInteractive -Config $cfg -RemoteCommandLine $remote)
