#!/usr/bin/env pwsh
# =============================================================================
# model-download.ps1 — Windows client: download an alias, Hugging Face ID, or Ollama model (REMOTE)
# =============================================================================
# Runs model-download on the CONFIGURED REMOTE Linux NVIDIA GPU server over SSH.
# This does NOT inspect any GPU installed on this Windows PC.
#
# Usage:
#   .\bin\model-download.ps1 [<args forwarded to the remote command>]
#
# Configure once first:  .\bootstrap.ps1 -RemoteHost <SERVER_IP> ...
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig
$argLine = (@($args) | ForEach-Object { ConvertTo-BashSingleQuoted "$_" }) -join ' '
$remote = 'model-download' + $(if ($argLine) { " $argLine" } else { '' })

Write-GrkInfo ("{0} -> {1}@{2}:{3}" -f 'model-download', $cfg['RemoteUser'], $cfg['RemoteHost'], $cfg['RemotePort'])
exit (Invoke-GrkRemoteCommand -Config $cfg -RemoteCommandLine $remote)
