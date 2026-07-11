# Personal Agent Preferences

## DELEGATION IS THE DEFAULT -- READ THIS FIRST

**You delegate by default. You stay inline only as the exception.**

The main agent (GLM-5.2) is strong, but its context window is finite and
precious. Every file you read, every search you run, every test output you
absorb eats into that budget and degrades your performance on later steps.
Subagents run in their own context and return only a short summary — that is
the whole point.

**Before you reach for a tool, ask: "Could a subagent do this and hand me a
summary?" If yes, delegate. The answer is yes far more often than you think.**

Hard rules — delegate to a subagent when ANY apply:
- You are about to read a **4th file** for the current task. Stop. Delegate.
- The task will produce **more than ~100 lines** of tool output. Delegate.
- You are exploring, searching, grepping, or mapping an unfamiliar area. Delegate.
- You are running lint / typecheck / tests / build. Delegate.
- You are reviewing a diff or PR. Delegate.
- You are doing research or a web lookup. Delegate.

The ONLY times you stay inline:
- One Read + one Edit on a single file you already know.
- A step whose input is the previous step's output, with nothing worth summarizing.
- Active back-and-forth with the user.
- You already have all needed content in context.

**When in doubt, delegate.** If you catch yourself reading file after file or
scrolling through long output, you have already failed — delegate immediately.

### Goal: maximize parallelization

The goal is not a fixed 50/50 split — it is **maximum parallelization**. At any
point in a non-trivial task, ask: "How many independent threads can I run at
once?" If there are 3 disjoint areas to investigate, fire 3 subagent Task calls
in the same response. If exploration and verification can overlap, start both
now. The main agent's job is to **fan out work, then merge results** — not to
serialize it by doing each piece inline. A healthy session has subagents
running in parallel while you plan the next step or talk to the user. If only
one thing is happening at a time and it is you doing it, you are serializing
work that should be parallel.

## Main Agent Model

The default session model is **glm-5.2:cloud** (GLM-5.2 via Ollama Cloud), set in
`sessionDefaultSettings.model` in `settings.json`. Frontier-class open
coding/agentic model (SWE-bench Pro 62.1, Terminal-Bench 2.1 81.0), roughly
between Claude Opus 4.7 and Opus 4.8 in coding strength, 1M context. Use it
directly for the small set of inline cases above; delegate the rest.

## Subagent Delegation

Subagents are a **context-management and parallelism primitive** — they shine
when there's high intermediate work (reading files, running searches, exploring)
but a small summary to return. **Eagerly delegate** whenever ANY of these apply:

- **Research & exploration** — codebase exploration, breadth-first information
  gathering, web research. The subagent reads 20+ files/pages; you get a concise
  summary instead of polluting your own context.
- **Search & lookup** — large grep/search across the repo, finding relevant code
  paths, locating definitions and usages.
- **Verification passes** — run lint, typecheck, tests, or build checks in a
  subagent so the output doesn't flood your context.
- **Code review** — a fresh-context review of a diff or PR, especially from
  a different model for an independent opinion.
- **Multi-file investigation** — any task that requires reading more than ~3 files
  you haven't already read in this session.

**The only valid reasons to stay inline** are:
- Quick single-file edits you can do with one Read + one Edit.
- Sequentially dependent steps where each step's input is the previous step's
  output and nothing in between is worth summarizing.
- Collaborative iteration with frequent back-and-forth with the user.
- You already have all needed file contents in your current context.

If you find yourself about to read a 4th file for a task, **stop and delegate
instead.** If a task would produce more than ~100 lines of tool output,
**delegate it.** When in doubt, delegate.

### Parallel fan-out (map-reduce, not best-of-N)

When a task has **independent, disjoint parts** (e.g. explore the auth module
AND the DB layer AND the API surface), issue multiple subagent Task calls **in
the same response** with each subagent owning a different scope. This is the
recommended "map-reduce" pattern: each agent works on a separate slice, you merge
their summaries.

**Do not** fan-out the *same* task to N agents and pick the best result
("best-of-N" / solve-first race). This is a research/eval technique that costs
3-15x tokens for no reliability gain in production. If you need a second opinion,
delegate once to a different subagent, not the same one five times.

### General guidelines

- **Always delegate** research, exploration, search, and verification unless the
  task is a trivial single-step read/edit. **The main agent should almost never
  be the one doing broad exploration or running search/grep itself** -- that is
  what subagents are for.
- Give each subagent the full task plus any necessary context in the prompt — they
  do not see this conversation.
- Still do simple, single-step tasks yourself; don't delegate trivial reads/edits.
