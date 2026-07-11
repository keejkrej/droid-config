# droid-config

Portable [Factory Droid](https://docs.factory.ai) configuration: custom
subagent delegation preferences and an MCP server template, synced into
`~/.factory/`.

## Layout

```
factory/
  AGENTS.md               personal subagent-delegation prefs, synced to ~/.factory/AGENTS.md
  mcp.json               template merged into ~/.factory/mcp.json
  settings.json          template merged into ~/.factory/settings.json (customModels + default model)
scripts/
  merge-json.mjs          non-destructive JSON merge helper used by setup
setup.sh                  installer/linker for Linux/macOS, safe to re-run
setup.ps1                 installer/linker for Windows / PowerShell, safe to re-run
```

## What this config does

- Sets the default session model to **glm-5.2:cloud** (GLM-5.2 via Ollama
  Cloud) via `factory/settings.json`.
- Registers an optional **vision-mcp** server (Ollama-backed vision model)
  via `factory/mcp.json`.
- Installs `factory/AGENTS.md` as `~/.factory/AGENTS.md`, which instructs the
  main agent to **delegate eagerly to subagents** for research, exploration,
  search, verification, code review, and any multi-file investigation.
  Subagents are a context-management and parallelism primitive: they run in
  their own context and return a short summary, keeping the main agent's
  context lean. The AGENTS.md file is model- and droid-agnostic — it
  encourages delegation to whichever subagents are available in the session
  (built-in `worker`, or any custom droids you add separately).

## Prerequisites

- Linux with `bash`, `curl`, `node`/`npm` (18+) **or** Windows with PowerShell 5+ (pwsh 7+ recommended), `node`/`npm` (18+)
- An [ollama.com](https://ollama.com) account for the GLM cloud model (used
  as the default main agent model)

## Setup

**Linux / macOS:**

```bash
./setup.sh
```

**Windows / PowerShell:**

```powershell
pwsh setup.ps1
```

Safe to re-run. It will:
1. Verify Node.js/npm.
2. Install Ollama if missing, pull `glm-5.2:cloud` (the default main agent
   model) and `gemma4:31b-cloud` (for the optional vision-mcp server). If
   `ollama pull` fails, run `ollama signin` once and re-run this script.
3. Link `factory/AGENTS.md` into `~/.factory/`, backing up any pre-existing
   file it would replace. (Symlinks on Linux; symlinks on Windows where
   possible, falling back to copies if the OS refuses.)
4. Merge `factory/mcp.json` / `factory/settings.json` into the live
   `~/.factory/mcp.json` / `~/.factory/settings.json` — only touching the
   keys this repo owns (`mcpServers.vision-mcp`, the
   `custom:glm-5.2:cloud-0` entry in `customModels`, and
   `sessionDefaultSettings.model`). Everything else in those files is left
   untouched.
5. Runs `droid mcp list` to confirm the servers connect.

## Usage

The main agent runs on GLM-5.2 by default (configured in `settings.json` via
`sessionDefaultSettings.model`). Per `AGENTS.md`, it should **eagerly
delegate** to subagents for independent opinions, parallel work, exploration,
search, verification, and any multi-file investigation. Only stay inline for
quick single-file edits or tightly sequential steps.

For tasks with **independent, disjoint parts** (e.g. explore auth + DB + API
simultaneously), issue multiple subagent Task calls in the same response —
each subagent owns a different scope (map-reduce pattern). Do not fan-out the
same task to N agents to pick the best (best-of-N is wasteful and not
recommended for production).

## Notes

- `factory/mcp.json` uses the literal token `$HOME` in paths; `scripts/merge-json.mjs`
  expands it to the real home directory when writing to `~/.factory/mcp.json`, so the
  repo stays portable across machines/users.
