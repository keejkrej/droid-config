# droid-config

Portable [Factory Droid](https://docs.factory.ai) configuration: custom droids,
MCP servers, and a bridge that lets Droid delegate real work to external
agent CLIs (Grok Build, Cursor Agent) speaking the
[Agent Client Protocol](https://agentclientprotocol.com) (ACP).

## Layout

```
factory/
  droids/               custom droids (subagents), synced to ~/.factory/droids
    grok.md             relay subagent -> real Grok Build CLI (grok-composer-2.5-fast) via ACP
    cursor.md           relay subagent -> real Cursor Agent CLI (composer-2.5-fast) via ACP
    cursor-deep.md      relay subagent -> Cursor Agent CLI (claude-fable-5-high) for difficult tasks
    worker.md           general-purpose worker subagent
    scrutiny-feature-reviewer.md      (mission-mode only)
    user-testing-flow-validator.md    (mission-mode only)
  AGENTS.md               personal subagent-delegation prefs, synced to ~/.factory/AGENTS.md
  mcp.json               template merged into ~/.factory/mcp.json
  settings.json          template merged into ~/.factory/settings.json (customModels + default model)
mcp-bridges/
  acp-bridge/            generic ACP<->MCP bridge (Node, @modelcontextprotocol/sdk)
scripts/
  merge-json.mjs          non-destructive JSON merge helper used by setup.sh
  grok-usage.sh           check whether grok still has usage quota remaining
setup.sh                  installer/linker, safe to re-run
```

## Why a bridge?

Factory custom droids run Factory's own models; they can't hand the reasoning
loop to an arbitrary external CLI. Factory's MCP transport speaks MCP
JSON-RPC, not ACP JSON-RPC, so `grok agent stdio` / `cursor-agent acp` can't
be registered as an MCP server directly.

`mcp-bridges/acp-bridge` is a small MCP stdio server that spawns an ACP agent
subprocess, drives the ACP handshake (`initialize` -> `authenticate` ->
`session/new` -> `session/prompt`), and exposes the result as a single MCP
tool (`prompt`). The `grok`, `cursor`, and `cursor-deep` custom droids are
thin relays restricted to only that tool, so calling them via the Task tool
runs the actual external grok / cursor-agent process and returns its real
response. Each MCP server passes a `--model` flag to its underlying CLI so the
specific model (grok-composer-2.5-fast, composer-2.5-fast, or
claude-fable-5-high) is pinned at the ACP-bridge level.

## Prerequisites

- Linux with `bash`, `curl`, `node`/`npm` (18+)
- `grok` and `cursor-agent` CLIs **already installed and logged in** (this
  script only checks for them; see below if you still need to install them)
- An [ollama.com](https://ollama.com) account for the GLM cloud model (used
  as the default main agent model)

## Setup

```bash
./setup.sh
```

Safe to re-run. It will:
1. Verify Node.js/npm.
2. Install Ollama if missing, pull `glm-5.2:cloud` (the default main agent
   model) and `gemma4:31b-cloud` (for the optional vision-mcp server). If
   `ollama pull` fails, run `ollama signin` once and re-run this script.
3. Check for `grok` / `cursor-agent` on `PATH` (warns, doesn't install).
4. `npm install` the ACP bridge dependencies.
5. Symlink `mcp-bridges/acp-bridge`, `factory/droids/*.md`, and
   `factory/AGENTS.md` into `~/.factory/`, backing up any pre-existing files
   it would replace.
6. Merge `factory/mcp.json` / `factory/settings.json` into the live
   `~/.factory/mcp.json` / `~/.factory/settings.json` -- only touching the
   keys this repo owns (`mcpServers.{vision-mcp,grok-acp,cursor-acp,cursor-deep-acp}`,
   the `custom:glm-5.2:cloud-0` entry in `customModels`, and
   `sessionDefaultSettings.model`). Everything else in those files is left
   untouched.
7. Install the `grok-usage.sh` helper into `~/.factory/bin/`.
8. Remove any stale `glm.md` droid symlink from older setups.
9. Runs `droid mcp list` to confirm the servers connect.

If `grok` / `cursor-agent` aren't installed yet:

```bash
curl -fsSL https://x.ai/cli/install.sh | bash   # grok
curl https://cursor.com/install -fsS | bash     # cursor-agent (agent)
```

Then authenticate (`grok` interactive login, `cursor-agent login` or `agent
login`) before re-running `./setup.sh`.

## Usage

```
droid exec --auto high "Use the Task tool with subagent_type 'grok' to ..."
droid exec --auto high "Use the Task tool with subagent_type 'cursor' to ..."
droid exec --auto high "Use the Task tool with subagent_type 'cursor-deep' to ..."
```

or, in an interactive session, ask Droid to "run the subagent grok/cursor/cursor-deep
on <task>". The `worker` subagent works the same way via the Task tool.

The main agent runs on GLM-5.2 by default (configured in `settings.json` via
`sessionDefaultSettings.model`). Delegate to subagents for independent
opinions, parallel work, or different model strengths:

- **grok** (grok-composer-2.5-fast) — default for delegated work; fast and capable.
- **cursor** (composer-2.5-fast) — fallback when grok quota is exhausted.
- **cursor-deep** (claude-fable-5-high) — for difficult, high-stakes tasks.
- **worker** — general-purpose exploration/Q&A/research.

### Checking grok quota

Grok Build has subscription usage limits (SuperGrok / X Premium Plus). The
recommended workflow is to just try grok, and if its response contains a
usage-limit error, re-delegate the task to `cursor` or `cursor-deep`.

`scripts/grok-usage.sh` is a **manual diagnostic** that sends a trivial prompt
to grok and reports whether a usage-limit error appears. Run it occasionally or
when you suspect limits are the problem, not automatically before every
delegation (a point-in-time "OK" does not guarantee grok won't run out
mid-task, and xAI does not publish the exact reset window).

```bash
bash scripts/grok-usage.sh   # exit 0 = OK, exit 1 = out of quota, exit 2 = other error
```

## Notes

- Secrets (grok/cursor auth tokens, ollama.com login) live in each tool's own
  config (`~/.grok`, `~/.cursor` / cursor-agent's config, ollama's keyring)
  and are never touched or read by this repo.
- `factory/mcp.json` uses the literal token `$HOME` in bridge paths/commands;
  `scripts/merge-json.mjs` expands it to the real home directory when
  writing to `~/.factory/mcp.json`, so the repo stays portable across
  machines/users.
