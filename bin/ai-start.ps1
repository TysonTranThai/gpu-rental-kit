#!/usr/bin/env pwsh
# =============================================================================
# ai-start.ps1 — Windows client: start Ollama, vLLM, or llama.cpp (REMOTE)
# =============================================================================
# Interactive session against the CONFIGURED REMOTE Linux NVIDIA GPU server.
# This does NOT inspect or use any GPU installed on this Windows PC.
#
# Usage:
#   .\bin\ai-start.ps1 [<args forwarded to the remote command>]
#
# Configure once first:  .\bootstrap.ps1 -RemoteHost <SERVER_IP> ...
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig
$argLine = (@($args) | ForEach-Object { ConvertTo-BashSingleQuoted "$_" }) -join ' '
$remote = 'ai-start' + $(if ($argLine) { " $argLine" } else { '' })

Write-GrkInfo ("{0} -> {1}@{2}:{3}" -f 'ai-start', $cfg['RemoteUser'], $cfg['RemoteHost'], $cfg['RemotePort'])
Write-GrkWarn 'Interactive remote session — close it to stop the selected runtime.'
exit (Invoke-GrkRemoteInteractive -Config $cfg -RemoteCommandLine $remote)
