# Idempotent setup for this Factory Droid configuration (Windows / PowerShell):
#   - Node.js (required by the merge script)
#   - Ollama + the GLM-5.2 cloud model (default main agent model)
#   - Links factory/AGENTS.md into ~/.factory/AGENTS.md (personal subagent prefs)
#   - Merges factory/mcp.json and factory/settings.json into the live Factory config
#   - Verifies MCP servers
[CmdletBinding()]
param(
  [string]$FactoryHome = (Join-Path $HOME ".factory"),
  [switch]$NoElevate
)

# ---------------------------------------------------------------------------
# Self-elevation: if not running as admin, relaunch with -Verb RunAs (UAC
# prompt). If the user denies the UAC prompt, continue non-elevated and fall
# back to copy mode for symlinks. Pass -NoElevate to skip this and stay
# non-elevated (useful for unattended runs).
# ---------------------------------------------------------------------------
if (-not $PSBoundParameters.ContainsKey("NoElevate")) {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Get-Process -Id $PID).Path  # the current pwsh/powershell exe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($PSBoundParameters.ContainsKey("FactoryHome")) {
      $psi.Arguments += " -FactoryHome `"$FactoryHome`""
    }
    $psi.Verb = "RunAs"
    $psi.UseShellExecute = $true
    $psi.WorkingDirectory = $PSScriptRoot
    try {
      $proc = [System.Diagnostics.Process]::Start($psi)
      $proc.WaitForExit()
      exit $proc.ExitCode
    } catch {
      Write-Host "!! UAC denied or unavailable ($($_.Exception.Message)); continuing non-elevated (symlinks will fall back to copies)." -ForegroundColor Yellow
    }
  }
}

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$RepoDir = $PSScriptRoot
$FactoryDir = $FactoryHome

function Log($msg)  { Write-Host "`n==> $msg" -ForegroundColor Blue }
function Ok($msg)   { Write-Host "OK $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "!! $msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# link_path: link $Target -> $Source, backing up an existing file/symlink.
# Windows symlinks require Developer Mode or admin; fall back to Copy-Item.
# ---------------------------------------------------------------------------
function Link-Path($Target, $Source) {
  $targetParent = Split-Path -Parent $Target
  if (-not (Test-Path $targetParent)) { New-Item -ItemType Directory -Path $targetParent -Force | Out-Null }

  $resolvedSource = (Resolve-Path $Source).Path

  # If a symlink already points at the source, nothing to do.
  if ((Get-Item $Target -ErrorAction SilentlyContinue).LinkType -eq "SymbolicLink") {
    $existing = (Get-Item $Target).Target
    if ($existing -and ((Resolve-Path $existing).Path) -eq $resolvedSource) { return }
  }

  # Back up anything existing.
  if (Test-Path $Target) {
    $backup = "$Target.bak.$([int][double]::Parse((Get-Date -UFormat %s)))"
    Move-Item $Target $backup -Force
    Warn "Backed up existing $Target -> $backup"
  }

  # Try symlink first; fall back to copy if the OS refuses (non-admin, no Dev Mode).
  try {
    New-Item -ItemType SymbolicLink -Path $Target -Value $resolvedSource -ErrorAction Stop | Out-Null
  } catch {
    Warn "Could not create symlink ($($_.Exception.Message)); copying instead."
    if (Test-Path $resolvedSource -PathType Container) {
      Copy-Item $resolvedSource $Target -Recurse -Force
    } else {
      Copy-Item $resolvedSource $Target -Force
    }
  }
}

# ---------------------------------------------------------------------------
# 1. Node.js / npm (required to run the merge script)
# ---------------------------------------------------------------------------
Log "Checking Node.js / npm"
$node = Get-Command node -ErrorAction SilentlyContinue
$npm  = Get-Command npm  -ErrorAction SilentlyContinue
if (-not $node -or -not $npm) {
  Warn "node/npm not found. Install Node.js 18+ (e.g. winget install OpenJS.NodeJS) and re-run."
  exit 1
}
Ok "node $(node --version), npm $(npm --version)"

# ---------------------------------------------------------------------------
# 2. Ollama + GLM cloud model (default main agent model, set via settings.json)
# ---------------------------------------------------------------------------
Log "Checking Ollama"
$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollama) {
  Log "Installing Ollama"
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget) {
    winget install --id Ollama.Ollama --accept-source-agreements --accept-package-agreements
  } else {
    Warn "winget not found. Install Ollama from https://ollama.com/download/windows, then re-run."
    exit 1
  }
  # Refresh PATH for this session after install.
  $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [Environment]::GetEnvironmentVariable("PATH", "User")
  $ollama = Get-Command ollama -ErrorAction SilentlyContinue
} else {
  Ok "ollama already installed ($(& ollama --version 2>&1 | Select-Object -First 1))"
}

# Ensure the Ollama service is responding.
$versionOk = $false
try { $null = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/version" -TimeoutSec 5; $versionOk = $true } catch {}

if (-not $versionOk) {
  Warn "Starting 'ollama serve' in the background (logs: $HOME\.ollama-serve.log)"
  Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden -RedirectStandardOutput "$HOME\.ollama-serve.log" -RedirectStandardError "$HOME\.ollama-serve.err.log"
  Start-Sleep -Seconds 2
}

$GlmModel = "glm-5.2:cloud"
Log "Pulling $GlmModel (requires an ollama.com account)"
try {
  & ollama pull $GlmModel
  Ok "$GlmModel ready"
} catch {
  Warn "Could not pull $GlmModel. Run 'ollama signin' to authenticate with ollama.com, then re-run this script."
}

$VisionModel = "gemma4:31b-cloud"
try {
  & ollama pull $VisionModel *> $null
  Ok "$VisionModel ready (used by the optional vision-mcp server)"
} catch {
  Warn "Could not pull $VisionModel (optional, only needed for the vision-mcp server)"
}

# ---------------------------------------------------------------------------
# 3. Link personal AGENTS.md into ~/.factory
# ---------------------------------------------------------------------------
Log "Linking personal AGENTS.md into $FactoryDir"
Link-Path (Join-Path $FactoryDir "AGENTS.md") (Join-Path $RepoDir "factory\AGENTS.md")
Ok "linked AGENTS.md"

# ---------------------------------------------------------------------------
# 4. Merge mcp.json / settings.json (non-destructive: only touches the keys
#    this repo owns -- mcpServers.vision-mcp, the glm-5.2 entry in
#    customModels, and sessionDefaultSettings.model)
# ---------------------------------------------------------------------------
Log "Merging mcp.json and settings.json into $FactoryDir"
& node (Join-Path $RepoDir "scripts\merge-json.mjs") mcp (Join-Path $RepoDir "factory\mcp.json") (Join-Path $FactoryDir "mcp.json")
& node (Join-Path $RepoDir "scripts\merge-json.mjs") settings (Join-Path $RepoDir "factory\settings.json") (Join-Path $FactoryDir "settings.json")
Ok "config merged"

# ---------------------------------------------------------------------------
# 5. Verify
# ---------------------------------------------------------------------------
Log "Verifying MCP servers"
if (Get-Command droid -ErrorAction SilentlyContinue) {
  & droid mcp list
} else {
  Warn "'droid' CLI not found on PATH; skipping live verification."
}

Log "Done."
Write-Host "Try:  droid exec --auto high `"Use the Task tool to delegate exploration of this repo to a subagent`""
