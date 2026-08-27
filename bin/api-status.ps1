#!/usr/bin/env pwsh
# =============================================================================
# api-status.ps1 — Windows client: check the local end of an API tunnel
# =============================================================================
# Checks whether an OpenAI-compatible inference API answers on localhost.
# This works ONLY while an SSH tunnel to the remote GPU server is open:
#
#   ssh -N -L 8080:127.0.0.1:8080 user@SERVER_IP     # llama.cpp (default)
#   ssh -N -L 8000:127.0.0.1:8000 user@SERVER_IP     # vLLM
#
# No credentials are printed and no requests leave this PC except to
# 127.0.0.1 through the tunnel.
#
# Usage:
#   .\bin\api-status.ps1                 check llama.cpp (8080) and vLLM (8000)
#   .\bin\api-status.ps1 -Port 8080      check one specific local port
# =============================================================================

param(
    [int]$Port = 0,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: .\bin\api-status.ps1 [-Port <local-port>] [-Help]'
    Write-Host ''
    Write-Host 'Checks http://127.0.0.1:<port>/v1/models through an open SSH tunnel.'
    Write-Host 'Default ports come from %USERPROFILE%\.gpu-rental-kit\client.json'
    exit 0
}

. (Join-Path $PSScriptRoot 'grk-client-lib.ps1')

$cfg = Get-GrkClientConfig

if ($Port -gt 0) {
    $ports = @($Port)
} else {
    $ports = @([int]$cfg['LlamaCppPort'], [int]$cfg['VllmPort'])
}

Write-Host 'GPU Rental Kit — API tunnel status (LOCALHOST ONLY)'
Write-Host ''

$anyOk = $false
foreach ($p in $ports) {
    if ((Test-GrkTunnelApi -Port $p)) { $anyOk = $true }
}

Write-Host ''
if (-not $anyOk) {
    Write-GrkWarn 'No tunnel API reachable. Start a runtime on the server first (e.g. .\bin\ai-start.ps1 llama /path/model.gguf), then open a tunnel.'
    exit 1
}
exit 0
