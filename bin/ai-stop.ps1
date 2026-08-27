#!/usr/bin/env pwsh
# =============================================================================
# ai-stop.ps1 — Windows client: stop the active AI runtime (REMOTE)
# =============================================================================
# Runs ai-stop on the CONFIGURED REMOTE Linux NVIDIA GPU server over SSH.
# This does NOT inspect or control anything on this Windows PC.
#
# Usage:
#   .\bin\ai-stop.ps1
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig

Write-GrkInfo ("ai-stop -> {0}@{1}:{2}" -f $cfg['RemoteUser'], $cfg['RemoteHost'], $cfg['RemotePort'])
exit (Invoke-GrkRemoteCommand -Config $cfg -RemoteCommandLine 'ai-stop')
