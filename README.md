# droid-config

Portable [Factory Droid](https://docs.factory.ai) configuration: custom droids,
MCP servers, and a bridge that lets Droid delegate real work to external
agent CLIs (Grok Build, Cursor Agent) speaking the
[Agent Client Protocol](https://agentclientprotocol.com) (ACP).

## Layout

```
factory/
  droids/               custom droids (subagents), synced to ~/.factory/droids
    fast.md             fast subagent: grok (grok-composer-2.5-fast) with cursor fallback (composer-2.5-fast)
    deep.md             deep subagent: cursor-agent (claude-fable-5-high) for difficult tasks
  AGENTS.md               personal subagent-delegation prefs, synced to ~/.factory/AGENTS.md
  mcp.json               template merged into ~/.factory/mcp.json
  settings.json          template merged into ~/.factory/settings.json (customModels + default model)
mcp-bridges/
  acp-bridge/            generic ACP<->MCP bridge (Node, @modelcontextprotocol/sdk)
scripts/
  merge-json.mjs          non-destructive JSON merge helper used by setup.sh
  grok-usage.sh           check whether grok still has usage quota remaining
  cursor-usage.sh          check whether cursor-agent still has usage quota remaining
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
tool (`prompt`). The `fast` and `deep` custom droids are thin relays
restricted to only that tool, so calling them via the Task tool runs the
actual external grok / cursor-agent process and returns its real response.
Each MCP server passes a `--model` flag to its underlying CLI so the specific
model (grok-composer-2.5-fast, composer-2.5-fast, or claude-fable-5-high) is
pinned at the ACP-bridge level.

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
5. Symlink `mcp-bridges/acp-bridge`, `factory/droids/fast.md`,
   `factory/droids/deep.md`, and `factory/AGENTS.md` into `~/.factory/`,
   backing up any pre-existing files they would replace.
6. Merge `factory/mcp.json` / `factory/settings.json` into the live
   `~/.factory/mcp.json` / `~/.factory/settings.json` -- only touching the
   keys this repo owns (`mcpServers.{vision-mcp,grok-acp,cursor-acp,cursor-deep-acp}`,
   the `custom:glm-5.2:cloud-0` entry in `customModels`, and
   `sessionDefaultSettings.model`). Everything else in those files is left
   untouched.
7. Install the `grok-usage.sh` and `cursor-usage.sh` helpers into `~/.factory/bin/`.
8. Remove every droid from `~/.factory/droids` other than `fast.md` and
   `deep.md` (cleans up stale files from older setups, including `worker.md`,
   `scrutiny-feature-reviewer.md`, `user-testing-flow-validator.md`,
   `glm.md`, `grok.md`, `cursor.md`, `cursor-deep.md`).
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
droid exec --auto high "Use the Task tool with subagent_type 'fast' to ..."
droid exec --auto high "Use the Task tool with subagent_type 'deep' to ..."
```

or, in an interactive session, ask Droid to "run the subagent fast/deep on
<task>".

The main agent runs on GLM-5.2 by default (configured in `settings.json` via
`sessionDefaultSettings.model`). It should **eagerly delegate** to subagents
for independent opinions, parallel work, exploration, search, verification, and
different model strengths. Only `fast` and `deep` are provided; `worker` and
any other subagent listed by the Task tool are leftovers and must not be used.

- **fast** (grok-composer-2.5-fast with cursor composer-2.5-fast fallback) —
  default for delegated work. The `fast` droid tries grok first and
  automatically falls back to cursor if grok hits a usage limit. Use liberally
  for research, codebase exploration, search, verification passes, and code
  review — subagents are a context-management primitive that keeps the main
  agent's context clean.
- **deep** (claude-fable-5-high) — for difficult, high-stakes tasks where
  maximum reasoning depth is needed.

For tasks with **independent, disjoint parts** (e.g. explore auth + DB + API
simultaneously), issue multiple `fast` Task calls in the same response — each
subagent owns a different scope (map-reduce pattern). Do not fan-out the same
task to N agents to pick the best (best-of-N is wasteful and not recommended
for production).

### Checking provider quota

Both Grok Build and Cursor Agent have subscription usage limits. The `fast`
droid handles grok-to-cursor fallback internally, so no pre-check is needed.
For manual diagnostics:

```bash
bash scripts/grok-usage.sh      # exit 0 = OK, exit 1 = out of quota, exit 2 = other error
bash scripts/cursor-usage.sh     # same exit codes
```

These are point-in-time checks and do not guarantee the provider won't run out
mid-task. Neither xAI nor Cursor publishes exact reset windows. Run them
occasionally or when you suspect limits are the problem.

## Notes

- Secrets (grok/cursor auth tokens, ollama.com login) live in each tool's own
  config (`~/.grok`, `~/.cursor` / cursor-agent's config, ollama's keyring)
  and are never touched or read by this repo.
- `factory/mcp.json` uses the literal token `$HOME` in bridge paths/commands;
  `scripts/merge-json.mjs` expands it to the real home directory when
  writing to `~/.factory/mcp.json`, so the repo stays portable across
  machines/users.
