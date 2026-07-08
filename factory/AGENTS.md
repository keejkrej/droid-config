# Personal Agent Preferences

## Main Agent Model

The default session model is **glm-5.2:cloud** (GLM-5.2 via Ollama Cloud), set in
`sessionDefaultSettings.model` in `settings.json`. This is a frontier-class open
coding/agentic model (SWE-bench Pro 62.1, Terminal-Bench 2.1 81.0), roughly between
Claude Opus 4.7 and Opus 4.8 in coding strength, with 1M context. Use it as the
primary engine for all work, delegating to subagents only when an independent
opinion, parallel execution, or a different model's strengths are needed.

## Subagent Delegation

Available custom subagents (via the Task tool): `fast` and `deep`. **There
are no others.** If the Task tool offers `worker` or any other subagent,
**do not use it** -- it is a leftover and not provided by this config. Use
only `fast` or `deep`.

- **`fast`** — delegates to **grok-composer-2.5-fast** (Grok Build CLI, xAI) first;
  if grok returns a usage-limit error, automatically falls back to
  **composer-2.5-fast** (Cursor Agent CLI). Same fast Composer 2.5 Fast model, two
  providers. **Default for delegated work** — quick lookups, parallel exploration,
  cross-checks, anything that benefits from speed.
- **`deep`** — delegates to **claude-fable-5-high** (Cursor Agent CLI, Fable 5 1M,
  high reasoning, no data retention). The strongest reasoning model available. Use
  for genuinely difficult, high-stakes tasks where maximum depth is needed and the
  main agent or `fast` aren't enough.

### When to delegate (MANDATORY -- read carefully)

**You must delegate.** The main agent keeps its own context small by offloading
intermediate work to subagents. Doing the work inline when a subagent applies is
**not** an optimization -- it is a failure mode that wastes your limited context
window and degrades later performance.

Subagents are a **context-management and parallelism primitive** — they shine
when there's high intermediate work (reading files, running searches, exploring)
but a small summary to return. **Eagerly delegate** to `fast` whenever ANY of
these apply:

- **Research & exploration** — codebase exploration, breadth-first information
  gathering, web research. The subagent reads 20+ files/pages; you get a concise
  summary instead of polluting your own context.
- **Search & lookup** — large grep/search across the repo, finding relevant code
  paths, locating definitions and usages.
- **Verification passes** — run lint, typecheck, tests, or build checks in a
  subagent so the output doesn't flood your context.
- **Code review** — a fresh-context review of a diff or PR, especially from a
  different model for an independent opinion.
- **Multi-file investigation** — any task that requires reading more than ~3 files
  you haven't already read in this session.

**The only valid reasons to stay inline** are:
- Quick single-file edits you can do with one Read + one Edit.
- Sequentially dependent steps where each step's input is the previous step's
  output and nothing in between is worth summarizing.
- Collaborative iteration with frequent back-and-forth with the user.
- You already have all needed file contents in your current context.

If you find yourself about to read a 4th file for a task, **stop and delegate to
`fast` instead.** If a task would produce more than ~100 lines of tool output,
**delegate it.** When in doubt, delegate.

### Parallel fan-out (map-reduce, not best-of-N)

When a task has **independent, disjoint parts** (e.g. explore the auth module
AND the DB layer AND the API surface), issue multiple `fast` Task calls **in the
same response** with each subagent owning a different scope. This is the
recommended "map-reduce" pattern: each agent works on a separate slice, you merge
their summaries.

**Do not** fan-out the *same* task to N agents and pick the best result
("best-of-N" / solve-first race). This is a research/eval technique that costs
3-15x tokens for no reliability gain in production. If you need a second opinion,
delegate to `deep` once, not `fast` five times.

### Delegation order

1. **Default:** delegate to `fast` (grok first, cursor fallback — handled internally
   by the droid).
2. **For difficult/high-stakes tasks** where depth matters more than speed: use
   `deep` (Fable 5 High).
3. **For independent second opinions:** use a different subagent than the one
   already tried (e.g. `fast` first, `deep` for a deep cross-check).

### Checking provider usage (manual diagnostics)

`scripts/grok-usage.sh` and `scripts/cursor-usage.sh` send trivial prompts to
each provider and report whether a usage-limit error appears. They are **manual
diagnostics only**, not something to run automatically before every delegation:

- A point-in-time "OK" result does not guarantee the provider won't run out
  mid-task.
- Neither xAI nor Cursor publishes exact reset windows, so an "exhausted" result
  has no reliable expiry either.
- The `fast` droid already handles grok-to-cursor fallback internally, so there
  is no need to pre-check. Run these scripts occasionally (or when you suspect
  limits are the problem) to confirm status.

### General guidelines

- **Always delegate** research, exploration, search, and verification to `fast`
  unless the task is a trivial single-step read/edit. The `fast` droid is cheap
  and handles provider fallback internally. **The main agent should almost never
  be the one doing broad exploration or running search/grep itself** -- that is
  what `fast` is for.
- Give each subagent the full task plus any necessary context in the prompt — they
  do not see this conversation.
- Use `deep` sparingly for genuinely difficult reasoning, not as a default.
- **Never** use `worker` or any subagent other than `fast` / `deep`. If the Task
  tool lists them, ignore them -- they are not provided by this config.
- Still do simple, single-step tasks yourself; don't delegate trivial reads/edits.
