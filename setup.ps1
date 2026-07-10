# Idempotent setup for this Factory Droid configuration (Windows / PowerShell):
#   - Node.js (required by the ACP bridge)
#   - Ollama + the GLM-5.2 cloud model (default main agent model)
#   - Verifies grok / cursor-agent CLIs are present (assumed pre-installed & logged in)
#   - Installs the ACP bridge deps and links it into ~/.factory/mcp-bridges
#   - Links custom droids (fast, deep) into ~/.factory/droids
#   - Links factory/AGENTS.md into ~/.factory/AGENTS.md (personal subagent prefs)
#   - Merges factory/mcp.json and factory/settings.json into the live Factory config
#   - Links the grok-usage and cursor-usage helper scripts (.ps1) into ~/.factory/bin
#   - Prunes non-provided droids, then verifies MCP servers
[CmdletBinding()]
param(
  [string]$FactoryHome = (Join-Path $HOME ".factory")
)

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
# 1. Node.js / npm (required to run the ACP bridge and the merge script)
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
# 3. grok / cursor-agent CLIs -- assumed already installed & authenticated
# ---------------------------------------------------------------------------
Log "Checking grok / cursor-agent CLIs"
if (Get-Command grok -ErrorAction SilentlyContinue) {
  Ok "grok found: $((Get-Command grok).Source)"
} else {
  Warn "grok CLI not found on PATH. Install via the xAI installer for your platform."
}
if (Get-Command cursor-agent -ErrorAction SilentlyContinue) {
  Ok "cursor-agent found: $((Get-Command cursor-agent).Source)"
} else {
  Warn "cursor-agent CLI not found on PATH. Install from https://cursor.com/install"
}

# ---------------------------------------------------------------------------
# 4. ACP bridge dependencies
# ---------------------------------------------------------------------------
Log "Installing ACP bridge dependencies"
Push-Location (Join-Path $RepoDir "mcp-bridges\acp-bridge")
& npm install --omit=dev --no-audit --no-fund
Pop-Location
Ok "acp-bridge dependencies installed"

# ---------------------------------------------------------------------------
# 5. Link this repo into ~/.factory
# ---------------------------------------------------------------------------
Log "Linking mcp-bridges/acp-bridge into $FactoryDir"
Link-Path (Join-Path $FactoryDir "mcp-bridges\acp-bridge") (Join-Path $RepoDir "mcp-bridges\acp-bridge")
Ok "linked acp-bridge"

Log "Linking custom droids (fast, deep) into $FactoryDir\droids"
foreach ($f in @("fast.md", "deep.md")) {
  Link-Path (Join-Path $FactoryDir "droids\$f") (Join-Path $RepoDir "factory\droids\$f")
}
Ok "linked: fast.md deep.md"

Log "Linking personal AGENTS.md into $FactoryDir"
Link-Path (Join-Path $FactoryDir "AGENTS.md") (Join-Path $RepoDir "factory\AGENTS.md")
Ok "linked AGENTS.md"

# ---------------------------------------------------------------------------
# 6. Merge mcp.json / settings.json (non-destructive: only touches the keys
#    this repo owns -- mcpServers.{vision-mcp,grok-acp,cursor-acp,cursor-deep-acp},
#    the glm-5.2 entry in customModels, and sessionDefaultSettings.model)
# ---------------------------------------------------------------------------
Log "Merging mcp.json and settings.json into $FactoryDir"
& node (Join-Path $RepoDir "scripts\merge-json.mjs") mcp (Join-Path $RepoDir "factory\mcp.json") (Join-Path $FactoryDir "mcp.json")
& node (Join-Path $RepoDir "scripts\merge-json.mjs") settings (Join-Path $RepoDir "factory\settings.json") (Join-Path $FactoryDir "settings.json")
Ok "config merged"

# ---------------------------------------------------------------------------
# 7. Install usage helper scripts (Windows .ps1 variants)
# ---------------------------------------------------------------------------
Log "Installing usage helper scripts"
Link-Path (Join-Path $FactoryDir "bin\grok-usage.ps1") (Join-Path $RepoDir "scripts\grok-usage.ps1")
Link-Path (Join-Path $FactoryDir "bin\cursor-usage.ps1") (Join-Path $RepoDir "scripts\cursor-usage.ps1")
Ok "linked grok-usage.ps1, cursor-usage.ps1 -> $FactoryDir\bin\"

# ---------------------------------------------------------------------------
# 8. Remove all droid files we don't provide (keep only fast.md / deep.md)
# ---------------------------------------------------------------------------
Log "Pruning non-provided droids from $FactoryDir\droids"
$droidsDir = Join-Path $FactoryDir "droids"
if (Test-Path $droidsDir) {
  Get-ChildItem -Path $droidsDir -Filter *.md | ForEach-Object {
    if ($_.Name -notin @("fast.md", "deep.md")) {
      Remove-Item $_.FullName -Force
      Ok "removed $($_.Name)"
    }
  }
}

# ---------------------------------------------------------------------------
# 9. Verify
# ---------------------------------------------------------------------------
Log "Verifying MCP servers"
if (Get-Command droid -ErrorAction SilentlyContinue) {
  & droid mcp list
} else {
  Warn "'droid' CLI not found on PATH; skipping live verification."
}

Log "Done."
Write-Host "Try:  droid exec --auto high `"Use the Task tool with subagent_type 'fast' to say hi`""
Write-Host "Try:  droid exec --auto high `"Use the Task tool with subagent_type 'deep' to say hi`""
Write-Host "Check grok quota:   pwsh scripts\grok-usage.ps1"
Write-Host "Check cursor quota: pwsh scripts\cursor-usage.ps1"
