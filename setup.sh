#!/usr/bin/env bash
# Idempotent setup for this Factory Droid configuration:
#   - Node.js (required by the merge script)
#   - Ollama + the GLM-5.2 cloud model (default main agent model)
#   - Links factory/AGENTS.md into ~/.factory/AGENTS.md (personal subagent prefs)
#   - Merges factory/mcp.json and factory/settings.json into the live Factory config
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTORY_DIR="${FACTORY_HOME:-$HOME/.factory}"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# 1. Node.js / npm (required to run the merge script)
# ---------------------------------------------------------------------------
log "Checking Node.js / npm"
if ! command -v node >/dev/null 2>&1 && [ -s "$HOME/.nvm/nvm.sh" ]; then
  warn "node not on PATH; trying nvm"
  # shellcheck disable=SC1091
  \. "$HOME/.nvm/nvm.sh"
fi
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  warn "node/npm not found. Install Node.js 18+ (e.g. https://github.com/nvm-sh/nvm) and re-run."
  exit 1
fi
ok "node $(node --version), npm $(npm --version)"

# ---------------------------------------------------------------------------
# 2. Ollama + GLM cloud model (default main agent model, set via settings.json)
# ---------------------------------------------------------------------------
log "Checking Ollama"
if ! command -v ollama >/dev/null 2>&1; then
  log "Installing Ollama"
  curl -fsSL https://ollama.com/install.sh | sh
else
  ok "ollama already installed ($(ollama --version 2>&1 | head -1))"
fi

if ! curl -fsS http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files ollama.service >/dev/null 2>&1; then
    warn "ollama.service isn't responding. Start it with: sudo systemctl enable --now ollama"
  else
    warn "Starting 'ollama serve' in the background (logs: $HOME/.ollama-serve.log)"
    nohup ollama serve >"$HOME/.ollama-serve.log" 2>&1 &
    disown
    sleep 2
  fi
fi

GLM_MODEL="glm-5.2:cloud"
log "Pulling $GLM_MODEL (requires an ollama.com account)"
if ollama pull "$GLM_MODEL"; then
  ok "$GLM_MODEL ready"
else
  warn "Could not pull $GLM_MODEL. Run 'ollama signin' to authenticate with ollama.com, then re-run this script."
fi

VISION_MODEL="gemma4:31b-cloud"
if ollama pull "$VISION_MODEL" >/dev/null 2>&1; then
  ok "$VISION_MODEL ready (used by the optional vision-mcp server)"
else
  warn "Could not pull $VISION_MODEL (optional, only needed for the vision-mcp server)"
fi

# ---------------------------------------------------------------------------
# 3. Link this repo into ~/.factory
# ---------------------------------------------------------------------------
link_path() {
  local target=$1 src=$2
  if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$src")" ]; then
    return
  fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    local backup="${target}.bak.$(date +%s)"
    mv "$target" "$backup"
    warn "Backed up existing $target -> $backup"
  fi
  mkdir -p "$(dirname "$target")"
  ln -sfn "$src" "$target"
}

log "Linking personal AGENTS.md into $FACTORY_DIR"
link_path "$FACTORY_DIR/AGENTS.md" "$REPO_DIR/factory/AGENTS.md"
ok "linked AGENTS.md"

# ---------------------------------------------------------------------------
# 4. Merge mcp.json / settings.json (non-destructive: only touches the keys
#    this repo owns -- mcpServers.vision-mcp, the glm-5.2 entry in
#    customModels, and sessionDefaultSettings.model)
# ---------------------------------------------------------------------------
log "Merging mcp.json and settings.json into $FACTORY_DIR"
node "$REPO_DIR/scripts/merge-json.mjs" mcp "$REPO_DIR/factory/mcp.json" "$FACTORY_DIR/mcp.json"
node "$REPO_DIR/scripts/merge-json.mjs" settings "$REPO_DIR/factory/settings.json" "$FACTORY_DIR/settings.json"
ok "config merged"

# ---------------------------------------------------------------------------
# 5. Verify
# ---------------------------------------------------------------------------
log "Verifying MCP servers"
if command -v droid >/dev/null 2>&1; then
  droid mcp list || true
else
  warn "'droid' CLI not found on PATH; skipping live verification."
fi

log "Done."
echo "Try:  droid exec --auto high \"Use the Task tool to delegate exploration of this repo to a subagent\""
