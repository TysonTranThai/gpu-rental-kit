# =============================================================================
# grk-client-lib.ps1 — shared helpers for GPU Rental Kit Windows client tools
# =============================================================================
# Every bin/*.ps1 command dot-sources this library. It provides:
#   - client configuration loading (client.json + GRK_* env overrides)
#   - honest remote-vs-local behavior (Windows has no local NVIDIA GPU path)
#   - SSH command execution against the configured remote Linux GPU server
#
# This is a LOCAL CLIENT helper only. It never touches the user's filesystem
# beyond the kit config directory, never stores credentials, and never gives
# the remote server access to local files, shell, or other host capabilities.
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GrkConfigDir = Join-Path $env:USERPROFILE '.gpu-rental-kit'
$script:GrkConfigFile = Join-Path $script:GrkConfigDir 'client.json'

function Write-GrkInfo {
    param([string]$Message)
    Write-Host "[grk] $Message"
}

function Write-GrkWarn {
    param([string]$Message)
    Write-Host "[grk][WARN] $Message" -ForegroundColor Yellow
}

function Write-GrkError {
    param([string]$Message)
    Write-Host "[grk][ERROR] $Message" -ForegroundColor Red
}

function Get-GrkClientConfig {
    <#
        Loads client configuration. Precedence:
          1. GRK_* environment variables (GRK_REMOTE_HOST, GRK_REMOTE_PORT,
             GRK_REMOTE_USER, GRK_LLAMACPP_PORT, GRK_VLLM_PORT, GRK_OLLAMA_PORT)
          2. %USERPROFILE%\.gpu-rental-kit\client.json (created by bootstrap.ps1)
        Returns a hashtable; callers use Assert-GrkRemoteConfigured to print
        setup guidance when no remote host is configured yet.
    #>
    $cfg = @{
        RemoteHost   = ''
        RemotePort   = 22
        RemoteUser   = 'root'
        LlamaCppPort = 8080
        VllmPort     = 8000
        OllamaPort   = 11434
    }

    if (Test-Path -LiteralPath $script:GrkConfigFile) {
        try {
            $json = Get-Content -LiteralPath $script:GrkConfigFile -Raw | ConvertFrom-Json
            foreach ($prop in @('RemoteHost','RemotePort','RemoteUser','LlamaCppPort','VllmPort','OllamaPort')) {
                if ($null -ne $json.$prop) { $cfg[$prop] = $json.$prop }
            }
        } catch {
            throw "Client configuration file is not valid JSON: $($script:GrkConfigFile) — re-run bootstrap.ps1 to regenerate it."
        }
    }

    if ($env:GRK_REMOTE_HOST)    { $cfg['RemoteHost']   = $env:GRK_REMOTE_HOST }
    if ($env:GRK_REMOTE_PORT)    { $cfg['RemotePort']   = [int]$env:GRK_REMOTE_PORT }
    if ($env:GRK_REMOTE_USER)    { $cfg['RemoteUser']   = $env:GRK_REMOTE_USER }
    if ($env:GRK_LLAMACPP_PORT)  { $cfg['LlamaCppPort'] = [int]$env:GRK_LLAMACPP_PORT }
    if ($env:GRK_VLLM_PORT)      { $cfg['VllmPort']     = [int]$env:GRK_VLLM_PORT }
    if ($env:GRK_OLLAMA_PORT)    { $cfg['OllamaPort']   = [int]$env:GRK_OLLAMA_PORT }

    return $cfg
}

function Assert-GrkRemoteConfigured {
    param([hashtable]$Config)
    if ([string]::IsNullOrWhiteSpace("$($Config['RemoteHost'])")) {
        Write-GrkError "No remote GPU server is configured."
        Write-Host ""
        Write-Host "  Windows commands inspect and control the REMOTE Linux NVIDIA GPU"
        Write-Host "  server. This PC does not need an NVIDIA GPU, and these commands"
        Write-Host "  do NOT inspect any locally installed GPU."
        Write-Host ""
        Write-Host "  Configure a remote first:"
        Write-Host "    PS> .\bootstrap.ps1 -RemoteHost <SERVER_IP> -RemoteUser <user> [-RemotePort <port>]"
        Write-Host ""
        Write-Host "  Or for one-off use without saving configuration:"
        Write-Host '    PS> $env:GRK_REMOTE_HOST="<SERVER_IP>"; $env:GRK_REMOTE_USER="<user>"'
        throw "remote-not-configured"
    }
}

function ConvertTo-BashSingleQuoted {
    <# Wraps a value as a POSIX-safe single-quoted string. #>
    param([AllowEmptyString()][string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Get-GrkBashLoginCommand {
    <# Wraps a command line so it runs under a login bash (loads ~/.profile,
       which sources ~/.bashrc and puts ~/ai/bin on PATH). #>
    param([string]$RemoteCommandLine)
    return "bash -lc " + (ConvertTo-BashSingleQuoted $RemoteCommandLine)
}

function Invoke-GrkRemoteCommand {
    <#
        Runs a bash command line on the configured remote server over SSH and
        streams output. Batch mode (stdin piped). Returns the ssh exit code.
    #>
    param(
        [hashtable]$Config,
        [string]$RemoteCommandLine,
        [string[]]$ExtraSshArgs = @()
    )
    Assert-GrkRemoteConfigured -Config $Config

    $sshArgs = @()
    if ([int]$Config['RemotePort'] -ne 22) { $sshArgs += @('-p', "$($Config['RemotePort'])") }
    $sshArgs += $ExtraSshArgs
    $sshArgs += ('{0}@{1}' -f $Config['RemoteUser'], $Config['RemoteHost'])
    $sshArgs += (Get-GrkBashLoginCommand -RemoteCommandLine $RemoteCommandLine)

    & ssh @sshArgs
    return $LASTEXITCODE
}

function Invoke-GrkRemoteInteractive {
    <#
        Opens an interactive SSH session running one command with a TTY
        (used by ai-start / model-run where the runtime expects stdin).
    #>
    param(
        [hashtable]$Config,
        [string]$RemoteCommandLine
    )
    Assert-GrkRemoteConfigured -Config $Config

    $sshArgs = @('-t')
    if ([int]$Config['RemotePort'] -ne 22) { $sshArgs += @('-p', "$($Config['RemotePort'])") }
    $sshArgs += ('{0}@{1}' -f $Config['RemoteUser'], $Config['RemoteHost'])
    $sshArgs += (Get-GrkBashLoginCommand -RemoteCommandLine $RemoteCommandLine)

    & ssh @sshArgs
    return $LASTEXITCODE
}

function Test-GrkTunnelApi {
    <#
        Checks whether an OpenAI-compatible API on localhost (usually reached
        through an SSH tunnel) responds. Returns $true/$false. Never prints
        request bodies or credentials.
    #>
    param(
        [int]$Port,
        [int]$TimeoutSeconds = 5
    )
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/models" `
            -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        if ($null -ne $resp -and $null -ne $resp.data) {
            Write-Host ("  API OK            http://127.0.0.1:{0}/v1  ({1} model(s))" -f $Port, @($resp.data).Count)
            return $true
        }
        Write-Host ("  API responded with an unexpected shape on port {0}" -f $Port)
        return $false
    } catch {
        Write-Host ("  API NOT REACHABLE http://127.0.0.1:{0}/v1" -f $Port)
        Write-Host ("  Open the tunnel first: ssh -N -L {0}:127.0.0.1:{0} user@SERVER_IP" -f $Port)
        return $false
    }
}
