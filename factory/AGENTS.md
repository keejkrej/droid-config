# Personal Agent Preferences

## Main Agent Model

The default session model is **glm-5.2:cloud** (GLM-5.2 via Ollama Cloud), set in
`sessionDefaultSettings.model` in `settings.json`. This is a frontier-class open
coding/agentic model (SWE-bench Pro 62.1, Terminal-Bench 2.1 81.0), roughly between
Claude Opus 4.7 and Opus 4.8 in coding strength, with 1M context. Use it as the
primary engine for all work, delegating to subagents only when an independent
opinion, parallel execution, or a different model's strengths are needed.

## Subagent Delegation

Available custom subagents (via the Task tool): `grok`, `cursor`, `cursor-deep`, `worker`.

- **`grok`** — relays to the real Grok Build CLI (xAI) running **grok-composer-2.5-fast**
  (Cursor's Composer 2.5 Fast model, proxied by xAI). Fast and capable for general
  coding tasks. **Default choice** for delegated work, but subject to Grok Build's
  subscription usage limits (SuperGrok / X Premium Plus). When limits are exhausted
  the error message says so; fall back to `cursor`.
- **`cursor`** — relays to the real Cursor Agent CLI running **composer-2.5-fast**
  (Composer 2.5 Fast). Same fast model as grok, different provider. Use as the
  primary fallback when grok is out of quota, or for a cross-check from a different
  agent.
- **`cursor-deep`** — relays to the Cursor Agent CLI running **claude-fable-5-high**
  (Anthropic Fable 5 1M, high reasoning, no data retention). The strongest reasoning
  model available among subagents. Reserve for genuinely difficult, high-stakes tasks
  where maximum depth is needed and the main agent or fast subagents aren't enough.

### Delegation order

1. **Default:** delegate to `grok` (fast, good limits on SuperGrok).
2. **If grok's response contains a usage-limit error** (the message says
   "You've reached your free Grok Build usage limit" or similar): re-delegate
   the same task to `cursor`. Do not pre-check grok's quota before every call
   (see "Checking grok usage" below).
3. **For difficult/high-stakes tasks** where depth matters more than speed: use
   `cursor-deep` (Fable 5 High) instead of or in addition to the fast subagents.
4. **For independent second opinions:** use a different subagent than the one
   already tried (e.g. grok first, cursor-deep for a deep cross-check).

### Checking grok usage

`scripts/grok-usage.sh` sends a trivial prompt to grok in headless mode and
reports whether a usage-limit error appears. It is a **manual diagnostic only**,
not something to run automatically before every delegation:

- A point-in-time "OK" result does not guarantee grok won't run out mid-task.
- xAI does not publish the exact reset window (community reports range from
  hours to weekly depending on plan and timing), so an "exhausted" result has
  no reliable expiry either.
- Just try grok, and if the response contains a usage-limit error, fall back
  to `cursor` or `cursor-deep` for that task. Run the script occasionally
  (or when you suspect limits are the problem) to confirm status.

### General guidelines

- **Eagerly delegate** non-trivial work to subagents instead of doing it all
  yourself, defaulting to `grok` unless the task specifically needs deeper reasoning
  (then use `cursor-deep`). If grok returns a usage-limit error, re-delegate to
  `cursor` (same fast model, different provider).
- When a task has independent, parallelizable parts (e.g. exploring multiple areas
  of a codebase, getting a second opinion on a design/fix, running checks from a
  different model), issue multiple Task calls to subagents **in the same response**
  rather than sequentially.
- Give each subagent the full task plus any necessary context in the prompt — they
  do not see this conversation.
- Use `worker` for general-purpose exploration/Q&A/research when a specialized
  subagent isn't a better fit.
- Still do simple, single-step tasks yourself; don't delegate trivial reads/edits.
